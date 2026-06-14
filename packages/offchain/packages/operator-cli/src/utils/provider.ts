import { JsonRpcProvider, Wallet } from 'ethers'
import type { CLIConfig } from './config'

export function createProvider(rpcUrl: string): JsonRpcProvider {
  return new JsonRpcProvider(rpcUrl)
}

export function createWallet(config: CLIConfig): Wallet {
  const provider = createProvider(config.rpcUrl)
  return new Wallet(config.privateKey, provider)
}

export function createWalletWithProvider(privateKey: string, provider: JsonRpcProvider): Wallet {
  return new Wallet(privateKey, provider)
}
