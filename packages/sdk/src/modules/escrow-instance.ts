import { Contract, ZeroAddress } from "ethers";
import type { FHEClient } from "../crypto/fhe.js";
import { CONFIDENTIAL_ESCROW_ABI, FHERC20_ABI, CONDITION_RESOLVER_ABI } from "../constants/abis.js";
import type {
  NetworkAddresses,
  PollOptions,
  FundOptions,
  FundResult,
  SettlementResult,
  TransactionResult,
  ApprovalOptions,
} from "../types/index.js";
import { TransactionFailedError, TimeoutError, ApprovalRequiredError } from "../errors/index.js";
import { pollUntil } from "../utils/polling.js";
import type { BridgeModule } from "./bridge.js";
import type { CoverageInstance } from "./coverage-instance.js";
import type { ethers } from "ethers";

const DEFAULT_GAS_BUFFER = 1.3;
const FALLBACK_GAS_LIMIT = 3_000_000n;
const DEFAULT_SETTLEMENT_TIMEOUT = 600_000;

function toTxResult(receipt: ethers.TransactionReceipt): TransactionResult {
  return { hash: receipt.hash, blockNumber: receipt.blockNumber, gasUsed: receipt.gasUsed };
}

async function estimateGas(contract: Contract, method: string, args: unknown[]): Promise<bigint> {
  try {
    const estimate = await contract[method].estimateGas(...args);
    return BigInt(Math.ceil(Number(estimate) * DEFAULT_GAS_BUFFER));
  } catch {
    return FALLBACK_GAS_LIMIT;
  }
}

export class EscrowInstance {
  public readonly id: bigint;
  public readonly createTx?: TransactionResult;
  public readonly coverage?: CoverageInstance;

  private readonly escrowContract: Contract;
  private readonly tokenContract: Contract;
  private readonly fhe: FHEClient;
  private readonly addresses: NetworkAddresses;
  private readonly signer: ethers.Signer;
  private bridgeModule: BridgeModule | null = null;

  /** @internal */
  constructor(
    escrowId: bigint,
    signer: ethers.Signer,
    fhe: FHEClient,
    addresses: NetworkAddresses,
    opts?: { createTx?: TransactionResult; coverage?: CoverageInstance; bridge?: BridgeModule },
  ) {
    this.id = escrowId;
    this.signer = signer;
    this.fhe = fhe;
    this.addresses = addresses;
    this.createTx = opts?.createTx;
    this.coverage = opts?.coverage;
    this.bridgeModule = opts?.bridge ?? null;
    this.escrowContract = new Contract(addresses.escrow, CONFIDENTIAL_ESCROW_ABI, signer);
    this.tokenContract = new Contract(addresses.confidentialUSDC, FHERC20_ABI, signer);
  }

  async exists(): Promise<boolean> {
    return this.escrowContract.exists(this.id);
  }

  // ─── Fund ─────────────────────────────────────────────────

  /**
   * Fund this escrow. Routes automatically based on options:
   *
   * **Local funding** (same chain):
   * ```ts
   * await escrow.fund(sdk.usdc(1000), { autoApprove: true });
   * ```
   *
   * **Cross-chain funding** (CCTP from another chain):
   * ```ts
   * await escrow.fund(sdk.usdc(1000), {
   *   crossChain: { sourceRpc: "...", sourcePrivateKey: "..." },
   * });
   * ```
   *
   * **Cross-chain + wait for operator settlement**:
   * ```ts
   * const result = await escrow.fund(sdk.usdc(1000), {
   *   crossChain: { sourceRpc: "...", sourcePrivateKey: "..." },
   *   waitForSettlement: true,
   * });
   * console.log("Settled by:", result.settlement!.payer);
   * ```
   *
   * @param amount - Amount in USDC base units (6 decimals). Use sdk.usdc() for convenience.
   * @param options - Funding options. See FundOptions for details.
   */
  async fund(amount: bigint, options?: FundOptions): Promise<FundResult> {
    if (options?.crossChain) {
      return this.fundCrossChainInternal(amount, options);
    }
    return this.fundLocal(amount, options);
  }

  // ─── Redeem ───────────────────────────────────────────────

  /**
   * Redeem this escrow.
   *
   * ```ts
   * await escrow.redeem();
   * ```
   */
  async redeem(): Promise<TransactionResult> {
    const gasLimit = await estimateGas(this.escrowContract, "redeem", [this.id]);
    const tx = await this.escrowContract.redeem(this.id, { gasLimit });
    const receipt = await tx.wait();
    if (!receipt || receipt.status === 0) {
      throw new TransactionFailedError(`redeem() reverted for escrow ${this.id}`, {
        txHash: receipt?.hash,
      });
    }
    return toTxResult(receipt);
  }

  // ─── Status ───────────────────────────────────────────────

  /**
   * Check if this escrow has been funded by querying past EscrowFunded events.
   * Scans the last ~10,000 blocks. For escrows created longer ago, use
   * sdk.events.queryEscrowEvents() with a custom block range.
   */
  async isFunded(): Promise<boolean> {
    const filter = this.escrowContract.filters.EscrowFunded(this.id);
    try {
      const currentBlock = await this.escrowContract.runner?.provider?.getBlockNumber();
      const fromBlock = Math.max(0, (currentBlock ?? 0) - 10000);
      const events = await this.escrowContract.queryFilter(filter, fromBlock);
      return events.length > 0;
    } catch {
      // Fallback: scan all (slower, may hit rate limits)
      const events = await this.escrowContract.queryFilter(filter);
      return events.length > 0;
    }
  }

