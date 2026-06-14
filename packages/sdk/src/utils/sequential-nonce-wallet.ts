import { Wallet } from "ethers";
import type { ethers } from "ethers";

/**
 * Wallet that tracks the last submitted nonce locally, to avoid races where
 * the RPC's "pending" query returns stale data right after a previous tx
 * was submitted (anvil instant-mine, or testnet between blocks).
 *
 * Behaviour:
 * - On each send, fetches RPC pending nonce.
 * - If it's still <= the locally-tracked next nonce, uses the local value
 *   (we know better — a tx was submitted but RPC hasn't propagated yet).
 * - Otherwise uses RPC value (RPC saw a tx from another path; trust it).
 * - After submit, updates local tracker to nonce+1.
 *
 * This avoids the NonceManager drift bug (where a one-shot fetch + delta
 * counter can desync from chain state if the underlying tx fails) while
 * keeping protection against stale-pending races.
 */
export class SequentialNonceWallet extends Wallet {
  private _nextNonce: number | null = null;

  async getNonce(blockTag?: ethers.BlockTag): Promise<number> {
    const rpcNonce = await super.getNonce(blockTag);
    if (blockTag === "pending" && this._nextNonce !== null && this._nextNonce > rpcNonce) {
      return this._nextNonce;
    }
    return rpcNonce;
  }

  async sendTransaction(tx: ethers.TransactionRequest): Promise<ethers.TransactionResponse> {
    if (tx.nonce == null) {
      tx.nonce = await this.getNonce("pending");
    }
    const result = await super.sendTransaction(tx);
    this._nextNonce = Number(tx.nonce) + 1;
    return result;
  }
}
