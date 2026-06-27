export class RelayJobDto {
  id: string
  transactionHash: string
  sourceChainId: number
  status: string
  message?: string
  attestation?: string
  messageHash?: string
  executionTxHash?: string
  operatorFee?: string
  error?: string
  createdAt: string
  completedAt?: string
  retryCount: number
  nextRetryAt?: string
  lastError?: string
}

export class RelayJobStatusDto {
  totalJobs: number
  pending: number
  fetchingAttestation: number
  executing: number
  completed: number
  failed: number
  pendingRetry: number
}
