import { Observable } from 'rxjs'

export interface RelayEvent {
  id: string
  transactionHash: string
  sourceChainId: number
  destinationChainId?: number
  taskType?: string
  taskHash?: string
  message?: string
  attestation?: string
  metadata?: Record<string, string>
  createdAt: string
}

export interface CoordinatorClientPort {
  connect(): Observable<RelayEvent>
  disconnect(): void
  isConnected(): boolean
}

export const COORDINATOR_CLIENT_PORT = Symbol('CoordinatorClientPort')
