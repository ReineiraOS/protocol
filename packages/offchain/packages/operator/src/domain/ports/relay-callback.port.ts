export interface RelayCallbackPort {
  notifyCompletion(
    callbackUrl: string,
    withdrawalId: string,
    destinationTxHash: string,
  ): Promise<void>
}

export const RELAY_CALLBACK_PORT = Symbol('RelayCallbackPort')
