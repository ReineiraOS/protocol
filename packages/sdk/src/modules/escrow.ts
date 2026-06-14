import { Contract, ethers as ethersLib } from "ethers";
import type { ethers } from "ethers";
import type { FHEClient } from "../crypto/fhe.js";
import { CONFIDENTIAL_ESCROW_ABI } from "../constants/abis.js";
import type { NetworkAddresses, TransactionResult, CreateEscrowParams } from "../types/index.js";
import { EscrowNotFoundError, TransactionFailedError, ValidationError } from "../errors/index.js";
import { EscrowBuilder, type EscrowBuildConfig } from "./escrow-builder.js";
import { EscrowInstance } from "./escrow-instance.js";
import type { RecourseModule } from "./recourse.js";
import type { BridgeModule } from "./bridge.js";

const FALLBACK_GAS_LIMIT = 900_000n;

export class EscrowModule {
  private readonly escrowContract: Contract;
  private readonly fhe: FHEClient;
  private readonly addresses: NetworkAddresses;
  private readonly _signer: ethers.Signer;
  private recourseModule: RecourseModule | null = null;
  private bridgeModule: BridgeModule | null = null;

  constructor(signer: ethers.Signer, fhe: FHEClient, addresses: NetworkAddresses) {
    this._signer = signer;
    this.fhe = fhe;
    this.addresses = addresses;
    this.escrowContract = new Contract(addresses.escrow, CONFIDENTIAL_ESCROW_ABI, signer);
  }

  /** @internal */
  setRecourseModule(recourse: RecourseModule): void {
    this.recourseModule = recourse;
  }

  /** @internal */
  setBridgeModule(bridge: BridgeModule): void {
    this.bridgeModule = bridge;
  }

  /**
   * Create an escrow.
   *
   * ```ts
   * const escrow = await sdk.escrow.create({
   *   amount: sdk.usdc(1000),
   *   owner: "0xRecipient...",
   * });
   * ```
   */
  async create(params: CreateEscrowParams): Promise<EscrowInstance> {
    // Validate through builder to get consistent error messages
    const builder = this.build().amount(params.amount).owner(params.owner);
    if (params.resolver) builder.condition(params.resolver, params.resolverData);
    if (params.recourse) builder.recourse(params.recourse);
    return builder.create();
  }

  /**
   * Fluent builder for complex escrows (conditions, recourse).
   *
   * ```ts
   * const escrow = await sdk.escrow.build()
   *   .amount(sdk.usdc(1000))
   *   .owner("0x...")
   *   .condition("0xResolver...", encodedData)
   *   .recourse({...})
   *   .create();
   * ```
   */
  build(): EscrowBuilder {
    return new EscrowBuilder((config) => this.executeCreate(config));
  }

  /**
   * Get an EscrowInstance for an existing escrow by ID.
   * Use this to interact with escrows you didn't create in this session.
   *
   * ```ts
   * const escrow = sdk.escrow.get(42n);
   * await escrow.fund(sdk.usdc(100));
   * ```
   */
  get(escrowId: bigint): EscrowInstance {
    return new EscrowInstance(escrowId, this._signer, this.fhe, this.addresses, {
      bridge: this.bridgeModule ?? undefined,
    });
  }

  /** Check if an escrow exists on-chain. */
  async exists(escrowId: bigint): Promise<boolean> {
    return this.escrowContract.exists(escrowId);
  }

  /** Total number of escrows created. */
  async total(): Promise<bigint> {
    return this.escrowContract.total();
  }

  /**
   * Redeem multiple escrows in one transaction.
   *
   * ```ts
   * await sdk.escrow.redeemMultiple([0n, 1n, 2n]);
   * ```
   */
  async redeemMultiple(escrowIds: bigint[]): Promise<TransactionResult> {
    if (escrowIds.length === 0) {
      throw new ValidationError("escrowIds array cannot be empty");
    }

    let gasLimit: bigint;
    try {
      const est = await this.escrowContract.redeemMultiple.estimateGas(escrowIds);
      gasLimit = BigInt(Math.ceil(Number(est) * 1.3));
    } catch {
      gasLimit = FALLBACK_GAS_LIMIT;
    }

    const tx = await this.escrowContract.redeemMultiple(escrowIds, { gasLimit });
    const receipt = await tx.wait();
    if (!receipt || receipt.status === 0) {
      throw new TransactionFailedError("redeemMultiple() reverted", { txHash: receipt?.hash });
    }
    return { hash: receipt.hash, blockNumber: receipt.blockNumber, gasUsed: receipt.gasUsed };
  }

  private async executeCreate(config: EscrowBuildConfig): Promise<EscrowInstance> {
    const encryptedOwner = await this.fhe.encryptAddress(config.owner!);
    const encryptedAmount = await this.fhe.encryptUint64(config.amount!);

    const resolver = config.resolver ?? ethersLib.ZeroAddress;
    const resolverData = config.resolverData ?? "0x";

    let gasLimit: bigint;
    try {
      const est = await this.escrowContract.create.estimateGas(
        encryptedOwner,
        encryptedAmount,
        resolver,
        resolverData,
      );
      gasLimit = BigInt(Math.ceil(Number(est) * 1.3));
    } catch {
      gasLimit = FALLBACK_GAS_LIMIT;
    }

    const tx = await this.escrowContract.create(
      encryptedOwner,
      encryptedAmount,
      resolver,
      resolverData,
      { gasLimit },
    );
    const receipt = await tx.wait();
    if (!receipt || receipt.status === 0) {
      throw new TransactionFailedError("escrow create() reverted", { txHash: receipt?.hash });
    }

    const escrowId = this.parseEscrowCreatedEvent(receipt);
    const createTx: TransactionResult = {
      hash: receipt.hash,
      blockNumber: receipt.blockNumber,
      gasUsed: receipt.gasUsed,
    };

    let coverage;
    if (config.recourse) {
      if (!this.recourseModule) {
        throw new TransactionFailedError(
          ".recourse() requires the recourse module. Use sdk.escrow (not standalone EscrowModule).",
        );
      }
      coverage = await this.recourseModule.purchaseCoverage({
        pool: config.recourse.pool,
        policy: config.recourse.policy,
        escrowId,
        coverageAmount: config.recourse.coverageAmount,
        expiry: config.recourse.expiry,
        policyData: config.recourse.policyData,
        riskProof: config.recourse.riskProof,
      });
    }

    return new EscrowInstance(escrowId, this._signer, this.fhe, this.addresses, {
      createTx,
      coverage,
      bridge: this.bridgeModule ?? undefined,
    });
  }

  private parseEscrowCreatedEvent(receipt: ethers.TransactionReceipt): bigint {
    for (const log of receipt.logs) {
      try {
        const parsed = this.escrowContract.interface.parseLog({
          topics: [...log.topics] as string[],
          data: log.data,
        });
        if (parsed?.name === "EscrowCreated") {
          return parsed.args.escrowId;
        }
      } catch {
        // Not our event, skip
      }
    }
    throw new EscrowNotFoundError(0n);
  }
}
