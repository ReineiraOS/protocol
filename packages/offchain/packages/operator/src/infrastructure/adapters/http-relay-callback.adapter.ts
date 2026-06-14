import { Injectable, Logger } from '@nestjs/common'
import { ConfigService } from '@nestjs/config'
import { request } from 'undici'
import { RelayCallbackPort } from '../../domain/ports/relay-callback.port'

const MAX_RETRIES = 3
const RETRY_DELAY_MS = 1000

@Injectable()
export class HttpRelayCallbackAdapter implements RelayCallbackPort {
  private readonly logger = new Logger(HttpRelayCallbackAdapter.name)
  private readonly callbackSecret: string

  constructor(configService: ConfigService) {
    this.callbackSecret = configService.get<string>('RELAY_CALLBACK_SECRET', '')
  }

  async notifyCompletion(
    callbackUrl: string,
    withdrawalId: string,
    destinationTxHash: string,
  ): Promise<void> {
    const body = JSON.stringify({
      withdrawal_id: withdrawalId,
      destination_tx_hash: destinationTxHash,
      status: 'COMPLETED',
    })

    for (let attempt = 1; attempt <= MAX_RETRIES; attempt++) {
      try {
        const { statusCode } = await request(callbackUrl, {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            ...(this.callbackSecret ? { 'X-Relay-Secret': this.callbackSecret } : {}),
          },
          body,
        })

        if (statusCode >= 200 && statusCode < 300) {
          this.logger.log(`Callback sent for withdrawal ${withdrawalId}: ${statusCode}`)
          return
        }

        this.logger.warn(
          `Callback returned ${statusCode} for withdrawal ${withdrawalId} (attempt ${attempt}/${MAX_RETRIES})`,
        )
      } catch (error) {
        const errorMessage = error instanceof Error ? error.message : String(error)
        this.logger.warn(
          `Callback failed for withdrawal ${withdrawalId} (attempt ${attempt}/${MAX_RETRIES}): ${errorMessage}`,
        )
      }

      if (attempt < MAX_RETRIES) {
        await new Promise((resolve) => setTimeout(resolve, RETRY_DELAY_MS * attempt))
      }
    }

    this.logger.error(`Callback exhausted retries for withdrawal ${withdrawalId} at ${callbackUrl}`)
  }
}
