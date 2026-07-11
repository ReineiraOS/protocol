import { randomUUID } from 'node:crypto'
import { ChainId } from '../value-objects/chain-id.value-object'
import { TransactionHash } from '../value-objects/transaction-hash.value-object'

export interface RelayMessageProps {
  transactionHash: TransactionHash
  sourceChainId: ChainId
  destinationChainId?: ChainId
  taskType?: string
  metadata?: Record<string, string>
  message?: string
  attestation?: string
}

export class RelayMessage {
  readonly id: string
  readonly transactionHash: TransactionHash
  readonly sourceChainId: ChainId
  readonly destinationChainId?: ChainId
  readonly taskType?: string
  readonly metadata?: Record<string, string>
  readonly createdAt: Date
  private _message?: string
  private _attestation?: string
  private _assignedOperator?: string
  private _assignedAt?: Date

  constructor(props: RelayMessageProps) {
    this.id = randomUUID()
    this.transactionHash = props.transactionHash
    this.sourceChainId = props.sourceChainId
    this.destinationChainId = props.destinationChainId
    this.taskType = props.taskType
    this.metadata = props.metadata
    this.createdAt = new Date()
    this._message = props.message
    this._attestation = props.attestation
  }

  get message(): string | undefined {
    return this._message
  }

  get attestation(): string | undefined {
    return this._attestation
  }

  get assignedOperator(): string | undefined {
    return this._assignedOperator
  }

  get assignedAt(): Date | undefined {
    return this._assignedAt
  }

  get isAssigned(): boolean {
    return this._assignedOperator !== undefined
  }

  assignTo(operatorAddress: string): void {
    this._assignedOperator = operatorAddress
    this._assignedAt = new Date()
  }

  updateAttestation(message: string, attestation: string): void {
    this._message = message
    this._attestation = attestation
  }

  toJSON(): Record<string, unknown> {
    return {
      id: this.id,
      transactionHash: this.transactionHash.value,
      sourceChainId: this.sourceChainId.value,
      destinationChainId: this.destinationChainId?.value,
      taskType: this.taskType,
      metadata: this.metadata,
      message: this._message,
      attestation: this._attestation,
      assignedOperator: this._assignedOperator,
      assignedAt: this._assignedAt?.toISOString(),
      createdAt: this.createdAt.toISOString(),
    }
  }
}
