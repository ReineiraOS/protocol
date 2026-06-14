import { Injectable } from '@nestjs/common'
import { RelayMessage } from '../../domain/entities/relay-message.entity'

// TODO: Replace with persistent storage (PostgreSQL/Redis) for message durability
@Injectable()
export class MessageRepository {
  private readonly messages = new Map<string, RelayMessage>()

  save(message: RelayMessage): void {
    this.messages.set(message.id, message)
  }

  findById(id: string): RelayMessage | undefined {
    return this.messages.get(id)
  }

  findByTransactionHash(txHash: string): RelayMessage | undefined {
    const normalizedHash = txHash.toLowerCase()
    for (const message of this.messages.values()) {
      if (message.transactionHash.value === normalizedHash) {
        return message
      }
    }
    return undefined
  }

  findPending(): RelayMessage[] {
    return Array.from(this.messages.values()).filter((msg) => !msg.isAssigned)
  }

  findAll(): RelayMessage[] {
    return Array.from(this.messages.values())
  }

  delete(id: string): boolean {
    return this.messages.delete(id)
  }

  clear(): void {
    this.messages.clear()
  }

  count(): number {
    return this.messages.size
  }
}
