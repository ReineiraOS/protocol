import { Injectable, Logger } from '@nestjs/common'
import { RelayJob } from '../../domain/entities/relay-job.entity'

@Injectable()
export class RelayJobRepository {
  private readonly logger = new Logger(RelayJobRepository.name)
  private readonly jobs = new Map<string, RelayJob>()

  save(job: RelayJob): void {
    this.jobs.set(job.id, job)
    this.logger.debug(`Saved job ${job.id}`)
  }

  findById(id: string): RelayJob | undefined {
    return this.jobs.get(id)
  }

  findByTransactionHash(txHash: string): RelayJob | undefined {
    const normalizedHash = txHash.toLowerCase()
    for (const job of this.jobs.values()) {
      if (job.transactionHash.value === normalizedHash) {
        return job
      }
    }
    return undefined
  }

  findPending(): RelayJob[] {
    return Array.from(this.jobs.values()).filter(
      (job) => job.status === 'pending' || job.status === 'fetching_attestation',
    )
  }

  findActive(): RelayJob[] {
    return Array.from(this.jobs.values()).filter(
      (job) =>
        job.status !== 'completed' && job.status !== 'failed' && job.status !== 'pending_retry',
    )
  }

  findReadyForRetry(): RelayJob[] {
    return Array.from(this.jobs.values()).filter((job) => job.isReadyForRetry)
  }

  findPendingRetry(): RelayJob[] {
    return Array.from(this.jobs.values()).filter((job) => job.status === 'pending_retry')
  }

  findCompleted(): RelayJob[] {
    return Array.from(this.jobs.values()).filter((job) => job.status === 'completed')
  }

  findFailed(): RelayJob[] {
    return Array.from(this.jobs.values()).filter((job) => job.status === 'failed')
  }

  findAll(): RelayJob[] {
    return Array.from(this.jobs.values())
  }

  delete(id: string): boolean {
    return this.jobs.delete(id)
  }

  clear(): void {
    this.jobs.clear()
  }

  count(): number {
    return this.jobs.size
  }

  countByStatus(): Record<string, number> {
    const counts: Record<string, number> = {}
    for (const job of this.jobs.values()) {
      counts[job.status] = (counts[job.status] || 0) + 1
    }
    return counts
  }
}
