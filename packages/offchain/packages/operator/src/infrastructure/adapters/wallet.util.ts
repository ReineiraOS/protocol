import { Wallet } from 'ethers'

/**
 * Derive a wallet address from a private key. Returns '' for a missing or
 * malformed key — callers surface their own warning where the distinction
 * matters. Permissionless relayers identify themselves by their wallet.
 */
export function addressFromPrivateKey(privateKey: string): string {
  if (!privateKey) return ''
  try {
    return new Wallet(privateKey).address
  } catch {
    return ''
  }
}
