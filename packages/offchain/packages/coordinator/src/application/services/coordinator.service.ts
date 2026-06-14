import { Injectable, Logger } from '@nestjs/common'
import { Subject, Observable } from 'rxjs'
import { RelayMessage } from '../../domain/entities/relay-message.entity'
import { ChainId } from '../../domain/value-objects/chain-id.value-object'
import { TransactionHash } from '../../domain/value-objects/transaction-hash.value-object'
import { MessageRepository } from '../../infrastructure/repositories/message.repository'
import { SubmitTransactionDto } from '../dto/submit-transaction.dto'
import { RelayEventDto } from '../dto/relay-event.dto'

export interface OperatorSubscription {
  operatorAddress: string
  subscribedAt: Date
}

@Injectable()
export class CoordinatorService {
  private readonly logger = new Logger(CoordinatorService.name)
  private readonly operatorStreams = new Map<string, Subject<RelayEventDto>>()
  private subscribedOperators: string[] = []
  private roundRobinIndex = 0

  constructor(private readonly messageRepository: MessageRepository) {}

  submitTransaction(dto: SubmitTransactionDto): RelayMessage {
    this.logger.log(
      `Received CCTP bridge transaction: ${dto.transactionHash} from chain ${dto.sourceChainId}`,
    )

    const message = new RelayMessage({
      transactionHash: new TransactionHash(dto.transactionHash),
      sourceChainId: new ChainId(dto.sourceChainId),
      destinationChainId:
        dto.destinationChainId !== undefined ? new ChainId(dto.destinationChainId) : undefined,
      taskType: dto.taskType,
      metadata: dto.metadata,
    })

    this.messageRepository.save(message)
    this.distributeToNextOperator(message)

    return message
  }

  subscribeOperator(operatorAddress: string): Observable<RelayEventDto> {
    const normalizedAddress = operatorAddress.toLowerCase()
    this.logger.log(`Operator subscribing: ${normalizedAddress}`)

    if (!this.operatorStreams.has(normalizedAddress)) {
      this.operatorStreams.set(normalizedAddress, new Subject<RelayEventDto>())
      this.subscribedOperators.push(normalizedAddress)
      this.logger.log(
        `New operator registered. Total operators: ${this.subscribedOperators.length}`,
      )
    }

    return this.operatorStreams.get(normalizedAddress)!.asObservable()
  }

  unsubscribeOperator(operatorAddress: string): void {
    const normalizedAddress = operatorAddress.toLowerCase()
    this.logger.log(`Operator unsubscribing: ${normalizedAddress}`)

    const subject = this.operatorStreams.get(normalizedAddress)
    if (subject) {
      subject.complete()
      this.operatorStreams.delete(normalizedAddress)
      this.subscribedOperators = this.subscribedOperators.filter(
        (addr) => addr !== normalizedAddress,
      )

      if (this.roundRobinIndex >= this.subscribedOperators.length) {
        this.roundRobinIndex = 0
      }

      this.logger.log(`Operator removed. Total operators: ${this.subscribedOperators.length}`)
    }
  }

  getSubscribedOperatorCount(): number {
    return this.subscribedOperators.length
  }

  getSubscribedOperators(): string[] {
    return [...this.subscribedOperators]
  }

  private distributeToNextOperator(message: RelayMessage): void {
    if (this.subscribedOperators.length === 0) {
      this.logger.warn('No operators subscribed. Message queued but not distributed.')
      return
    }

    const selectedOperator = this.subscribedOperators[this.roundRobinIndex]
    this.roundRobinIndex = (this.roundRobinIndex + 1) % this.subscribedOperators.length

    message.assignTo(selectedOperator)

    const subject = this.operatorStreams.get(selectedOperator)
    if (subject) {
      const event: RelayEventDto = {
        id: message.id,
        transactionHash: message.transactionHash.value,
        sourceChainId: message.sourceChainId.value,
        destinationChainId: message.destinationChainId?.value,
        taskType: message.taskType,
        message: message.message,
        attestation: message.attestation,
        metadata: message.metadata,
        createdAt: message.createdAt.toISOString(),
      }

      this.logger.log(`Distributing CCTP relay task ${message.id} to operator ${selectedOperator}`)
      subject.next(event)
    }
  }

  getMessage(id: string): RelayMessage | undefined {
    return this.messageRepository.findById(id)
  }

  getPendingMessages(): RelayMessage[] {
    return this.messageRepository.findPending()
  }
}
