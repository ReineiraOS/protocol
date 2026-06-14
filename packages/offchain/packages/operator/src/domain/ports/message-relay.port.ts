export interface MessageRelayResult {
  success: boolean
  transactionHash?: string
  error?: string
}

export interface MessageRelayPort {
  relayMessage(
    destinationChainId: number,
    message: string,
    attestation: string,
  ): Promise<MessageRelayResult>
}

export const MESSAGE_RELAY_PORT = Symbol('MessageRelayPort')
