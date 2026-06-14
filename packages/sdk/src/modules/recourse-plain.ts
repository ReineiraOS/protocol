import { Contract } from "ethers";
import type { ethers } from "ethers";
import { POOL_FACTORY_ABI, PLAIN_COVERAGE_MANAGER_ABI } from "../constants/abis.js";
import type {
  NetworkAddresses,
  CreatePlainPoolParams,
  PurchasePlainCoverageParams,
  TransactionResult,
} from "../types/index.js";
import { TransactionFailedError, ValidationError } from "../errors/index.js";
import { PlainPoolInstance } from "./pool-plain-instance.js";
import { PlainCoverageInstance } from "./coverage-plain-instance.js";

const FALLBACK_GAS_LIMIT = 1_500_000n;

export class PlainRecourseModule {
  private readonly _signer: ethers.Signer;
  private readonly _addresses: NetworkAddresses;
  private readonly _factory: Contract;
  private readonly _coverage: Contract;

  constructor(signer: ethers.Signer, addresses: NetworkAddresses) {
    this._signer = signer;
    this._addresses = addresses;
    this._factory = new Contract(addresses.plainPoolFactory, POOL_FACTORY_ABI, signer);
    this._coverage = new Contract(
      addresses.plainCoverageManager,
      PLAIN_COVERAGE_MANAGER_ABI,
      signer,
    );
  }

  /** Create a new plain recourse pool. The signer becomes the immutable Pool Creator. */
  async createPool(params: CreatePlainPoolParams): Promise<PlainPoolInstance> {
    if (!params.paymentToken) {
      throw new ValidationError("paymentToken is required");
    }

    const initialManager = params.initialManager ?? "0x0000000000000000000000000000000000000000";
    const guardian = params.guardian ?? "0x0000000000000000000000000000000000000000";
    const isOpen = params.isOpen ?? true;

    const tx = await this._factory.createPool(
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
        const parsed = this._factory.interface.parseLog({
          topics: [...log.topics] as string[],
          data: log.data,
        });
        if (parsed?.name === "PoolCreated") {
          return new PlainPoolInstance(
            parsed.args.poolId,
            parsed.args.pool,
            this._signer,
            this._addresses,
            { createTx },
          );
        }
      } catch {
        // skip
      }
    }
    throw new TransactionFailedError("createPool() succeeded but no PoolCreated event found");
  }

  /** Get an existing pool by id. */
  async getPool(poolId: bigint): Promise<PlainPoolInstance> {
    const poolAddress: string = await this._factory.pool(poolId);
    return new PlainPoolInstance(poolId, poolAddress, this._signer, this._addresses);
  }

  /** Total number of pools created. */
  async poolCount(): Promise<bigint> {
    return this._factory.poolCount();
  }

  /** Get a CoverageInstance for an existing coverage by id. */
  getCoverage(coverageId: bigint): PlainCoverageInstance {
    return new PlainCoverageInstance(coverageId, this._signer, this._addresses);
  }

  /** Purchase coverage for an escrow. Pass `invite`+`inviteSig` for private pools. */
  async purchaseCoverage(params: PurchasePlainCoverageParams): Promise<PlainCoverageInstance> {
    if (!params.holder) throw new ValidationError("holder is required");
    if (!params.pool) throw new ValidationError("pool is required");
    if (!params.policy) throw new ValidationError("policy is required");
    if (params.coverageAmount <= 0n) throw new ValidationError("coverageAmount must be positive");

    const useVoucher = params.invite !== undefined;
    if (useVoucher && !params.inviteSig) {
      throw new ValidationError("inviteSig is required when invite is provided");
    }

    let gasLimit: bigint;
    let tx: ethers.ContractTransactionResponse;

    if (useVoucher) {
      const inviteTuple = [
        params.invite!.pool,
        params.invite!.invitee,
        params.invite!.maxUses,
        params.invite!.deadline,
        params.invite!.inviteId,
      ];
      try {
        const est = await this._coverage
          .getFunction(
            "purchaseCoverage(address,address,address,uint256,uint256,uint256,bytes,bytes,(address,address,uint256,uint256,uint256),bytes)",
          )
          .estimateGas(
            params.holder,
            params.pool,
            params.policy,
            params.escrowId,
            params.coverageAmount,
            params.expiry,
            params.policyData ?? "0x",
            params.riskProof ?? "0x",
            inviteTuple,
            params.inviteSig!,
          );
        gasLimit = BigInt(Math.ceil(Number(est) * 1.3));
      } catch {
        gasLimit = FALLBACK_GAS_LIMIT;
      }
      tx = await this._coverage.getFunction(
        "purchaseCoverage(address,address,address,uint256,uint256,uint256,bytes,bytes,(address,address,uint256,uint256,uint256),bytes)",
      )(
        params.holder,
        params.pool,
        params.policy,
        params.escrowId,
        params.coverageAmount,
        params.expiry,
        params.policyData ?? "0x",
        params.riskProof ?? "0x",
        inviteTuple,
        params.inviteSig!,
        { gasLimit },
      );
    } else {
      try {
        const est = await this._coverage
          .getFunction(
            "purchaseCoverage(address,address,address,uint256,uint256,uint256,bytes,bytes)",
          )
          .estimateGas(
            params.holder,
            params.pool,
            params.policy,
            params.escrowId,
            params.coverageAmount,
            params.expiry,
            params.policyData ?? "0x",
            params.riskProof ?? "0x",
          );
        gasLimit = BigInt(Math.ceil(Number(est) * 1.3));
      } catch {
        gasLimit = FALLBACK_GAS_LIMIT;
      }
      tx = await this._coverage.getFunction(
        "purchaseCoverage(address,address,address,uint256,uint256,uint256,bytes,bytes)",
      )(
        params.holder,
        params.pool,
        params.policy,
        params.escrowId,
        params.coverageAmount,
        params.expiry,
        params.policyData ?? "0x",
        params.riskProof ?? "0x",
        { gasLimit },
      );
    }

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
        const parsed = this._coverage.interface.parseLog({
          topics: [...log.topics] as string[],
          data: log.data,
        });
        if (parsed?.name === "CoveragePurchased") {
          return new PlainCoverageInstance(parsed.args.coverageId, this._signer, this._addresses, {
            createTx,
          });
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
