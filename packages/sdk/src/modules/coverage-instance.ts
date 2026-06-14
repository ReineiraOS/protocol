import { Contract } from "ethers";
import type { ethers } from "ethers";
import { COVERAGE_MANAGER_ABI } from "../constants/abis.js";
import type { NetworkAddresses, TransactionResult } from "../types/index.js";
import { TransactionFailedError, CoverageNotActiveError } from "../errors/index.js";

export enum CoverageStatus {
  None = 0,
  Active = 1,
  Disputed = 2,
  Claimed = 3,
  Expired = 4,
}

export class CoverageInstance {
  public readonly id: bigint;
  /** Tx receipt from purchaseCoverage(), if returned by that call. */
  public readonly createTx?: TransactionResult;

  private readonly coverageContract: Contract;

  constructor(
    coverageId: bigint,
    signer: ethers.Signer,
    addresses: NetworkAddresses,
    createTx?: TransactionResult,
  ) {
    this.id = coverageId;
    this.createTx = createTx;
    this.coverageContract = new Contract(addresses.coverageManager, COVERAGE_MANAGER_ABI, signer);
  }

  async status(): Promise<CoverageStatus> {
    const raw = await this.coverageContract.coverageStatus(this.id);
    return Number(raw) as CoverageStatus;
  }

  async dispute(disputeProof: string): Promise<TransactionResult> {
    const currentStatus = await this.status();
    if (currentStatus !== CoverageStatus.Active) {
      throw new CoverageNotActiveError(this.id);
    }

    const tx = await this.coverageContract.dispute(this.id, disputeProof, {
      gasLimit: 3_000_000n,
    });
    const receipt = await tx.wait();
    if (!receipt || receipt.status === 0) {
      throw new TransactionFailedError(`dispute() reverted for coverage ${this.id}`, {
        txHash: receipt?.hash,
      });
    }
    return { hash: receipt.hash, blockNumber: receipt.blockNumber, gasUsed: receipt.gasUsed };
  }
}
