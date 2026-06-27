import { Injectable, Logger, OnModuleInit, OnModuleDestroy, Inject } from '@nestjs/common'
import { Subscription } from 'rxjs'
import { RelayJob, isRetryableError } from '../../domain/entities/relay-job.entity'
import { TransactionHash } from '../../domain/value-objects/transaction-hash.value-object'
import { ChainId } from '../../domain/value-objects/chain-id.value-object'
import {
  COORDINATOR_CLIENT_PORT,
  CoordinatorClientPort,
  RelayEvent,
} from '../../domain/ports/coordinator-client.port'
import {
  ATTESTATION_PROVIDER_PORT,
  AttestationProviderPort,
} from '../../domain/ports/attestation-provider.port'
import { MESSAGE_RELAY_PORT, MessageRelayPort } from '../../domain/ports/message-relay.port'
import { RELAY_CALLBACK_PORT, RelayCallbackPort } from '../../domain/ports/relay-callback.port'
import { RelayJobRepository } from '../../infrastructure/repositories/relay-job.repository'
import { RelayJobDto, RelayJobStatusDto } from '../dto/relay-job.dto'

const TASK_CCTP_RELAY = '0x7f590974bc33c0198dbfa46b88b7e202d51129d9e12c8181dc58fc3f234def67'
const TASK_CCTP_OUTBOUND_RELAY = 'CCTP_OUTBOUND_RELAY'

// Retry configuration
const MAX_RETRIES = 3
const BASE_RETRY_DELAY_MS = 1000 // 1 second base, exponential backoff: 1s, 2s, 4s
const RETRY_CHECK_INTERVAL_MS = 500 // Check for ready retries every 500ms

@Injectable()
export class OperatorService implements OnModuleInit, OnModuleDestroy {
  private readonly logger = new Logger(OperatorService.name)
  private subscription: Subscription | null = null
  private retryInterval: ReturnType<typeof setInterval> | null = null
  private isRunning = false
  private isProcessingRetries = false

  constructor(
    @Inject(COORDINATOR_CLIENT_PORT)
    private readonly coordinatorClient: CoordinatorClientPort,
    @Inject(ATTESTATION_PROVIDER_PORT)
    private readonly attestationProvider: AttestationProviderPort,
    @Inject(MESSAGE_RELAY_PORT)
    private readonly messageRelay: MessageRelayPort,
    @Inject(RELAY_CALLBACK_PORT)
    private readonly relayCallback: RelayCallbackPort,
    private readonly jobRepository: RelayJobRepository,
  ) {}

  async onModuleInit(): Promise<void> {
    this.logger.log('Operator service initializing...')
    await this.start()
  }

  onModuleDestroy(): void {
    this.stop()
  }

  async start(): Promise<void> {
    if (this.isRunning) {
      this.logger.warn('Operator is already running')
      return
    }

    this.logger.log('Starting operator service...')
    this.isRunning = true

    const operatorAddress = this.messageRelay.getOperatorAddress()
    this.logger.log(
      `Relayer running permissionlessly as ${operatorAddress || '(no wallet configured)'} — no registration or stake required`,
    )

    this.subscription = this.coordinatorClient.connect().subscribe({
      next: (event) => void this.handleRelayEvent(event),
      error: (error) => {
        this.logger.error(`Coordinator connection error: ${error}`)
        this.isRunning = false
      },
      complete: () => {
        this.logger.log('Coordinator connection closed')
        this.isRunning = false
      },
    })

    // Start retry processing interval
    this.retryInterval = setInterval(() => {
      void this.processRetries()
    }, RETRY_CHECK_INTERVAL_MS)

    this.logger.log('Operator service started, listening for relay events...')
  }

  stop(): void {
    if (!this.isRunning) {
      return
    }

    this.logger.log('Stopping operator service...')
    this.isRunning = false

    if (this.retryInterval) {
      clearInterval(this.retryInterval)
      this.retryInterval = null
    }

    if (this.subscription) {
      this.subscription.unsubscribe()
      this.subscription = null
    }

    this.coordinatorClient.disconnect()
    this.logger.log('Operator service stopped')
  }

  private async handleRelayEvent(event: RelayEvent): Promise<void> {
    this.logger.log(`Processing relay event ${event.id} for tx ${event.transactionHash}`)

    const job = new RelayJob({
      transactionHash: new TransactionHash(event.transactionHash),
      sourceChainId: new ChainId(event.sourceChainId),
      destinationChainId: event.destinationChainId
        ? new ChainId(event.destinationChainId)
        : undefined,
      taskType: event.taskType,
      metadata: event.metadata,
      message: event.message,
      attestation: event.attestation,
    })

    this.jobRepository.save(job)

    const taskType = event.taskType || TASK_CCTP_RELAY

    if (taskType === TASK_CCTP_OUTBOUND_RELAY) {
      await this.handleOutboundRelay(job, event)
    } else {
      await this.handleInboundRelay(job, event)
    }
  }

