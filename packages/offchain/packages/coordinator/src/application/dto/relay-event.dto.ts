export class RelayEventDto {
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
