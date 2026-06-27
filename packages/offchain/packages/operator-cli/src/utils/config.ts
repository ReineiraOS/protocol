import { config } from 'dotenv'
import { Command } from 'commander'
import { resolve } from 'path'
import { CONTRACTS } from '@reineira-ops/shared'

// Load .env from operator-cli package directory, not cwd
config({ path: resolve(__dirname, '../../.env') })

export interface CLIConfig {
  rpcUrl: string
  rpcUrlSource: string
  privateKey: string
  escrowReceiverAddress: string
}

export function loadConfig(options: Record<string, string>, requireRpc = true): CLIConfig {
  const rpcUrl = options.rpc || process.env.RPC_URL
  const rpcUrlSource = options.rpcSource || process.env.RPC_URL_SOURCE
  const privateKey = options.privateKey || process.env.PRIVATE_KEY
  const escrowReceiverAddress =
    options.escrowReceiver ||
    process.env.ESCROW_RECEIVER_ADDRESS ||
    CONTRACTS.ARBITRUM_SEPOLIA.ESCROW_RECEIVER

  if (!privateKey) throw new Error('Missing --private-key or PRIVATE_KEY')
  if (requireRpc && !rpcUrl) throw new Error('Missing --rpc or RPC_URL')

  return {
    rpcUrl: rpcUrl || '',
    rpcUrlSource: rpcUrlSource || '',
    privateKey,
    escrowReceiverAddress: escrowReceiverAddress || '',
  }
}

export function getParentOptions(cmd: Command): Record<string, string> {
  // Walk up command chain to get root options
  let current: Command | null = cmd
  while (current.parent) {
    current = current.parent
  }
  return current.opts()
}
