export interface MessageRelayResult {
  success: boolean
  transactionHash?: string
  error?: string
}

export interface MessageRelayPort {
  /**
   * Generic CCTP relay: deliver a Circle attestation to the destination
   * MessageTransmitter (mints USDC to the recipient). Permissionless.
   */
  relayMessage(
    destinationChainId: number,
    message: string,
    attestation: string,
  ): Promise<MessageRelayResult>

  /**
   * Settle a bridged message into a confidential escrow by calling the
   * permissionless `CCTPV2EscrowReceiver.settle(message, attestation)` entry
   * point on the configured escrow chain. Replaces the former claim + execute
   * task flow — anyone holding a valid attestation can settle.
   */
  settle(message: string, attestation: string): Promise<MessageRelayResult>

  /** Address of the relayer wallet used to submit settlement transactions. */
  getOperatorAddress(): string
}

export const MESSAGE_RELAY_PORT = Symbol('MessageRelayPort')
