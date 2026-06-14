import { Contract } from "ethers";
import type { ethers } from "ethers";
import { PLAIN_COVERAGE_MANAGER_ABI } from "../constants/abis.js";
import type { NetworkAddresses, TransactionResult } from "../types/index.js";
import { PlainCoverageStatus } from "../types/index.js";
import { TransactionFailedError } from "../errors/index.js";

const FALLBACK_GAS_LIMIT = 400_000n;

export class PlainCoverageInstance {
  public readonly id: bigint;
  public createTx?: TransactionResult;

  private readonly _coverageManager: Contract;

  constructor(
    id: bigint,
    signer: ethers.Signer,
    addresses: NetworkAddresses,
    options: { createTx?: TransactionResult } = {},
  ) {
    this.id = id;
    this._coverageManager = new Contract(
      addresses.plainCoverageManager,
      PLAIN_COVERAGE_MANAGER_ABI,
      signer,
    );
    this.createTx = options.createTx;
  }

  async status(): Promise<PlainCoverageStatus> {
    const raw = await this._coverageManager.coverageStatus(this.id);
    return Number(raw) as PlainCoverageStatus;
  }

  async dispute(disputeProof: string = "0x"): Promise<TransactionResult> {
    let gasLimit: bigint;
    try {
      const est = await this._coverageManager.dispute.estimateGas(this.id, disputeProof);
      gasLimit = BigInt(Math.ceil(Number(est) * 1.3));
    } catch {
      gasLimit = FALLBACK_GAS_LIMIT;
    }

    const tx = await this._coverageManager.dispute(this.id, disputeProof, { gasLimit });
    const receipt = await tx.wait();
    if (!receipt || receipt.status === 0) {
      throw new TransactionFailedError("dispute() reverted", { txHash: receipt?.hash });
    }
    return { hash: receipt.hash, blockNumber: receipt.blockNumber, gasUsed: receipt.gasUsed };
  }
}
