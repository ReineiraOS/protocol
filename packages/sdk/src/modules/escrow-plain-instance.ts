import { Contract } from "ethers";
import type { ethers } from "ethers";
import { PLAIN_ESCROW_ABI, ERC20_ABI } from "../constants/abis.js";
import type { NetworkAddresses, TransactionResult } from "../types/index.js";
import { ApprovalRequiredError, TransactionFailedError } from "../errors/index.js";

const FALLBACK_GAS_LIMIT = 500_000n;

export interface PlainFundOptions {
  /** Auto-approve ERC20 spending if missing. Default false. */
  autoApprove?: boolean;
}

export class PlainEscrowInstance {
  public readonly id: bigint;
  public createTx?: TransactionResult;

  private readonly _signer: ethers.Signer;
  private readonly _addresses: NetworkAddresses;
  private readonly _escrow: Contract;
  private readonly _usdc: Contract;

  constructor(
    id: bigint,
    signer: ethers.Signer,
    addresses: NetworkAddresses,
    options: { createTx?: TransactionResult } = {},
  ) {
    this.id = id;
    this._signer = signer;
    this._addresses = addresses;
    this._escrow = new Contract(addresses.plainEscrow, PLAIN_ESCROW_ABI, signer);
    this._usdc = new Contract(addresses.usdc, ERC20_ABI, signer);
    this.createTx = options.createTx;
  }

  /** Whether this escrow exists on-chain. */
  async exists(): Promise<boolean> {
    return this._escrow.exists(this.id);
  }

  /** Owner / recipient of the escrow. */
  async owner(): Promise<string> {
    return this._escrow.getOwner(this.id);
  }

  /** Total expected amount. */
  async amount(): Promise<bigint> {
    return this._escrow.getAmount(this.id);
  }

  /** Amount paid in so far. */
  async paidAmount(): Promise<bigint> {
    return this._escrow.getPaidAmount(this.id);
  }

  /** Whether the escrow has been redeemed. */
  async isRedeemed(): Promise<boolean> {
    return this._escrow.getRedeemedStatus(this.id);
  }

  /** True when paidAmount >= amount and not yet redeemed. */
  async isFunded(): Promise<boolean> {
    const [amount, paid, redeemed] = await Promise.all([
      this.amount(),
      this.paidAmount(),
      this.isRedeemed(),
    ]);
    return !redeemed && paid >= amount;
  }

  /** Fund the escrow with the given USDC amount. */
  async fund(amount: bigint, options: PlainFundOptions = {}): Promise<TransactionResult> {
    const signerAddress = await this._signer.getAddress();
    const allowance: bigint = await this._usdc.allowance(
      signerAddress,
      this._addresses.plainEscrow,
    );

    if (allowance < amount) {
      if (!options.autoApprove) {
        throw new ApprovalRequiredError(this._addresses.plainEscrow, signerAddress);
      }
      const approveTx = await this._usdc.approve(this._addresses.plainEscrow, amount);
      const approveReceipt = await approveTx.wait();
      if (!approveReceipt || approveReceipt.status === 0) {
        throw new TransactionFailedError("USDC approve() reverted", {
          txHash: approveReceipt?.hash,
        });
      }
    }

    let gasLimit: bigint;
    try {
      const est = await this._escrow.fund.estimateGas(this.id, amount);
      gasLimit = BigInt(Math.ceil(Number(est) * 1.3));
    } catch {
      gasLimit = FALLBACK_GAS_LIMIT;
    }

    const tx = await this._escrow.fund(this.id, amount, { gasLimit });
    const receipt = await tx.wait();
    if (!receipt || receipt.status === 0) {
      throw new TransactionFailedError("escrow fund() reverted", { txHash: receipt?.hash });
    }
    return { hash: receipt.hash, blockNumber: receipt.blockNumber, gasUsed: receipt.gasUsed };
  }

  /** Redeem this escrow. Caller must be the owner. */
  async redeem(): Promise<TransactionResult> {
    let gasLimit: bigint;
    try {
      const est = await this._escrow.redeem.estimateGas(this.id);
      gasLimit = BigInt(Math.ceil(Number(est) * 1.3));
    } catch {
      gasLimit = FALLBACK_GAS_LIMIT;
    }

    const tx = await this._escrow.redeem(this.id, { gasLimit });
    const receipt = await tx.wait();
    if (!receipt || receipt.status === 0) {
      throw new TransactionFailedError("escrow redeem() reverted", { txHash: receipt?.hash });
    }
    return { hash: receipt.hash, blockNumber: receipt.blockNumber, gasUsed: receipt.gasUsed };
  }
}
