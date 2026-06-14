import { RelayJob, isRetryableError } from './relay-job.entity'
import { TransactionHash } from '../value-objects/transaction-hash.value-object'
import { ChainId } from '../value-objects/chain-id.value-object'

describe('RelayJob', () => {
  const validTxHash = '0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef'
  const validMessage = '0x000000010000000600000000abcdef'
  const validAttestation = '0xabcdef1234567890'

  const createJob = (
    props?: Partial<{
      message: string
      attestation: string
      destinationChainId: ChainId
      taskType: string
      metadata: Record<string, string>
    }>,
  ) =>
    new RelayJob({
      transactionHash: new TransactionHash(validTxHash),
      sourceChainId: new ChainId(6),
      ...props,
    })

  describe('constructor', () => {
    it('should create a job with required properties', () => {
      const job = createJob()

      expect(job.id).toBeDefined()
      expect(job.transactionHash.value).toBe(validTxHash)
      expect(job.sourceChainId.value).toBe(6)
      expect(job.status).toBe('pending')
      expect(job.createdAt).toBeInstanceOf(Date)
    })

    it('should create a job with optional message and attestation', () => {
      const job = createJob({ message: validMessage, attestation: validAttestation })

      expect(job.message).toBe(validMessage)
      expect(job.attestation).toBe(validAttestation)
    })

    it('should create a job with destinationChainId, taskType, and metadata', () => {
      const job = createJob({
        destinationChainId: new ChainId(11155111),
        taskType: 'CCTP_OUTBOUND_RELAY',
        metadata: { withdrawalId: 'wd-123', callbackUrl: 'https://example.com/callback' },
      })

      expect(job.destinationChainId?.value).toBe(11155111)
      expect(job.taskType).toBe('CCTP_OUTBOUND_RELAY')
      expect(job.metadata).toEqual({
        withdrawalId: 'wd-123',
        callbackUrl: 'https://example.com/callback',
      })
    })

    it('should leave optional outbound fields undefined when not provided', () => {
      const job = createJob()

      expect(job.destinationChainId).toBeUndefined()
      expect(job.taskType).toBeUndefined()
      expect(job.metadata).toBeUndefined()
    })
  })

  describe('hasAttestation', () => {
    it('should return false when no attestation', () => {
      const job = createJob()
      expect(job.hasAttestation).toBe(false)
    })

    it('should return true when both message and attestation set', () => {
      const job = createJob({ message: validMessage, attestation: validAttestation })
      expect(job.hasAttestation).toBe(true)
    })
  })

  describe('state transitions', () => {
    it('should transition from pending to fetching_attestation', () => {
      const job = createJob()
      job.startFetchingAttestation()
      expect(job.status).toBe('fetching_attestation')
    })

    it('should transition from fetching_attestation to claiming', () => {
      const job = createJob()
      job.startFetchingAttestation()
      job.startClaiming()
      expect(job.status).toBe('claiming')
    })

    it('should transition from claiming to executing', () => {
      const job = createJob()
      job.startFetchingAttestation()
      job.startClaiming()
      job.startExecuting()
      expect(job.status).toBe('executing')
    })

    it('should transition from executing to completed', () => {
      const job = createJob()
      job.startFetchingAttestation()
      job.startClaiming()
      job.startExecuting()
      job.complete(new TransactionHash(validTxHash), 1000n)

      expect(job.status).toBe('completed')
      expect(job.executionTxHash?.value).toBe(validTxHash)
      expect(job.operatorFee).toBe(1000n)
      expect(job.completedAt).toBeInstanceOf(Date)
    })

    it('should throw when starting fetch from non-pending state', () => {
      const job = createJob()
      job.startFetchingAttestation()
      expect(() => job.startFetchingAttestation()).toThrow()
    })

    it('should throw when claiming from invalid state', () => {
      const job = createJob()
      job.startFetchingAttestation()
      job.startClaiming()
      expect(() => job.startClaiming()).toThrow()
    })

    it('should transition from pending to executing via startRelaying', () => {
      const job = createJob()
      job.startRelaying()
      expect(job.status).toBe('executing')
    })

    it('should transition from fetching_attestation to executing via startRelaying', () => {
      const job = createJob()
      job.startFetchingAttestation()
      job.startRelaying()
      expect(job.status).toBe('executing')
    })

    it('should throw when startRelaying from invalid state', () => {
      const job = createJob()
      job.startFetchingAttestation()
      job.startClaiming()
      expect(() => job.startRelaying()).toThrow('Cannot start relaying from status: claiming')
    })

    it('should throw when executing from invalid state', () => {
      const job = createJob()
      expect(() => job.startExecuting()).toThrow()
    })

    it('should throw when completing from invalid state', () => {
      const job = createJob()
      expect(() => job.complete(new TransactionHash(validTxHash))).toThrow()
    })
  })

  describe('fail', () => {
    it('should transition to failed from any state', () => {
      const job = createJob()
      job.fail('Test error')

      expect(job.status).toBe('failed')
      expect(job.error).toBe('Test error')
      expect(job.completedAt).toBeInstanceOf(Date)
    })

    it('should fail from fetching_attestation state', () => {
      const job = createJob()
      job.startFetchingAttestation()
      job.fail('Attestation timeout')

      expect(job.status).toBe('failed')
      expect(job.error).toBe('Attestation timeout')
    })
  })

  describe('setAttestation', () => {
    it('should set message, attestation and compute message hash', () => {
      const job = createJob()
      job.setAttestation(validMessage, validAttestation)

      expect(job.message).toBe(validMessage)
      expect(job.attestation).toBe(validAttestation)
      expect(job.messageHash).toBeDefined()
    })
  })

  describe('toJSON', () => {
    it('should serialize job to JSON', () => {
      const job = createJob()
      const json = job.toJSON()

      expect(json.id).toBe(job.id)
      expect(json.transactionHash).toBe(validTxHash)
      expect(json.sourceChainId).toBe(6)
      expect(json.status).toBe('pending')
      expect(json.createdAt).toBeDefined()
      expect(json.destinationChainId).toBeUndefined()
      expect(json.taskType).toBeUndefined()
      expect(json.metadata).toBeUndefined()
    })

    it('should include outbound relay fields in JSON', () => {
      const job = createJob({
        destinationChainId: new ChainId(11155111),
        taskType: 'CCTP_OUTBOUND_RELAY',
        metadata: { withdrawalId: 'wd-123' },
      })
      const json = job.toJSON()

      expect(json.destinationChainId).toBe(11155111)
      expect(json.taskType).toBe('CCTP_OUTBOUND_RELAY')
      expect(json.metadata).toEqual({ withdrawalId: 'wd-123' })
    })

    it('should include execution details when completed', () => {
      const job = createJob()
      job.startFetchingAttestation()
      job.setAttestation(validMessage, validAttestation)
      job.startClaiming()
      job.startExecuting()
      job.complete(new TransactionHash(validTxHash), 1000n)

      const json = job.toJSON()

      expect(json.status).toBe('completed')
      expect(json.executionTxHash).toBe(validTxHash)
      expect(json.operatorFee).toBe('1000')
      expect(json.completedAt).toBeDefined()
    })

    it('should include retry details when pending retry', () => {
      const job = createJob()
      job.startFetchingAttestation()
      job.setAttestation(validMessage, validAttestation)
      job.startClaiming()
      job.startExecuting()
      job.fail('nonce too low')
      job.scheduleRetry(3, 1000)

      const json = job.toJSON()

      expect(json.status).toBe('pending_retry')
      expect(json.retryCount).toBe(1)
      expect(json.nextRetryAt).toBeDefined()
      expect(json.lastError).toBe('nonce too low')
    })
  })

  describe('isRetryableError', () => {
    it('should return true for nonce errors', () => {
      expect(isRetryableError('nonce too low')).toBe(true)
      expect(isRetryableError('nonce has already been used')).toBe(true)
    })

    it('should return true for network errors', () => {
      expect(isRetryableError('network error')).toBe(true)
      expect(isRetryableError('timeout')).toBe(true)
      expect(isRetryableError('connection refused')).toBe(true)
    })

    it('should return false for already executed errors', () => {
      expect(isRetryableError('already executed')).toBe(false)
      expect(isRetryableError('Message already executed on chain')).toBe(false)
    })

    it('should return false for already received errors', () => {
      expect(isRetryableError('already received')).toBe(false)
      expect(isRetryableError('message already received')).toBe(false)
    })

    it('should return false for message already processed', () => {
      expect(isRetryableError('message already processed')).toBe(false)
    })

    it('should return false for authorization errors', () => {
      expect(isRetryableError('Not authorized to execute')).toBe(false)
      expect(isRetryableError('not authorized')).toBe(false)
    })

    it('should return false for insufficient stake', () => {
      expect(isRetryableError('insufficient stake')).toBe(false)
      expect(isRetryableError('Insufficient stake to claim')).toBe(false)
    })
  })

  describe('scheduleRetry', () => {
    it('should schedule a retry with correct state', () => {
      const job = createJob()
      job.startFetchingAttestation()
      job.setAttestation(validMessage, validAttestation)
      job.startClaiming()
      job.startExecuting()
      job.fail('nonce too low')

      const result = job.scheduleRetry(3, 1000)

      expect(result).toBe(true)
      expect(job.status).toBe('pending_retry')
      expect(job.retryCount).toBe(1)
      expect(job.nextRetryAt).toBeDefined()
      expect(job.lastError).toBe('nonce too low')
      expect(job.error).toBeUndefined()
    })

    it('should increment retry count on each schedule', () => {
      const job = createJob()
      job.startFetchingAttestation()
      job.setAttestation(validMessage, validAttestation)
      job.startClaiming()
      job.startExecuting()
      job.fail('error 1')
      job.scheduleRetry(3, 1000)

      expect(job.retryCount).toBe(1)

      // Simulate retry attempt that fails again
      job.startRetry()
      job.startExecuting()
      job.fail('error 2')
      job.scheduleRetry(3, 1000)

      expect(job.retryCount).toBe(2)
      expect(job.lastError).toBe('error 2')
    })

    it('should return false when max retries exceeded', () => {
      const job = createJob()
      job.startFetchingAttestation()
      job.setAttestation(validMessage, validAttestation)
      job.startClaiming()
      job.startExecuting()
      job.fail('error')

      // Exhaust all retries
      job.scheduleRetry(2, 1000)
      job.startRetry()
      job.startExecuting()
      job.fail('error')

      job.scheduleRetry(2, 1000)
      job.startRetry()
      job.startExecuting()
      job.fail('error')

      const result = job.scheduleRetry(2, 1000)

      expect(result).toBe(false)
      expect(job.retryCount).toBe(2)
    })

    it('should calculate exponential backoff delays', () => {
      const job = createJob()
      job.startFetchingAttestation()
      job.setAttestation(validMessage, validAttestation)
      job.startClaiming()
      job.startExecuting()
      job.fail('error')

      const beforeSchedule = Date.now()
      job.scheduleRetry(3, 1000)
      const firstRetryAt = job.nextRetryAt!.getTime()

      // First retry should be ~1 second delay
      expect(firstRetryAt - beforeSchedule).toBeGreaterThanOrEqual(900)
      expect(firstRetryAt - beforeSchedule).toBeLessThanOrEqual(1100)

      job.startRetry()
      job.startExecuting()
      job.fail('error')

      const beforeSecond = Date.now()
      job.scheduleRetry(3, 1000)
      const secondRetryAt = job.nextRetryAt!.getTime()

      // Second retry should be ~2 seconds delay
      expect(secondRetryAt - beforeSecond).toBeGreaterThanOrEqual(1900)
      expect(secondRetryAt - beforeSecond).toBeLessThanOrEqual(2100)
    })
  })

  describe('startRetry', () => {
    it('should transition from pending_retry to claiming', () => {
      const job = createJob()
      job.startFetchingAttestation()
      job.setAttestation(validMessage, validAttestation)
      job.startClaiming()
      job.startExecuting()
      job.fail('error')
      job.scheduleRetry(3, 1000)

      job.startRetry()

      expect(job.status).toBe('claiming')
      expect(job.nextRetryAt).toBeUndefined()
    })

    it('should throw when not in pending_retry state', () => {
      const job = createJob()
      expect(() => job.startRetry()).toThrow('Cannot start retry from status: pending')
    })

    it('should allow full retry flow after startRetry', () => {
      const job = createJob()
      job.startFetchingAttestation()
      job.setAttestation(validMessage, validAttestation)
      job.startClaiming()
      job.startExecuting()
      job.fail('error')
      job.scheduleRetry(3, 1000)

      job.startRetry()
      job.startExecuting()
      job.complete(new TransactionHash(validTxHash), 500n)

      expect(job.status).toBe('completed')
      expect(job.retryCount).toBe(1)
      expect(job.operatorFee).toBe(500n)
    })
  })

  describe('isReadyForRetry', () => {
    it('should return false when not in pending_retry state', () => {
      const job = createJob()
      expect(job.isReadyForRetry).toBe(false)
    })

    it('should return false when nextRetryAt is in the future', () => {
      const job = createJob()
      job.startFetchingAttestation()
      job.setAttestation(validMessage, validAttestation)
      job.startClaiming()
      job.startExecuting()
      job.fail('error')
      job.scheduleRetry(3, 10000) // 10 seconds in future

      expect(job.isReadyForRetry).toBe(false)
    })

    it('should return true when nextRetryAt has passed', async () => {
      const job = createJob()
      job.startFetchingAttestation()
      job.setAttestation(validMessage, validAttestation)
      job.startClaiming()
      job.startExecuting()
      job.fail('error')
      job.scheduleRetry(3, 1) // 1ms delay

      // Wait for retry time to pass
      await new Promise((resolve) => setTimeout(resolve, 10))

      expect(job.isReadyForRetry).toBe(true)
    })
  })
})