  private async handleOutboundRelay(job: RelayJob, event: RelayEvent): Promise<void> {
    try {
      let message = event.message
      let attestation = event.attestation

      if (!message || !attestation) {
        job.startFetchingAttestation()
        this.logger.log(`Fetching attestation for outbound tx ${event.transactionHash}`)

        const attestationResult = await this.attestationProvider.waitForAttestation(
          event.transactionHash,
          event.sourceChainId,
        )

        message = attestationResult.message
        attestation = attestationResult.attestation
        job.setAttestation(message, attestation)

        this.logger.log(`Attestation received: nonce=${attestationResult.eventNonce}`)
      } else {
        job.setAttestation(message, attestation)
      }

      const destinationChainId = event.destinationChainId
      if (!destinationChainId) {
        job.fail('Missing destinationChainId for outbound relay')
        return
      }

      job.startRelaying()
      this.logger.log(`Relaying message to chain ${destinationChainId}`)

      const result = await this.messageRelay.relayMessage(destinationChainId, message, attestation)

      if (result.success && result.transactionHash) {
        job.complete(new TransactionHash(result.transactionHash))
        this.logger.log(`Outbound relay completed: tx=${result.transactionHash}`)

        const withdrawalId = event.metadata?.withdrawalId
        const callbackUrl = event.metadata?.callbackUrl
        if (withdrawalId && callbackUrl) {
          await this.relayCallback.notifyCompletion(
            callbackUrl,
            withdrawalId,
            result.transactionHash,
          )
        }
      } else {
        this.handleJobFailure(job, result.error || 'Unknown error')
      }
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error)
      this.handleJobFailure(job, errorMessage)
    }
  }

  private async handleInboundRelay(job: RelayJob, event: RelayEvent): Promise<void> {
    try {
      let message = event.message
      let attestation = event.attestation

      if (!message || !attestation) {
        job.startFetchingAttestation()
        this.logger.log(`Fetching attestation for tx ${event.transactionHash}`)

        const attestationResult = await this.attestationProvider.waitForAttestation(
          event.transactionHash,
          event.sourceChainId,
        )

        message = attestationResult.message
        attestation = attestationResult.attestation
        job.setAttestation(message, attestation)

        this.logger.log(`Attestation received: nonce=${attestationResult.eventNonce}`)
      } else {
        job.setAttestation(message, attestation)
      }

      // Permissionless settlement: anyone holding a valid attestation can call
      // EscrowReceiver.settle(message, attestation). No claim window, no stake.
      job.startRelaying()
      this.logger.log(`Settling escrow (permissionless) for tx ${event.transactionHash}`)

      const result = await this.messageRelay.settle(message, attestation)

      if (result.success && result.transactionHash) {
        job.complete(new TransactionHash(result.transactionHash))
        this.logger.log(`Settlement completed: tx=${result.transactionHash}`)

        const withdrawalId = event.metadata?.withdrawalId
        const callbackUrl = event.metadata?.callbackUrl
        if (withdrawalId && callbackUrl) {
          await this.relayCallback.notifyCompletion(
            callbackUrl,
            withdrawalId,
            result.transactionHash,
          )
        }
      } else {
        this.handleJobFailure(job, result.error || 'Unknown error')
      }
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error)
      this.handleJobFailure(job, errorMessage)
    }
  }

  private handleJobFailure(job: RelayJob, error: string): void {
    if (isRetryableError(error) && job.scheduleRetry(MAX_RETRIES, BASE_RETRY_DELAY_MS)) {
      this.logger.warn(
        `Settlement failed with retryable error, scheduling retry ${job.retryCount}/${MAX_RETRIES} ` +
          `in ${Math.pow(2, job.retryCount - 1)}s: ${error}`,
      )
    } else {
      job.fail(error)
      if (!isRetryableError(error)) {
        this.logger.error(`Settlement failed with non-retryable error: ${error}`)
      } else {
        this.logger.error(`Settlement failed after ${job.retryCount} retries: ${error}`)
      }
    }
  }

  private async processRetries(): Promise<void> {
    if (this.isProcessingRetries) {
      return
    }

    const readyJobs = this.jobRepository.findReadyForRetry()
    if (readyJobs.length === 0) {
      return
    }

    this.isProcessingRetries = true

    for (const job of readyJobs) {
      if (!this.isRunning) {
        break
      }

      this.logger.log(`Retrying job ${job.id} (attempt ${job.retryCount}/${MAX_RETRIES})`)
      await this.executeJob(job)
    }

    this.isProcessingRetries = false
  }

  private async executeJob(job: RelayJob): Promise<void> {
    try {
      const message = job.message
      const attestation = job.attestation

      if (!message || !attestation) {
        job.fail('Missing message or attestation for retry')
        return
      }

      job.startRetry()
      this.logger.log(`Settling escrow (retry ${job.retryCount})...`)

      const result = await this.messageRelay.settle(message, attestation)

      if (result.success && result.transactionHash) {
        job.complete(new TransactionHash(result.transactionHash))
        this.logger.log(`Retry succeeded: tx=${result.transactionHash}`)
      } else {
        this.handleJobFailure(job, result.error || 'Unknown error')
      }
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error)
      this.handleJobFailure(job, errorMessage)
    }
  }

  getStatus(): { isRunning: boolean; isConnected: boolean; operatorAddress: string } {
    return {
      isRunning: this.isRunning,
      isConnected: this.coordinatorClient.isConnected(),
      operatorAddress: this.messageRelay.getOperatorAddress(),
    }
  }

  getJobStatus(): RelayJobStatusDto {
    const counts = this.jobRepository.countByStatus()
    return {
      totalJobs: this.jobRepository.count(),
      pending: counts['pending'] || 0,
      fetchingAttestation: counts['fetching_attestation'] || 0,
      executing: counts['executing'] || 0,
      completed: counts['completed'] || 0,
      failed: counts['failed'] || 0,
      pendingRetry: counts['pending_retry'] || 0,
    }
  }

  getJobs(): RelayJobDto[] {
    return this.jobRepository.findAll().map((job) => job.toJSON() as RelayJobDto)
  }

  getJob(id: string): RelayJobDto | undefined {
    const job = this.jobRepository.findById(id)
    return job ? (job.toJSON() as RelayJobDto) : undefined
  }
}
