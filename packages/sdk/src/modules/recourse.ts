import { Contract } from "ethers";
import type { ethers } from "ethers";
import type { FHEClient } from "../crypto/fhe.js";
import { POOL_FACTORY_ABI, COVERAGE_MANAGER_ABI } from "../constants/abis.js";
import type {
  NetworkAddresses,
  CreatePoolParams,
  PurchaseCoverageParams,
  TransactionResult,
} from "../types/index.js";
import { TransactionFailedError } from "../errors/index.js";
import { PoolInstance } from "./pool-instance.js";
import { CoverageInstance } from "./coverage-instance.js";

export class RecourseModule {
  private readonly factoryContract: Contract;
  private readonly coverageContract: Contract;
  private readonly fhe: FHEClient;
  private readonly addresses: NetworkAddresses;
  private readonly signer: ethers.Signer;

  constructor(signer: ethers.Signer, fhe: FHEClient, addresses: NetworkAddresses) {
    this.signer = signer;
    this.fhe = fhe;
    this.addresses = addresses;
    this.factoryContract = new Contract(addresses.poolFactory, POOL_FACTORY_ABI, signer);
    this.coverageContract = new Contract(addresses.coverageManager, COVERAGE_MANAGER_ABI, signer);
  }

  async createPool(params: CreatePoolParams): Promise<PoolInstance> {
    const initialManager = params.initialManager ?? "0x0000000000000000000000000000000000000000";
    const guardian = params.guardian ?? "0x0000000000000000000000000000000000000000";
    const isOpen = params.isOpen ?? true;

    const tx = await this.factoryContract.createPool(
      params.paymentToken,
      initialManager,
      guardian,
      isOpen,
    );
    const receipt = await tx.wait();
    if (!receipt || receipt.status === 0) {
      throw new TransactionFailedError("createPool() reverted", { txHash: receipt?.hash });
    }

    const createTx: TransactionResult = {
      hash: receipt.hash,
      blockNumber: receipt.blockNumber,
      gasUsed: receipt.gasUsed,
    };

    for (const log of receipt.logs) {
      try {
        const parsed = this.factoryContract.interface.parseLog({
          topics: log.topics as string[],
          data: log.data,
        });
        if (parsed?.name === "PoolCreated") {
          return new PoolInstance(
            parsed.args.poolId,
            parsed.args.pool,
            this.signer,
            this.fhe,
            this.addresses,
            createTx,
          );
        }
      } catch {
        // skip
      }
    }
    throw new TransactionFailedError("createPool() succeeded but no PoolCreated event found");
  }

  async getPool(poolId: bigint): Promise<PoolInstance> {
    const poolAddress: string = await this.factoryContract.pool(poolId);
    return new PoolInstance(poolId, poolAddress, this.signer, this.fhe, this.addresses);
  }

  async poolCount(): Promise<bigint> {
    return this.factoryContract.poolCount();
  }

  /** Get a CoverageInstance for an existing coverage ID. */
  getCoverage(coverageId: bigint): CoverageInstance {
    return new CoverageInstance(coverageId, this.signer, this.addresses);
  }

  async purchaseCoverage(params: PurchaseCoverageParams): Promise<CoverageInstance> {
    const signerAddress = await this.signer.getAddress();
    const encryptedHolder = await this.fhe.encryptAddress(signerAddress);
    const encryptedAmount = await this.fhe.encryptUint64(params.coverageAmount);

    const tx = await this.coverageContract.purchaseCoverage(
      encryptedHolder,
      params.pool,
      params.policy,
      params.escrowId,
      encryptedAmount,
      params.expiry,
      params.policyData ?? "0x",
      params.riskProof ?? "0x",
      { gasLimit: 3_000_000n },
    );
    const receipt = await tx.wait();
    if (!receipt || receipt.status === 0) {
      throw new TransactionFailedError("purchaseCoverage() reverted", { txHash: receipt?.hash });
    }

    const createTx: TransactionResult = {
      hash: receipt.hash,
      blockNumber: receipt.blockNumber,
      gasUsed: receipt.gasUsed,
    };

    for (const log of receipt.logs) {
      try {
        const parsed = this.coverageContract.interface.parseLog({
          topics: log.topics as string[],
          data: log.data,
        });
        if (parsed?.name === "CoveragePurchased") {
          return new CoverageInstance(
            parsed.args.coverageId,
            this.signer,
            this.addresses,
            createTx,
          );
        }
      } catch {
        // skip
      }
    }
    throw new TransactionFailedError(
      "purchaseCoverage() succeeded but no CoveragePurchased event found",
    );
  }
}
