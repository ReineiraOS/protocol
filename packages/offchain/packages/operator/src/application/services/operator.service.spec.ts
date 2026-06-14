/* eslint-disable @typescript-eslint/unbound-method */
import { Subject } from 'rxjs'
import { Attestation } from '../../domain/entities/attestation.entity'
import { RelayJobRepository } from '../../infrastructure/repositories/relay-job.repository'
import { CoordinatorClientPort, RelayEvent } from '../../domain/ports/coordinator-client.port'
import { AttestationProviderPort } from '../../domain/ports/attestation-provider.port'
import { TaskExecutorPort, TaskResult } from '../../domain/ports/task-executor.port'
import { MessageRelayPort, MessageRelayResult } from '../../domain/ports/message-relay.port'
import { RelayCallbackPort } from '../../domain/ports/relay-callback.port'
import { OperatorService } from './operator.service'

const VALID_TX_HASH = '0x' + 'a'.repeat(64)
const RESULT_TX_HASH = '0x' + 'b'.repeat(64)
const VALID_MESSAGE = '0x' + 'c'.repeat(64)
const VALID_ATTESTATION = '0x' + 'd'.repeat(64)

function createMockEvent(overrides: Partial<RelayEvent> = {}): RelayEvent {
  return {
    id: 'event-1',
    transactionHash: VALID_TX_HASH,
    sourceChainId: 421614,
    createdAt: new Date().toISOString(),
    ...overrides,
  }
}

function createOutboundEvent(overrides: Partial<RelayEvent> = {}): RelayEvent {
  return createMockEvent({
    taskType: 'CCTP_OUTBOUND_RELAY',
    destinationChainId: 11155111,
    message: VALID_MESSAGE,
    attestation: VALID_ATTESTATION,
    metadata: {
      withdrawalId: 'wd-123',
      callbackUrl: 'https://api.example.com/callback',
    },
    ...overrides,
  })
}

function createMockAttestation(): Attestation {
  return new Attestation({
    message: VALID_MESSAGE,
    attestation: VALID_ATTESTATION,
    status: 'complete',
    eventNonce: '12345',
  })
}

