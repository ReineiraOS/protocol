import { Contract, ethers as ethersLib } from "ethers";
import type { ethers } from "ethers";
import { PLAIN_ESCROW_ABI } from "../constants/abis.js";
import type {
  NetworkAddresses,
  TransactionResult,
  CreatePlainEscrowParams,
} from "../types/index.js";
import { EscrowNotFoundError, TransactionFailedError, ValidationError } from "../errors/index.js";
import { PlainEscrowInstance } from "./escrow-plain-instance.js";

const FALLBACK_GAS_LIMIT = 700_000n;

export class PlainEscrowModule {
  private readonly _signer: ethers.Signer;
  private readonly _addresses: NetworkAddresses;
  private readonly _contract: Contract;

  constructor(signer: ethers.Signer, addresses: NetworkAddresses) {
    this._signer = signer;
    this._addresses = addresses;
    this._contract = new Contract(addresses.plainEscrow, PLAIN_ESCROW_ABI, signer);
  }

  /**
   * Create a plain escrow.
   *
   * ```ts
   * const escrow = await sdk.escrowPlain.create({
   *   amount: sdk.usdc(1000),
   *   owner: "0xRecipient...",
   * });
   * ```
   */
  async create(params: CreatePlainEscrowParams): Promise<PlainEscrowInstance> {
    if (!params.owner || params.owner === ethersLib.ZeroAddress) {
      throw new ValidationError("owner must be a non-zero address");
    }
    if (params.amount <= 0n) {
      throw new ValidationError("amount must be positive");
    }

    const resolver = params.resolver ?? ethersLib.ZeroAddress;
    const resolverData = params.resolverData ?? "0x";

    let gasLimit: bigint;
    try {
      const est = await this._contract.create.estimateGas(
        params.owner,
        params.amount,
        resolver,
        resolverData,
      );
      gasLimit = BigInt(Math.ceil(Number(est) * 1.3));
    } catch {
      gasLimit = FALLBACK_GAS_LIMIT;
    }

    const tx = await this._contract.create(params.owner, params.amount, resolver, resolverData, {
      gasLimit,
    });
    const receipt = await tx.wait();
    if (!receipt || receipt.status === 0) {
      throw new TransactionFailedError("escrow create() reverted", {
        txHash: receipt?.hash,
      });
    }

    const escrowId = this._parseEscrowCreated(receipt);
    return new PlainEscrowInstance(escrowId, this._signer, this._addresses, {
      createTx: { hash: receipt.hash, blockNumber: receipt.blockNumber, gasUsed: receipt.gasUsed },
    });
  }

  /** Get an instance for an existing escrow by ID. */
  get(escrowId: bigint): PlainEscrowInstance {
    return new PlainEscrowInstance(escrowId, this._signer, this._addresses);
  }

  /** Whether an escrow exists on-chain. */
  async exists(escrowId: bigint): Promise<boolean> {
    return this._contract.exists(escrowId);
  }

  /** Total number of escrows created. */
  async total(): Promise<bigint> {
    return this._contract.total();
  }

  /**
   * Redeem multiple escrows in one transaction.
   * Caller must be the owner of all included escrows.
   */
  async redeemMultiple(escrowIds: bigint[]): Promise<TransactionResult> {
    if (escrowIds.length === 0) {
      throw new ValidationError("escrowIds array cannot be empty");
    }

    let gasLimit: bigint;
    try {
      const est = await this._contract.redeemMultiple.estimateGas(escrowIds);
      gasLimit = BigInt(Math.ceil(Number(est) * 1.3));
    } catch {
      gasLimit = FALLBACK_GAS_LIMIT;
    }

    const tx = await this._contract.redeemMultiple(escrowIds, { gasLimit });
    const receipt = await tx.wait();
    if (!receipt || receipt.status === 0) {
      throw new TransactionFailedError("redeemMultiple() reverted", {
        txHash: receipt?.hash,
      });
    }
    return { hash: receipt.hash, blockNumber: receipt.blockNumber, gasUsed: receipt.gasUsed };
  }

  private _parseEscrowCreated(receipt: ethers.TransactionReceipt): bigint {
    for (const log of receipt.logs) {
      try {
        const parsed = this._contract.interface.parseLog({
          topics: [...log.topics] as string[],
          data: log.data,
        });
        if (parsed?.name === "EscrowCreated") {
          return parsed.args.escrowId;
        }
      } catch {
        // Not our event
      }
    }
    throw new EscrowNotFoundError(0n);
  }
}
