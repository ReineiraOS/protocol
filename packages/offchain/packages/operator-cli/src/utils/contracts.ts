import { Contract, Wallet, ContractTransactionResponse } from 'ethers'
import OperatorRegistryABI from '../abis/OperatorRegistry.json'
import TaskExecutorABI from '../abis/TaskExecutor.json'
import ERC20ABI from '../abis/ERC20.json'

/**
 * Operator information from the OperatorRegistry contract
 */
export interface OperatorInfo {
  stake: bigint
  unbondRequestTime: bigint
  isActive: boolean
  slashed: boolean
}

/**
 * Task claim information from the OperatorRegistry contract
 */
export interface TaskClaim {
  operator: string
  claimTime: bigint
  executed: boolean
}

export interface OperatorRegistryContract {
  registerOperator(amount: bigint): Promise<ContractTransactionResponse>
  addStake(amount: bigint): Promise<ContractTransactionResponse>
  requestUnbond(): Promise<ContractTransactionResponse>
  withdrawStake(): Promise<ContractTransactionResponse>
  claimTask(taskHash: string): Promise<ContractTransactionResponse>
  canExecuteTask(caller: string, taskHash: string): Promise<boolean>
  getOperatorInfo(operator: string): Promise<OperatorInfo>
  getTaskClaim(taskHash: string): Promise<TaskClaim>
  isOperatorActive(operator: string): Promise<boolean>
  stakingToken(): Promise<string>
  minStake(): Promise<bigint>
  exclusiveWindow(): Promise<bigint>
  permissionlessDelay(): Promise<bigint>
  UNBOND_PERIOD(): Promise<bigint>
}

export interface TaskExecutorContract {
  executeTask(taskType: string, payload: string): Promise<ContractTransactionResponse>
  getHandler(taskType: string): Promise<string>
  registry(): Promise<string>
  feeManager(): Promise<string>
}

export interface ERC20Contract {
  approve(spender: string, amount: bigint): Promise<ContractTransactionResponse>
  balanceOf(account: string): Promise<bigint>
  decimals(): Promise<number>
  symbol(): Promise<string>
  allowance(owner: string, spender: string): Promise<bigint>
}

export function getRegistryContract(address: string, wallet: Wallet): OperatorRegistryContract {
  return new Contract(address, OperatorRegistryABI, wallet) as unknown as OperatorRegistryContract
}

export function getTaskExecutorContract(address: string, wallet: Wallet): TaskExecutorContract {
  return new Contract(address, TaskExecutorABI, wallet) as unknown as TaskExecutorContract
}

export function getERC20Contract(address: string, wallet: Wallet): ERC20Contract {
  return new Contract(address, ERC20ABI, wallet) as unknown as ERC20Contract
}