describe('OperatorService', () => {
  let service: OperatorService
  let eventSubject: Subject<RelayEvent>
  let jobRepository: RelayJobRepository
  let mockCoordinatorClient: jest.Mocked<CoordinatorClientPort>
  let mockAttestationProvider: jest.Mocked<AttestationProviderPort>
  let mockTaskExecutor: jest.Mocked<TaskExecutorPort>
  let mockMessageRelay: jest.Mocked<MessageRelayPort>
  let mockRelayCallback: jest.Mocked<RelayCallbackPort>

  beforeEach(() => {
    eventSubject = new Subject<RelayEvent>()
    jobRepository = new RelayJobRepository()

    mockCoordinatorClient = {
      connect: jest.fn().mockReturnValue(eventSubject.asObservable()),
      disconnect: jest.fn(),
      isConnected: jest.fn().mockReturnValue(true),
    }

    mockAttestationProvider = {
      getAttestation: jest.fn(),
      waitForAttestation: jest.fn().mockResolvedValue(createMockAttestation()),
    }

    mockTaskExecutor = {
      canExecuteTask: jest.fn().mockResolvedValue(true),
      claimTask: jest.fn().mockResolvedValue(RESULT_TX_HASH),
      executeTask: jest.fn().mockResolvedValue({
        success: true,
        transactionHash: RESULT_TX_HASH,
        operatorFee: 100n,
      } as TaskResult),
      getOperatorStatus: jest.fn().mockResolvedValue({
        address: '0x' + '1'.repeat(40),
        isActive: true,
        stake: 5000n,
        unbondRequestTime: 0n,
        slashed: false,
      }),
      getOperatorAddress: jest.fn().mockReturnValue('0x' + '1'.repeat(40)),
    }

    mockMessageRelay = {
      relayMessage: jest.fn().mockResolvedValue({
        success: true,
        transactionHash: RESULT_TX_HASH,
      } as MessageRelayResult),
    }

    mockRelayCallback = {
      notifyCompletion: jest.fn().mockResolvedValue(undefined),
    }

    service = new OperatorService(
      mockCoordinatorClient,
      mockAttestationProvider,
      mockTaskExecutor,
      mockMessageRelay,
      mockRelayCallback,
      jobRepository,
    )
  })

  afterEach(() => {
    service.stop()
  })

  async function startAndEmit(event: RelayEvent): Promise<void> {
    await service.start()
    eventSubject.next(event)
    await new Promise((resolve) => setTimeout(resolve, 50))
  }

  describe('outbound relay', () => {
    it('should relay message to destination chain via messageRelay', async () => {
      await startAndEmit(createOutboundEvent())

      expect(mockMessageRelay.relayMessage).toHaveBeenCalledWith(
        11155111,
        VALID_MESSAGE,
        VALID_ATTESTATION,
      )
      expect(mockTaskExecutor.executeTask).not.toHaveBeenCalled()
    })

    it('should send callback notification on success', async () => {
      await startAndEmit(createOutboundEvent())

      expect(mockRelayCallback.notifyCompletion).toHaveBeenCalledWith(
        'https://api.example.com/callback',
        'wd-123',
        RESULT_TX_HASH,
      )
    })

    it('should skip callback when metadata is missing', async () => {
      await startAndEmit(createOutboundEvent({ metadata: undefined }))

      expect(mockMessageRelay.relayMessage).toHaveBeenCalled()
      expect(mockRelayCallback.notifyCompletion).not.toHaveBeenCalled()
    })

    it('should skip callback when only withdrawalId is present', async () => {
      await startAndEmit(createOutboundEvent({ metadata: { withdrawalId: 'wd-123' } }))

      expect(mockRelayCallback.notifyCompletion).not.toHaveBeenCalled()
    })

    it('should fetch attestation when not provided in event', async () => {
      await startAndEmit(createOutboundEvent({ message: undefined, attestation: undefined }))

      expect(mockAttestationProvider.waitForAttestation).toHaveBeenCalledWith(VALID_TX_HASH, 421614)
      expect(mockMessageRelay.relayMessage).toHaveBeenCalledWith(
        11155111,
        VALID_MESSAGE,
        VALID_ATTESTATION,
      )
    })

    it('should fail job when destinationChainId is missing', async () => {
      await startAndEmit(createOutboundEvent({ destinationChainId: undefined }))

      expect(mockMessageRelay.relayMessage).not.toHaveBeenCalled()

      const jobs = jobRepository.findAll()
      expect(jobs).toHaveLength(1)
      expect(jobs[0].status).toBe('failed')
      expect(jobs[0].error).toBe('Missing destinationChainId for outbound relay')
    })

    it('should handle relay failure with retry', async () => {
      mockMessageRelay.relayMessage.mockResolvedValue({
        success: false,
        error: 'Network timeout',
      })

      await startAndEmit(createOutboundEvent())

      const jobs = jobRepository.findAll()
      expect(jobs).toHaveLength(1)
      expect(jobs[0].status).toBe('pending_retry')
      expect(jobs[0].retryCount).toBe(1)
    })

    it('should fail permanently on non-retryable relay error', async () => {
      mockMessageRelay.relayMessage.mockResolvedValue({
        success: false,
        error: 'already received',
      })

      await startAndEmit(createOutboundEvent())

      const jobs = jobRepository.findAll()
      expect(jobs).toHaveLength(1)
      expect(jobs[0].status).toBe('failed')
    })

    it('should handle attestation fetch error', async () => {
      mockAttestationProvider.waitForAttestation.mockRejectedValue(
        new Error('Attestation timeout after 300000ms'),
      )

      await startAndEmit(createOutboundEvent({ message: undefined, attestation: undefined }))

      const jobs = jobRepository.findAll()
      expect(jobs).toHaveLength(1)
      expect(jobs[0].status).toBe('pending_retry')
    })

    it('should complete job with correct transaction hash', async () => {
      await startAndEmit(createOutboundEvent())

      const jobs = jobRepository.findAll()
      expect(jobs).toHaveLength(1)
      expect(jobs[0].status).toBe('completed')
      expect(jobs[0].executionTxHash?.value).toBe(RESULT_TX_HASH)
    })
  })

  describe('inbound relay', () => {
    it('should use taskExecutor for inbound events', async () => {
      await startAndEmit(
        createMockEvent({
          message: VALID_MESSAGE,
          attestation: VALID_ATTESTATION,
        }),
      )

      expect(mockTaskExecutor.claimTask).toHaveBeenCalled()
      expect(mockTaskExecutor.executeTask).toHaveBeenCalled()
      expect(mockMessageRelay.relayMessage).not.toHaveBeenCalled()
    })

    it('should fetch attestation when not provided', async () => {
      await startAndEmit(createMockEvent())

      expect(mockAttestationProvider.waitForAttestation).toHaveBeenCalledWith(VALID_TX_HASH, 421614)
    })

    it('should complete job on successful execution', async () => {
      await startAndEmit(
        createMockEvent({
          message: VALID_MESSAGE,
          attestation: VALID_ATTESTATION,
        }),
      )

      const jobs = jobRepository.findAll()
      expect(jobs).toHaveLength(1)
      expect(jobs[0].status).toBe('completed')
      expect(jobs[0].operatorFee).toBe(100n)
    })

    it('should handle task execution failure', async () => {
      mockTaskExecutor.executeTask.mockResolvedValue({
        success: false,
        error: 'revert',
      })

      await startAndEmit(
        createMockEvent({
          message: VALID_MESSAGE,
          attestation: VALID_ATTESTATION,
        }),
      )

      const jobs = jobRepository.findAll()
      expect(jobs).toHaveLength(1)
      expect(jobs[0].status).toBe('pending_retry')
    })
  })

  describe('task type routing', () => {
    it('should route CCTP_OUTBOUND_RELAY to outbound handler', async () => {
      await startAndEmit(createOutboundEvent())

      expect(mockMessageRelay.relayMessage).toHaveBeenCalled()
      expect(mockTaskExecutor.executeTask).not.toHaveBeenCalled()
    })

    it('should route default events to inbound handler', async () => {
      await startAndEmit(
        createMockEvent({
          message: VALID_MESSAGE,
          attestation: VALID_ATTESTATION,
        }),
      )

      expect(mockTaskExecutor.executeTask).toHaveBeenCalled()
      expect(mockMessageRelay.relayMessage).not.toHaveBeenCalled()
    })

    it('should route CCTP_RELAY to inbound handler', async () => {
      await startAndEmit(
        createMockEvent({
          taskType: '0x7f590974bc33c0198dbfa46b88b7e202d51129d9e12c8181dc58fc3f234def67',
          message: VALID_MESSAGE,
          attestation: VALID_ATTESTATION,
        }),
      )

      expect(mockTaskExecutor.executeTask).toHaveBeenCalled()
      expect(mockMessageRelay.relayMessage).not.toHaveBeenCalled()
    })
  })

  describe('lifecycle', () => {
    it('should connect to coordinator on start', async () => {
      await service.start()

      expect(mockCoordinatorClient.connect).toHaveBeenCalled()
      expect(mockTaskExecutor.getOperatorStatus).toHaveBeenCalled()
    })

    it('should disconnect on stop', async () => {
      await service.start()
      service.stop()

      expect(mockCoordinatorClient.disconnect).toHaveBeenCalled()
    })

    it('should not start twice', async () => {
      await service.start()
      await service.start()

      expect(mockCoordinatorClient.connect).toHaveBeenCalledTimes(1)
    })

    it('should report status', async () => {
      await service.start()

      const status = service.getStatus()
      expect(status.isRunning).toBe(true)
      expect(status.isConnected).toBe(true)
      expect(status.operatorAddress).toBe('0x' + '1'.repeat(40))
    })
  })

  describe('job queries', () => {
    it('should return job status counts', async () => {
      await startAndEmit(createOutboundEvent())

      const status = service.getJobStatus()
      expect(status.totalJobs).toBe(1)
      expect(status.completed).toBe(1)
    })

    it('should return all jobs as DTOs', async () => {
      await startAndEmit(createOutboundEvent())

      const jobs = service.getJobs()
      expect(jobs).toHaveLength(1)
      expect(jobs[0].transactionHash).toBe(VALID_TX_HASH)
    })

    it('should return single job by id', async () => {
      await startAndEmit(createOutboundEvent())

      const allJobs = service.getJobs()
      const job = service.getJob(allJobs[0].id)
      expect(job).toBeDefined()
      expect(job!.status).toBe('completed')
    })

    it('should return undefined for unknown job id', () => {
      const job = service.getJob('nonexistent')
      expect(job).toBeUndefined()
    })
  })
})
