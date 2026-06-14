import { RelayJobRepository } from './relay-job.repository'
import { RelayJob } from '../../domain/entities/relay-job.entity'
import { TransactionHash } from '../../domain/value-objects/transaction-hash.value-object'
import { ChainId } from '../../domain/value-objects/chain-id.value-object'

describe('RelayJobRepository', () => {
  let repository: RelayJobRepository

  const validTxHash = '0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef'
  const validMessage = '0x000000010000000600000000abcdef1234567890abcdef1234567890'
  const validAttestation = '0xabcdef1234567890abcdef1234567890'

  const createJob = () =>
    new RelayJob({
      transactionHash: new TransactionHash(validTxHash),
      sourceChainId: new ChainId(6),
    })

  beforeEach(() => {
    repository = new RelayJobRepository()
  })

  describe('save', () => {
    it('should save a job', () => {
      const job = createJob()
      repository.save(job)

      expect(repository.count()).toBe(1)
    })
  })

  describe('findById', () => {
    it('should find job by ID', () => {
      const job = createJob()
      repository.save(job)

      const found = repository.findById(job.id)
      expect(found).toBe(job)
    })

    it('should return undefined for non-existent ID', () => {
      const found = repository.findById('non-existent')
      expect(found).toBeUndefined()
    })
  })

  describe('findByTransactionHash', () => {
    it('should find job by transaction hash', () => {
      const job = createJob()
      repository.save(job)

      const found = repository.findByTransactionHash(validTxHash)
      expect(found).toBe(job)
    })

    it('should find job by uppercase transaction hash', () => {
      const job = createJob()
      repository.save(job)

      const found = repository.findByTransactionHash(validTxHash.toUpperCase())
      expect(found).toBe(job)
    })

    it('should return undefined for non-existent hash', () => {
      const found = repository.findByTransactionHash(
        '0xfedcba0987654321fedcba0987654321fedcba0987654321fedcba0987654321',
      )
      expect(found).toBeUndefined()
    })
  })

  describe('findPending', () => {
    it('should find pending jobs', () => {
      const job1 = createJob()
      const job2 = createJob()
      job2.startFetchingAttestation()

      repository.save(job1)
      repository.save(job2)

      const pending = repository.findPending()
      expect(pending.length).toBe(2)
    })

    it('should not include jobs in other states', () => {
      const job = createJob()
      job.fail('error')
      repository.save(job)

      const pending = repository.findPending()
      expect(pending.length).toBe(0)
    })
  })

  describe('findCompleted', () => {
    it('should find completed jobs', () => {
      const job = createJob()
      job.startFetchingAttestation()
      job.startClaiming()
      job.startExecuting()
      job.complete(new TransactionHash(validTxHash))

      repository.save(job)

      const completed = repository.findCompleted()
      expect(completed.length).toBe(1)
      expect(completed[0]).toBe(job)
    })
  })

  describe('findFailed', () => {
    it('should find failed jobs', () => {
      const job = createJob()
      job.fail('error')
      repository.save(job)

      const failed = repository.findFailed()
      expect(failed.length).toBe(1)
      expect(failed[0]).toBe(job)
    })
  })

  describe('findAll', () => {
    it('should return all jobs', () => {
      const job1 = createJob()
      const job2 = createJob()

      repository.save(job1)
      repository.save(job2)

      expect(repository.findAll().length).toBe(2)
    })
  })

  describe('delete', () => {
    it('should delete a job', () => {
      const job = createJob()
      repository.save(job)

      const result = repository.delete(job.id)
      expect(result).toBe(true)
      expect(repository.count()).toBe(0)
    })

    it('should return false for non-existent job', () => {
      const result = repository.delete('non-existent')
      expect(result).toBe(false)
    })
  })

  describe('clear', () => {
    it('should clear all jobs', () => {
      repository.save(createJob())
      repository.save(createJob())

      repository.clear()
      expect(repository.count()).toBe(0)
    })
  })

  describe('countByStatus', () => {
    it('should count jobs by status', () => {
      const job1 = createJob()
      const job2 = createJob()
      job2.fail('error')
      const job3 = createJob()
      job3.startFetchingAttestation()
      job3.startClaiming()
      job3.startExecuting()
      job3.complete(new TransactionHash(validTxHash))

      repository.save(job1)
      repository.save(job2)
      repository.save(job3)

      const counts = repository.countByStatus()
      expect(counts['pending']).toBe(1)
      expect(counts['failed']).toBe(1)
      expect(counts['completed']).toBe(1)
    })

    it('should count pending_retry jobs', () => {
      const job = createJob()
      job.startFetchingAttestation()
      job.setAttestation(validMessage, validAttestation)
      job.startClaiming()
      job.startExecuting()
      job.fail('nonce error')
      job.scheduleRetry(3, 1000)

      repository.save(job)

      const counts = repository.countByStatus()
      expect(counts['pending_retry']).toBe(1)
    })
  })

  describe('findPendingRetry', () => {
    it('should find jobs in pending_retry state', () => {
      const job1 = createJob()
      job1.startFetchingAttestation()
      job1.setAttestation(validMessage, validAttestation)
      job1.startClaiming()
      job1.startExecuting()
      job1.fail('error')
      job1.scheduleRetry(3, 1000)

      const job2 = createJob()
      job2.fail('permanent error')

      repository.save(job1)
      repository.save(job2)

      const pendingRetry = repository.findPendingRetry()
      expect(pendingRetry.length).toBe(1)
      expect(pendingRetry[0]).toBe(job1)
    })

    it('should return empty array when no jobs pending retry', () => {
      const job = createJob()
      repository.save(job)

      const pendingRetry = repository.findPendingRetry()
      expect(pendingRetry.length).toBe(0)
    })
  })

  describe('findReadyForRetry', () => {
    it('should find jobs ready for retry (past nextRetryAt)', async () => {
      const job = createJob()
      job.startFetchingAttestation()
      job.setAttestation(validMessage, validAttestation)
      job.startClaiming()
      job.startExecuting()
      job.fail('error')
      job.scheduleRetry(3, 1) // 1ms delay

      repository.save(job)

      // Wait for retry time to pass
      await new Promise((resolve) => setTimeout(resolve, 10))

      const ready = repository.findReadyForRetry()
      expect(ready.length).toBe(1)
      expect(ready[0]).toBe(job)
    })

    it('should not find jobs with future nextRetryAt', () => {
      const job = createJob()
      job.startFetchingAttestation()
      job.setAttestation(validMessage, validAttestation)
      job.startClaiming()
      job.startExecuting()
      job.fail('error')
      job.scheduleRetry(3, 10000) // 10 seconds in future

      repository.save(job)

      const ready = repository.findReadyForRetry()
      expect(ready.length).toBe(0)
    })

    it('should not find jobs in other states', () => {
      const job1 = createJob()
      const job2 = createJob()
      job2.fail('error')

      repository.save(job1)
      repository.save(job2)

      const ready = repository.findReadyForRetry()
      expect(ready.length).toBe(0)
    })
  })

  describe('findActive', () => {
    it('should not include pending_retry jobs', () => {
      const job1 = createJob() // pending - should be included
      const job2 = createJob()
      job2.startFetchingAttestation()
      job2.setAttestation(validMessage, validAttestation)
      job2.startClaiming()
      job2.startExecuting()
      job2.fail('error')
      job2.scheduleRetry(3, 1000) // pending_retry - should NOT be included

      repository.save(job1)
      repository.save(job2)

      const active = repository.findActive()
      expect(active.length).toBe(1)
      expect(active[0]).toBe(job1)
    })

    it('should not include completed or failed jobs', () => {
      const job1 = createJob()
      job1.fail('error')

      const job2 = createJob()
      job2.startFetchingAttestation()
      job2.startClaiming()
      job2.startExecuting()
      job2.complete(new TransactionHash(validTxHash))

      repository.save(job1)
      repository.save(job2)

      const active = repository.findActive()
      expect(active.length).toBe(0)
    })
  })
})
