import { Contract } from "ethers";
import type { ethers } from "ethers";
import { PLAIN_RECOURSE_POOL_ABI, ERC20_ABI } from "../constants/abis.js";
import type { NetworkAddresses, TransactionResult } from "../types/index.js";
import { ApprovalRequiredError, TransactionFailedError } from "../errors/index.js";

const FALLBACK_GAS_LIMIT = 500_000n;

export interface PlainStakeOptions {
  /** Auto-approve ERC20 spending if missing. Default false. */
  autoApprove?: boolean;
}

export interface PlainStakeResult {
  stakeId: bigint;
  tx: TransactionResult;
}

export class PlainPoolInstance {
  public readonly id: bigint;
  public readonly address: string;
  public createTx?: TransactionResult;

  private readonly _signer: ethers.Signer;
  private readonly _addresses: NetworkAddresses;
  private readonly _pool: Contract;

  constructor(
    id: bigint,
    poolAddress: string,
    signer: ethers.Signer,
    addresses: NetworkAddresses,
    options: { createTx?: TransactionResult } = {},
  ) {
    this.id = id;
    this.address = poolAddress;
    this._signer = signer;
    this._addresses = addresses;
    this._pool = new Contract(poolAddress, PLAIN_RECOURSE_POOL_ABI, signer);
    this.createTx = options.createTx;
  }

  async creator(): Promise<string> {
    return this._pool.creator();
  }

  async manager(): Promise<string> {
    return this._pool.manager();
  }

  async guardian(): Promise<string> {
    return this._pool.guardian();
  }

  async isOpen(): Promise<boolean> {
    return this._pool.isOpen();
  }

  async domainSeparator(): Promise<string> {
    return this._pool.domainSeparator();
  }

  async transferManager(newManager: string): Promise<TransactionResult> {
    return this._sendSimple(() => this._pool.transferManager(newManager), "transferManager");
  }

  async paymentToken(): Promise<string> {
    return this._pool.paymentToken();
  }

  async totalLiquidity(): Promise<bigint> {
    return this._pool.totalLiquidity();
  }

  async stakedAmount(stakeId: bigint): Promise<bigint> {
    return this._pool.stakedAmount(stakeId);
  }

  async pendingRewards(stakeId: bigint): Promise<bigint> {
    return this._pool.pendingRewards(stakeId);
  }

  async isPolicy(policy: string): Promise<boolean> {
    return this._pool.isPolicy(policy);
  }

  async addPolicy(policy: string): Promise<TransactionResult> {
    return this._sendSimple(() => this._pool.addPolicy(policy), "addPolicy");
  }

  async removePolicy(policy: string): Promise<TransactionResult> {
    return this._sendSimple(() => this._pool.removePolicy(policy), "removePolicy");
  }

  async stake(amount: bigint, options: PlainStakeOptions = {}): Promise<PlainStakeResult> {
    const signerAddress = await this._signer.getAddress();
    const paymentToken = await this.paymentToken();
    const erc20 = new Contract(paymentToken, ERC20_ABI, this._signer);
    const allowance: bigint = await erc20.allowance(signerAddress, this.address);

    if (allowance < amount) {
      if (!options.autoApprove) {
        throw new ApprovalRequiredError(this.address, signerAddress);
      }
      const approveTx = await erc20.approve(this.address, amount);
      const approveReceipt = await approveTx.wait();
      if (!approveReceipt || approveReceipt.status === 0) {
        throw new TransactionFailedError("payment-token approve() reverted", {
          txHash: approveReceipt?.hash,
        });
      }
    }

    let gasLimit: bigint;
    try {
      const est = await this._pool.stake.estimateGas(amount);
      gasLimit = BigInt(Math.ceil(Number(est) * 1.3));
    } catch {
      gasLimit = FALLBACK_GAS_LIMIT;
    }

    const tx = await this._pool.stake(amount, { gasLimit });
    const receipt = await tx.wait();
    if (!receipt || receipt.status === 0) {
      throw new TransactionFailedError("stake() reverted", { txHash: receipt?.hash });
    }

    const stakeId = this._parseStakedEvent(receipt);
    return {
      stakeId,
      tx: { hash: receipt.hash, blockNumber: receipt.blockNumber, gasUsed: receipt.gasUsed },
    };
  }

  async unstake(stakeId: bigint): Promise<TransactionResult> {
    return this._sendSimple(() => this._pool.unstake(stakeId), "unstake");
  }

  async claimRewards(stakeId: bigint): Promise<TransactionResult> {
    return this._sendSimple(() => this._pool.claimRewards(stakeId), "claimRewards");
  }

  private async _sendSimple(
    send: () => Promise<ethers.ContractTransactionResponse>,
    label: string,
  ): Promise<TransactionResult> {
    const tx = await send();
    const receipt = await tx.wait();
    if (!receipt || receipt.status === 0) {
      throw new TransactionFailedError(`${label}() reverted`, { txHash: receipt?.hash });
    }
    return { hash: receipt.hash, blockNumber: receipt.blockNumber, gasUsed: receipt.gasUsed };
  }

  private _parseStakedEvent(receipt: ethers.TransactionReceipt): bigint {
    for (const log of receipt.logs) {
      try {
        const parsed = this._pool.interface.parseLog({
          topics: [...log.topics] as string[],
          data: log.data,
        });
        if (parsed?.name === "Staked") {
          return parsed.args.stakeId;
        }
      } catch {
        // not our event
      }
    }
    throw new TransactionFailedError("Staked event not found in receipt");
  }
}
