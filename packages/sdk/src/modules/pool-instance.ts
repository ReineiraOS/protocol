import { Contract } from "ethers";
import type { ethers } from "ethers";
import type { FHEClient } from "../crypto/fhe.js";
import { RECOURSE_POOL_ABI, FHERC20_ABI } from "../constants/abis.js";
import type {
  NetworkAddresses,
  TransactionResult,
  ApprovalOptions,
  FundOptions,
} from "../types/index.js";
import { TransactionFailedError, ApprovalRequiredError } from "../errors/index.js";

function toTxResult(receipt: ethers.TransactionReceipt): TransactionResult {
  return { hash: receipt.hash, blockNumber: receipt.blockNumber, gasUsed: receipt.gasUsed };
}

export interface StakeResult {
  stakeId: bigint;
  tx: TransactionResult;
}

export class PoolInstance {
  public readonly id: bigint;
  public readonly address: string;
  /** Tx receipt from createPool(), if this instance was returned by createPool(). */
  public readonly createTx?: TransactionResult;

  private readonly poolContract: Contract;
  private readonly fhe: FHEClient;
  private readonly addresses: NetworkAddresses;
  private readonly signer: ethers.Signer;

  constructor(
    poolId: bigint,
    poolAddress: string,
    signer: ethers.Signer,
    fhe: FHEClient,
    addresses: NetworkAddresses,
    createTx?: TransactionResult,
  ) {
    this.id = poolId;
    this.address = poolAddress;
    this.signer = signer;
    this.fhe = fhe;
    this.addresses = addresses;
    this.createTx = createTx;
    this.poolContract = new Contract(poolAddress, RECOURSE_POOL_ABI, signer);
  }

  async addPolicy(policyAddress: string): Promise<TransactionResult> {
    const tx = await this.poolContract.addPolicy(policyAddress);
    const receipt = await tx.wait();
    if (!receipt || receipt.status === 0) {
      throw new TransactionFailedError("addPolicy() reverted", { txHash: receipt?.hash });
    }
    return toTxResult(receipt);
  }

  async removePolicy(policyAddress: string): Promise<TransactionResult> {
    const tx = await this.poolContract.removePolicy(policyAddress);
    const receipt = await tx.wait();
    if (!receipt || receipt.status === 0) {
      throw new TransactionFailedError("removePolicy() reverted", { txHash: receipt?.hash });
    }
    return toTxResult(receipt);
  }

  /**
   * @param amount - Amount in USDC base units (6 decimals). Use sdk.usdc(100) for convenience.
   * @param options - Pass `{ autoApprove: true }` to auto-approve. Defaults to throwing.
   */
  async stake(amount: bigint, options?: FundOptions): Promise<StakeResult> {
    await this.checkOrApprove(options);
    const encryptedAmount = await this.fhe.encryptUint64(amount);
    const tx = await this.poolContract.stake(encryptedAmount, { gasLimit: 900_000n });
    const receipt = await tx.wait();
    if (!receipt || receipt.status === 0) {
      throw new TransactionFailedError("stake() reverted", { txHash: receipt?.hash });
    }

    for (const log of receipt.logs) {
      try {
        const parsed = this.poolContract.interface.parseLog({
          topics: log.topics as string[],
          data: log.data,
        });
        if (parsed?.name === "Staked") {
          return { stakeId: parsed.args.stakeId, tx: toTxResult(receipt) };
        }
      } catch {
        // skip
      }
    }
    throw new TransactionFailedError("stake() succeeded but no Staked event found");
  }

  async unstake(stakeId: bigint): Promise<TransactionResult> {
    const tx = await this.poolContract.unstake(stakeId);
    const receipt = await tx.wait();
    if (!receipt || receipt.status === 0) {
      throw new TransactionFailedError("unstake() reverted", { txHash: receipt?.hash });
    }
    return toTxResult(receipt);
  }

  /** Check if this pool contract is approved as operator for signer's cUSDC. */
  async isApproved(): Promise<boolean> {
    const tokenAddress: string = await this.poolContract.paymentToken();
    const tokenContract = new Contract(tokenAddress, FHERC20_ABI, this.signer);
    const signerAddress = await this.signer.getAddress();
    return tokenContract.isOperator(signerAddress, this.address);
  }

  /** Explicitly approve this pool as operator. Called automatically by stake(). */
  async approve(options?: ApprovalOptions): Promise<TransactionResult> {
    const duration = options?.durationSeconds ?? 365 * 24 * 60 * 60;
    const tokenAddress: string = await this.poolContract.paymentToken();
    const tokenContract = new Contract(tokenAddress, FHERC20_ABI, this.signer);
    const tx = await tokenContract.setOperator(
      this.address,
      Math.floor(Date.now() / 1000) + duration,
    );
    const receipt = await tx.wait();
    return toTxResult(receipt);
  }

  private async checkOrApprove(options?: FundOptions): Promise<void> {
    const approved = await this.isApproved();
    if (approved) return;

    if (options?.autoApprove) {
      await this.approve();
      return;
    }

    const signerAddress = await this.signer.getAddress();
    throw new ApprovalRequiredError(this.address, signerAddress);
  }
}
