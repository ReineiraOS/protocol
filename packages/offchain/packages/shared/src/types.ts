/**
 * Result of a relay / settlement transaction.
 */
export interface TaskResult {
  success: boolean
  transactionHash: string
  result: Uint8Array
}

/**
 * CCTP payload: Circle message + attestation, as passed to
 * `CCTPV2EscrowReceiver.settle(message, attestation)`.
 */
export interface CCTPPayload {
  message: string
  attestation: string
}

export interface RelayMetadata {
  withdrawalId?: string
  callbackUrl?: string
}
