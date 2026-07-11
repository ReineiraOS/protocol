import { randomUUID } from 'node:crypto'
import { TransactionHash } from '../value-objects/transaction-hash.value-object'
import { ChainId } from '../value-objects/chain-id.value-object'
import { MessageHash } from '../value-objects/message-hash.value-object'

export type RelayJobStatus =
  | 'pending'
  | 'fetching_attestation'
  | 'executing'
  | 'completed'
  | 'failed'
  | 'pending_retry'

// Errors that should not be retried (permanent failures)
const NON_RETRYABLE_ERRORS = [
  'already executed',
  'already received',
  'message already processed',
  'Not authorized',
]

export function isRetryableError(error: string): boolean {
  const lowerError = error.toLowerCase()
  return !NON_RETRYABLE_ERRORS.some((e) => lowerError.includes(e.toLowerCase()))
}

export interface RelayJobProps {
  transactionHash: TransactionHash
  sourceChainId: ChainId
  destinationChainId?: ChainId
  taskType?: string
  metadata?: Record<string, string>
  message?: string
  attestation?: string
}

export class RelayJob {
  readonly id: string
  readonly transactionHash: TransactionHash
  readonly sourceChainId: ChainId
  readonly destinationChainId?: ChainId
  readonly taskType?: string
  readonly metadata?: Record<string, string>
  readonly createdAt: Date

  private _status: RelayJobStatus
  private _message?: string
  private _attestation?: string
  private _messageHash?: MessageHash
  private _executionTxHash?: TransactionHash
  private _operatorFee?: bigint
  private _error?: string
  private _completedAt?: Date
  private _retryCount: number = 0
  private _nextRetryAt?: Date
  private _lastError?: string

  constructor(props: RelayJobProps) {
    this.id = randomUUID()
    this.transactionHash = props.transactionHash
    this.sourceChainId = props.sourceChainId
    this.destinationChainId = props.destinationChainId
    this.taskType = props.taskType
    this.metadata = props.metadata
    this.createdAt = new Date()
    this._status = 'pending'
    this._message = props.message
    this._attestation = props.attestation
  }

  get status(): RelayJobStatus {
    return this._status
  }

  get message(): string | undefined {
    return this._message
  }

  get attestation(): string | undefined {
    return this._attestation
  }

  get messageHash(): MessageHash | undefined {
    return this._messageHash
  }

  get executionTxHash(): TransactionHash | undefined {
    return this._executionTxHash
  }

  get operatorFee(): bigint | undefined {
    return this._operatorFee
  }

  get error(): string | undefined {
    return this._error
  }

  get completedAt(): Date | undefined {
    return this._completedAt
  }

  get retryCount(): number {
    return this._retryCount
  }

  get nextRetryAt(): Date | undefined {
    return this._nextRetryAt
  }

  get lastError(): string | undefined {
    return this._lastError
  }

  get isReadyForRetry(): boolean {
    return (
      this._status === 'pending_retry' &&
      this._nextRetryAt !== undefined &&
      new Date() >= this._nextRetryAt
    )
  }

  get hasAttestation(): boolean {
    return this._message !== undefined && this._attestation !== undefined
  }

  startFetchingAttestation(): void {
    if (this._status !== 'pending') {
      throw new Error(`Cannot start fetching attestation from status: ${this._status}`)
    }
    this._status = 'fetching_attestation'
  }

  setAttestation(message: string, attestation: string): void {
    this._message = message
    this._attestation = attestation
    this._messageHash = MessageHash.fromMessage(message)
  }

  startRelaying(): void {
    if (this._status !== 'pending' && this._status !== 'fetching_attestation') {
      throw new Error(`Cannot start relaying from status: ${this._status}`)
    }
    this._status = 'executing'
  }

  complete(executionTxHash: TransactionHash, operatorFee?: bigint): void {
    if (this._status !== 'executing') {
      throw new Error(`Cannot complete from status: ${this._status}`)
    }
    this._status = 'completed'
    this._executionTxHash = executionTxHash
    this._operatorFee = operatorFee
    this._completedAt = new Date()
  }

  fail(error: string): void {
    this._status = 'failed'
    this._error = error
    this._completedAt = new Date()
  }

  /**
   * Schedule a retry with exponential backoff
   * @param maxRetries Maximum number of retries allowed
   * @param baseDelayMs Base delay in milliseconds (default 1000ms)
   * @returns true if retry was scheduled, false if max retries exceeded
   */
  scheduleRetry(maxRetries: number = 3, baseDelayMs: number = 1000): boolean {
    if (this._retryCount >= maxRetries) {
      return false
    }

    this._lastError = this._error
    this._error = undefined
    this._retryCount++

    // Exponential backoff: 1s, 2s, 4s, 8s, etc.
    const delayMs = baseDelayMs * Math.pow(2, this._retryCount - 1)
    this._nextRetryAt = new Date(Date.now() + delayMs)
    this._status = 'pending_retry'

    return true
  }

  /**
   * Reset job to executing state for retry execution (permissionless settle —
   * no claim phase).
   */
  startRetry(): void {
    if (this._status !== 'pending_retry') {
      throw new Error(`Cannot start retry from status: ${this._status}`)
    }
    this._status = 'executing'
    this._nextRetryAt = undefined
  }

  toJSON(): {
    id: string
    transactionHash: string
    sourceChainId: number
    destinationChainId?: number
    taskType?: string
    metadata?: Record<string, string>
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
  } {
    return {
      id: this.id,
      transactionHash: this.transactionHash.value,
      sourceChainId: this.sourceChainId.value,
      destinationChainId: this.destinationChainId?.value,
      taskType: this.taskType,
      metadata: this.metadata,
      status: this._status,
      message: this._message,
      attestation: this._attestation,
      messageHash: this._messageHash?.value,
      executionTxHash: this._executionTxHash?.value,
      operatorFee: this._operatorFee?.toString(),
      error: this._error,
      createdAt: this.createdAt.toISOString(),
      completedAt: this._completedAt?.toISOString(),
      retryCount: this._retryCount,
      nextRetryAt: this._nextRetryAt?.toISOString(),
      lastError: this._lastError,
    }
  }
}
