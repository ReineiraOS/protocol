export interface TaskResult {
  success: boolean
  transactionHash?: string
  operatorFee?: bigint
  error?: string
}

export interface OperatorStatus {
  address: string
  isActive: boolean
  stake: bigint
  unbondRequestTime: bigint
  slashed: boolean
}

export interface TaskExecutorPort {
  canExecuteTask(taskHash: string): Promise<boolean>
  claimTask(taskHash: string): Promise<string | null>
  executeTask(taskType: string, payload: string): Promise<TaskResult>
  getOperatorStatus(): Promise<OperatorStatus | null>
  getOperatorAddress(): string
}

export const TASK_EXECUTOR_PORT = Symbol('TaskExecutorPort')
