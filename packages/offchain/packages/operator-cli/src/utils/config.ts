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
  registryAddress: string
  taskExecutorAddress: string
}

export function loadConfig(options: Record<string, string>, requireRegistry = true): CLIConfig {
  const rpcUrl = options.rpc || process.env.RPC_URL
  const rpcUrlSource = options.rpcSource || process.env.RPC_URL_SOURCE
  const privateKey = options.privateKey || process.env.PRIVATE_KEY
  const registryAddress =
    options.registry ||
    process.env.OPERATOR_REGISTRY_ADDRESS ||
    CONTRACTS.ARBITRUM_SEPOLIA.OPERATOR_REGISTRY
  const taskExecutorAddress =
    options.executor ||
    process.env.TASK_EXECUTOR_ADDRESS ||
    CONTRACTS.ARBITRUM_SEPOLIA.TASK_EXECUTOR

  if (!privateKey) throw new Error('Missing --private-key or PRIVATE_KEY')
  if (requireRegistry && !rpcUrl) throw new Error('Missing --rpc or RPC_URL')
  if (requireRegistry && !registryAddress)
    throw new Error('Missing --registry or OPERATOR_REGISTRY_ADDRESS')

  return {
    rpcUrl: rpcUrl || '',
    rpcUrlSource: rpcUrlSource || '',
    privateKey,
    registryAddress: registryAddress || '',
    taskExecutorAddress: taskExecutorAddress || '',
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
