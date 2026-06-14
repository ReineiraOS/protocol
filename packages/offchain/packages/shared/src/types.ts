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

/**
 * Result of task execution
 */
export interface TaskResult {
  success: boolean
  transactionHash: string
  operatorFee: bigint
  result: Uint8Array
}

/**
 * Operator status for the operator service
 */
export interface OperatorStatus {
  stake: bigint
  isActive: boolean
  unbondRequestTime: bigint
  slashed: boolean
}

/**
 * CCTP payload structure for task execution
 */
export interface CCTPPayload {
  message: string
  attestation: string
}

export interface RelayMetadata {
  withdrawalId?: string
  callbackUrl?: string
}
