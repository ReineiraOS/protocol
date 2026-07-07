import { Contract, Wallet, ContractTransactionResponse } from 'ethers'
import CCTPV2EscrowReceiverABI from '../abis/CCTPV2EscrowReceiver.json'
import ERC20ABI from '../abis/ERC20.json'

/**
 * Permissionless CCTP V2 escrow settlement receiver. Anyone holding a valid
 * Circle attestation can call `settle(message, attestation)` — there is no
 * operator registry, staking, or task-claim step.
 */
export interface EscrowReceiverContract {
  settle(message: string, attestation: string): Promise<ContractTransactionResponse>
  buildHookData(escrowId: bigint): Promise<string>
}

export interface ERC20Contract {
  approve(spender: string, amount: bigint): Promise<ContractTransactionResponse>
  balanceOf(account: string): Promise<bigint>
  decimals(): Promise<number>
  symbol(): Promise<string>
  allowance(owner: string, spender: string): Promise<bigint>
}

export function getEscrowReceiverContract(address: string, wallet: Wallet): EscrowReceiverContract {
  return new Contract(address, CCTPV2EscrowReceiverABI, wallet) as unknown as EscrowReceiverContract
}

export function getERC20Contract(address: string, wallet: Wallet): ERC20Contract {
  return new Contract(address, ERC20ABI, wallet) as unknown as ERC20Contract
}
