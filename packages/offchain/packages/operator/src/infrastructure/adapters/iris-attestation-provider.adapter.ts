import { Injectable, Logger } from '@nestjs/common'
import { ConfigService } from '@nestjs/config'
import { request } from 'undici'
import { AttestationProviderPort } from '../../domain/ports/attestation-provider.port'
import { Attestation } from '../../domain/entities/attestation.entity'

/**
 * Mapping from EVM chain IDs to CCTP domain IDs
 * @see https://developers.circle.com/stablecoins/supported-domains
 */
const CHAIN_ID_TO_CCTP_DOMAIN: Record<number, number> = {
  // Mainnets
  1: 0, // Ethereum
  43114: 1, // Avalanche
  10: 2, // Optimism
  42161: 3, // Arbitrum
  8453: 6, // Base
  137: 7, // Polygon

  // Testnets
  11155111: 0, // Ethereum Sepolia
  43113: 1, // Avalanche Fuji
  11155420: 2, // Optimism Sepolia
  421614: 3, // Arbitrum Sepolia
  84532: 6, // Base Sepolia
  80002: 7, // Polygon Amoy
}

interface CCTPMessage {
  message: string
  eventNonce: string
  attestation: string
  cctpVersion: number
  status: string
}

interface IrisApiResponse {
  messages?: CCTPMessage[]
}

@Injectable()
export class IrisAttestationProviderAdapter implements AttestationProviderPort {
  private readonly logger = new Logger(IrisAttestationProviderAdapter.name)
  private readonly irisApiUrl: string
  private readonly defaultTimeoutMs: number
  private readonly defaultPollIntervalMs: number

  constructor(configService: ConfigService) {
    this.irisApiUrl = configService.get<string>(
      'IRIS_API_URL',
      'https://iris-api-sandbox.circle.com',
    )
    this.defaultTimeoutMs = configService.get<number>('ATTESTATION_TIMEOUT_MS', 300000)
    this.defaultPollIntervalMs = configService.get<number>('POLLING_INTERVAL_MS', 2000)
  }

  async getAttestation(txHash: string, sourceChainId: number): Promise<Attestation | null> {
    const sourceDomain = this.chainIdToCctpDomain(sourceChainId)
    const url = `${this.irisApiUrl}/v2/messages/${sourceDomain}?transactionHash=${txHash}`

    try {
      const { statusCode, body } = await request(url, {
        method: 'GET',
        headers: {
          Accept: 'application/json',
        },
      })

      if (statusCode !== 200) {
        this.logger.debug(`Iris API returned ${statusCode} for tx ${txHash}`)
        return null
      }

      const data = (await body.json()) as IrisApiResponse

      if (data.messages && data.messages.length > 0) {
        const msg = data.messages[0]

        if (msg.attestation && msg.attestation !== 'PENDING') {
          return new Attestation({
            message: msg.message,
            attestation: msg.attestation,
            status: msg.status,
            eventNonce: msg.eventNonce,
          })
        }
      }

      return null
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error)
      this.logger.debug(`Error fetching attestation: ${errorMessage}`)
      return null
    }
  }

  async waitForAttestation(
    txHash: string,
    sourceChainId: number,
    timeoutMs?: number,
    pollIntervalMs?: number,
  ): Promise<Attestation> {
    const timeout = timeoutMs ?? this.defaultTimeoutMs
    const pollInterval = pollIntervalMs ?? this.defaultPollIntervalMs
    const startTime = Date.now()
    const sourceDomain = this.chainIdToCctpDomain(sourceChainId)

    this.logger.log(
      `Waiting for attestation for tx ${txHash} from chain ${sourceChainId} (CCTP domain ${sourceDomain})`,
    )

    while (Date.now() - startTime < timeout) {
      const attestation = await this.getAttestation(txHash, sourceChainId)

      if (attestation) {
        const elapsed = Math.floor((Date.now() - startTime) / 1000)
        this.logger.log(`Attestation received for tx ${txHash} in ${elapsed}s`)
        return attestation
      }

      const elapsed = Math.floor((Date.now() - startTime) / 1000)
      this.logger.debug(`Attestation pending (${elapsed}s elapsed)`)

      await this.sleep(pollInterval)
    }

    throw new Error(`Attestation timeout after ${timeout}ms for tx ${txHash}`)
  }

  private sleep(ms: number): Promise<void> {
    return new Promise((resolve) => setTimeout(resolve, ms))
  }

  private chainIdToCctpDomain(chainId: number): number {
    const domain = CHAIN_ID_TO_CCTP_DOMAIN[chainId]
    if (domain === undefined) {
      throw new Error(`Unknown chain ID: ${chainId}. No CCTP domain mapping found.`)
    }
    return domain
  }
}
