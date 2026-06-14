import { MessageRepository } from './message.repository'
import { RelayMessage } from '../../domain/entities/relay-message.entity'
import { ChainId } from '../../domain/value-objects/chain-id.value-object'
import { TransactionHash } from '../../domain/value-objects/transaction-hash.value-object'

describe('MessageRepository', () => {
  let repository: MessageRepository

  const validTxHash = '0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef'
  const validTxHash2 = '0xfedcba0987654321fedcba0987654321fedcba0987654321fedcba0987654321'

  const createMessage = (txHash = validTxHash) => {
    return new RelayMessage({
      transactionHash: new TransactionHash(txHash),
      sourceChainId: new ChainId(84532),
    })
  }

  beforeEach(() => {
    repository = new MessageRepository()
  })

  describe('save', () => {
    it('should save a message', () => {
      const message = createMessage()
      repository.save(message)

      expect(repository.count()).toBe(1)
    })
  })

  describe('findById', () => {
    it('should find message by ID', () => {
      const message = createMessage()
      repository.save(message)

      const found = repository.findById(message.id)

      expect(found).toBeDefined()
      expect(found?.id).toBe(message.id)
    })

    it('should return undefined for non-existent ID', () => {
      const found = repository.findById('non-existent')
      expect(found).toBeUndefined()
    })
  })

  describe('findByTransactionHash', () => {
    it('should find message by transaction hash', () => {
      const message = createMessage()
      repository.save(message)

      const found = repository.findByTransactionHash(validTxHash)

      expect(found).toBeDefined()
      expect(found?.transactionHash.value).toBe(validTxHash)
    })

    it('should find message by uppercase transaction hash', () => {
      const message = createMessage()
      repository.save(message)

      const found = repository.findByTransactionHash(validTxHash.toUpperCase())

      expect(found).toBeDefined()
    })

    it('should return undefined for non-existent hash', () => {
      const found = repository.findByTransactionHash(validTxHash2)
      expect(found).toBeUndefined()
    })
  })

  describe('findPending', () => {
    it('should return only unassigned messages', () => {
      const message1 = createMessage(validTxHash)
      const message2 = createMessage(validTxHash2)

      message1.assignTo('0xoperator')

      repository.save(message1)
      repository.save(message2)

      const pending = repository.findPending()

      expect(pending.length).toBe(1)
      expect(pending[0].id).toBe(message2.id)
    })

    it('should return empty array when all assigned', () => {
      const message = createMessage()
      message.assignTo('0xoperator')
      repository.save(message)

      const pending = repository.findPending()

      expect(pending.length).toBe(0)
    })
  })

  describe('findAll', () => {
    it('should return all messages', () => {
      const message1 = createMessage(validTxHash)
      const message2 = createMessage(validTxHash2)

      repository.save(message1)
      repository.save(message2)

      const all = repository.findAll()

      expect(all.length).toBe(2)
    })
  })

  describe('delete', () => {
    it('should delete a message', () => {
      const message = createMessage()
      repository.save(message)

      const deleted = repository.delete(message.id)

      expect(deleted).toBe(true)
      expect(repository.count()).toBe(0)
    })

    it('should return false for non-existent message', () => {
      const deleted = repository.delete('non-existent')
      expect(deleted).toBe(false)
    })
  })

  describe('clear', () => {
    it('should remove all messages', () => {
      repository.save(createMessage(validTxHash))
      repository.save(createMessage(validTxHash2))

      repository.clear()

      expect(repository.count()).toBe(0)
    })
  })

  describe('count', () => {
    it('should return correct count', () => {
      expect(repository.count()).toBe(0)

      repository.save(createMessage(validTxHash))
      expect(repository.count()).toBe(1)

      repository.save(createMessage(validTxHash2))
      expect(repository.count()).toBe(2)
    })
  })
})