  async isConditionMet(): Promise<boolean> {
    const resolverAddress: string = await this.escrowContract.getConditionResolver(this.id);
    if (resolverAddress === ZeroAddress) return true;
    const provider = this.signer.provider ?? this.escrowContract.runner?.provider;
    if (!provider) return true; // Can't check without provider, assume met
    const resolver = new Contract(resolverAddress, CONDITION_RESOLVER_ABI, provider);
    return resolver.isConditionMet(this.id);
  }

  /**
   * Check if the escrow is likely redeemable: exists + funded + condition met.
   *
   * Note: The contract also checks encrypted owner and FHE balance comparisons
   * on-chain during redeem(). Those can't be verified off-chain.
   */
  async isRedeemable(): Promise<boolean> {
    const [escrowExists, funded, conditionMet] = await Promise.all([
      this.exists(),
      this.isFunded(),
      this.isConditionMet(),
    ]);
    return escrowExists && funded && conditionMet;
  }

  async waitForRedeemable(options?: PollOptions): Promise<void> {
    await pollUntil(() => this.isRedeemable(), options);
  }

  /**
   * Wait for this escrow to be funded.
   * Listens for the EscrowFunded event, resolves when it fires.
   *
   * Note: With HTTP RPC providers, ethers uses polling (~4s intervals)
   * to detect events. For faster detection, use a WebSocket RPC URL.
   */
  async waitForFunded(timeoutMs = DEFAULT_SETTLEMENT_TIMEOUT): Promise<SettlementResult> {
    const filter = this.escrowContract.filters.EscrowFunded(this.id);

    // Check history first
    try {
      const currentBlock = await this.escrowContract.runner?.provider?.getBlockNumber();
      const fromBlock = Math.max(0, (currentBlock ?? 0) - 10000);
      const events = await this.escrowContract.queryFilter(filter, fromBlock);
      if (events.length > 0) {
        const last = events[events.length - 1];
        return { payer: (last as any).args.payer, blockNumber: last.blockNumber };
      }
    } catch {
      // queryFilter failed — fall through to listener
    }

    // Listen for future event (no async executor)
    return new Promise<SettlementResult>((resolve, reject) => {
      let settled = false;

      const cleanup = () => {
        settled = true;
        clearTimeout(timer);
        this.escrowContract.off(filter, handler);
      };

      const timer = setTimeout(() => {
        if (settled) return;
        cleanup();
        reject(new TimeoutError(`Escrow ${this.id} was not funded within ${timeoutMs}ms`));
      }, timeoutMs);

      const handler = (_escrowId: bigint, payer: string, event: any) => {
        if (settled) return;
        cleanup();
        resolve({ payer, blockNumber: event.log?.blockNumber ?? 0 });
      };

      this.escrowContract.on(filter, handler);
    });
  }

  // ─── Approval ─────────────────────────────────────────────

  async isApproved(): Promise<boolean> {
    const signerAddress = await this.signer.getAddress();
    return this.tokenContract.isOperator(signerAddress, this.addresses.escrow);
  }

  async approve(options?: ApprovalOptions): Promise<TransactionResult> {
    const duration = options?.durationSeconds ?? 365 * 24 * 60 * 60;
    const tx = await this.tokenContract.setOperator(
      this.addresses.escrow,
      Math.floor(Date.now() / 1000) + duration,
    );
    const receipt = await tx.wait();
    return toTxResult(receipt);
  }

  // ─── Private ──────────────────────────────────────────────

  private async fundLocal(amount: bigint, options?: FundOptions): Promise<FundResult> {
    await this.checkOrApprove(options);
    const encryptedPayment = await this.fhe.encryptUint64(amount);
    const gasLimit = await estimateGas(this.escrowContract, "fund", [this.id, encryptedPayment]);
    const tx = await this.escrowContract.fund(this.id, encryptedPayment, { gasLimit });
    const receipt = await tx.wait();
    if (!receipt || receipt.status === 0) {
      throw new TransactionFailedError(`fund() reverted for escrow ${this.id}`, {
        txHash: receipt?.hash,
      });
    }
    return { tx: toTxResult(receipt) };
  }

  private async fundCrossChainInternal(amount: bigint, options: FundOptions): Promise<FundResult> {
    const crossChain = options.crossChain!;

    if (!this.bridgeModule) {
      const { BridgeModule: BM } = await import("./bridge.js");
      this.bridgeModule = new BM(this.addresses);
    }

    // Convert private key to signer at boundary — never pass raw key deeper
    let sourceSigner = crossChain.sourceSigner;
    if (!sourceSigner && crossChain.sourcePrivateKey) {
      const { JsonRpcProvider, Wallet } = require("ethers");
      sourceSigner = new Wallet(
        crossChain.sourcePrivateKey,
        new JsonRpcProvider(crossChain.sourceRpc),
      );
    }

    const result = await this.bridgeModule.fundEscrowCrossChain({
      escrowId: this.id,
      sourceRpc: crossChain.sourceRpc,
      sourceSigner,
      amount,
      destinationSigner: this.signer,
    });

    const timeoutMs = options.settlementTimeoutMs ?? DEFAULT_SETTLEMENT_TIMEOUT;
    const self = this;

    const fundResult: FundResult = {
      tx: result.burnTx,
      relayTaskId: result.relayTaskId,
      waitForSettlement: (overrideTimeout?: number) =>
        self.waitForFunded(overrideTimeout ?? timeoutMs),
    };

    // If waitForSettlement requested, block until settled
    if (options.waitForSettlement) {
      fundResult.settlement = await self.waitForFunded(timeoutMs);
    }

    return fundResult;
  }

  private async checkOrApprove(options?: FundOptions): Promise<void> {
    const approved = await this.isApproved();
    if (approved) return;

    if (options?.autoApprove) {
      await this.approve();
      return;
    }

    const signerAddress = await this.signer.getAddress();
    throw new ApprovalRequiredError(this.addresses.escrow, signerAddress);
  }
}
