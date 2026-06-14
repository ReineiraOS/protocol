import { Contract, zeroPadValue } from "ethers";
import { CCTP_TOKEN_MESSENGER_ABI, ERC20_ABI } from "../constants/abis.js";
import {
  CCTP_ETHEREUM_SEPOLIA,
  CCTP_BASE_SEPOLIA,
  CCTP_ARBITRUM_SEPOLIA_DOMAIN,
  CHAIN_ID_ETHEREUM_SEPOLIA,
  CHAIN_ID_BASE_SEPOLIA,
} from "../constants/addresses.js";
import type { NetworkAddresses, TransactionResult, BridgeBurnResult } from "../types/index.js";
import { TransactionFailedError, ValidationError } from "../errors/index.js";
import { encodeHookData, padAddress } from "../utils/encoding.js";
import type { ethers } from "ethers";

/** @internal */
export interface BridgeFundParams {
  escrowId: bigint;
  sourceRpc: string;
  amount: bigint;
  sourceSigner?: ethers.Signer;
  destinationSigner: ethers.Signer;
}

/** Health status of the coordinator and operator network. */
export interface CoordinatorHealth {
  /** Whether the coordinator is reachable. */
  reachable: boolean;
  /** Number of operators connected to the coordinator. */
  connectedOperators: number;
  /** Operator addresses currently connected. */
  operators: string[];
}

// Known source chain configs by RPC URL pattern
function detectSourceChain(rpcUrl: string) {
  if (rpcUrl.includes("base")) {
    return { cctp: CCTP_BASE_SEPOLIA, chainId: CHAIN_ID_BASE_SEPOLIA, name: "Base Sepolia" };
  }
  return {
    cctp: CCTP_ETHEREUM_SEPOLIA,
    chainId: CHAIN_ID_ETHEREUM_SEPOLIA,
    name: "Ethereum Sepolia",
  };
}

export class BridgeModule {
  private readonly addresses: NetworkAddresses;
  private coordinatorUrl: string | null = null;

  constructor(addresses: NetworkAddresses) {
    this.addresses = addresses;
  }

  /** @internal */
  setCoordinatorUrl(url: string): void {
    this.coordinatorUrl = url.replace(/\/+$/, "");
  }

  /** Whether a coordinator URL is configured. */
  get isCoordinatorConfigured(): boolean {
    return this.coordinatorUrl !== null;
  }

  /**
   * Check coordinator health and connected operator count.
   */
  async checkHealth(): Promise<CoordinatorHealth> {
    if (!this.coordinatorUrl) {
      return { reachable: false, connectedOperators: 0, operators: [] };
    }

    try {
      const response = await fetch(`${this.coordinatorUrl}/operators/stats`);
      if (!response.ok) {
        return { reachable: false, connectedOperators: 0, operators: [] };
      }
      const data = (await response.json()) as {
        subscribedCount: number;
        operators: string[];
      };
      return {
        reachable: true,
        connectedOperators: data.subscribedCount,
        operators: data.operators ?? [],
      };
    } catch {
      return { reachable: false, connectedOperators: 0, operators: [] };
    }
  }

  /**
   * Initiate a cross-chain fund via CCTP and submit to the coordinator for relay.
   * Auto-detects source chain (Ethereum Sepolia or Base Sepolia) from the RPC URL.
   */
  async fundEscrowCrossChain(params: BridgeFundParams): Promise<BridgeBurnResult> {
    if (!params.sourceSigner) {
      throw new ValidationError("Cross-chain funding requires a source chain signer.");
    }
    const sourceSigner = params.sourceSigner;

    // Auto-detect source chain from RPC URL
    const source = detectSourceChain(params.sourceRpc);

    const usdc = new Contract(source.cctp.usdc, ERC20_ABI, sourceSigner);
    const tokenMessenger = new Contract(
      source.cctp.tokenMessenger,
      CCTP_TOKEN_MESSENGER_ABI,
      sourceSigner,
    );

    const hookData = encodeHookData(params.escrowId);
    const mintRecipient = padAddress(this.addresses.escrowReceiver);

    // Approve USDC spending
    const approveTx = await usdc.approve(source.cctp.tokenMessenger, params.amount);
    await approveTx.wait();
    // Wait for nonce to propagate on fast L2s
    await new Promise((r) => setTimeout(r, 2000));

    // Burn USDC via CCTP
    const tx = await tokenMessenger.depositForBurnWithHook(
      params.amount,
      CCTP_ARBITRUM_SEPOLIA_DOMAIN,
      mintRecipient,
      source.cctp.usdc,
      zeroPadValue("0x0000000000000000000000000000000000000000", 32),
      params.amount / 100n || 1n, // maxFee — 1% of amount (required by Circle attestation)
      1000, // minFinalityThreshold
      hookData,
      { gasLimit: 300_000n },
    );
    const receipt = await tx.wait();
    if (!receipt || receipt.status === 0) {
      throw new TransactionFailedError("CCTP depositForBurnWithHook failed", {
        txHash: receipt?.hash,
      });
    }

    const burnTx: TransactionResult = {
      hash: receipt.hash,
      blockNumber: receipt.blockNumber,
      gasUsed: receipt.gasUsed,
    };

    // Submit to coordinator for operator relay
    let relayTaskId: string | undefined;
    if (this.coordinatorUrl) {
      relayTaskId = await this.submitToCoordinator(receipt.hash, source.chainId);
    }

    return { burnTx, relayTaskId };
  }

  /**
   * Submit a CCTP burn tx to the coordinator for operator relay.
   */
  async submitToCoordinator(txHash: string, sourceChainId?: number): Promise<string> {
    if (!this.coordinatorUrl) {
      throw new ValidationError(
        "coordinatorUrl not configured. Pass it in SDKConfig or call bridge.setCoordinatorUrl().",
      );
    }

    const body = {
      transactionHash: txHash,
      sourceChainId: sourceChainId ?? CHAIN_ID_ETHEREUM_SEPOLIA,
    };

    const response = await fetch(`${this.coordinatorUrl}/bridges/cctp/transactions`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(body),
    });

    if (!response.ok) {
      const text = await response.text().catch(() => "");
      throw new TransactionFailedError(
        `Coordinator rejected burn submission (HTTP ${response.status}): ${text}`,
      );
    }

    const result = (await response.json()) as { id: string; status: string; message: string };
    return result.id;
  }
}
