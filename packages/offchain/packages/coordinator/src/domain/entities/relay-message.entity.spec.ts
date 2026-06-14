import { RelayMessage } from './relay-message.entity'
import { ChainId } from '../value-objects/chain-id.value-object'
import { TransactionHash } from '../value-objects/transaction-hash.value-object'

describe('RelayMessage', () => {
  const validTxHash = '0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef'

  const createMessage = (
    overrides?: Partial<{
      message: string
      attestation: string
      destinationChainId: ChainId
      taskType: string
      metadata: Record<string, string>
    }>,
  ) => {
    return new RelayMessage({
      transactionHash: new TransactionHash(validTxHash),
      sourceChainId: new ChainId(84532),
      ...overrides,
    })
  }

  describe('constructor', () => {
    it('should create a relay message with required fields', () => {
      const message = createMessage()

      expect(message.id).toBeDefined()
      expect(message.transactionHash.value).toBe(validTxHash)
      expect(message.sourceChainId.value).toBe(84532)
      expect(message.createdAt).toBeInstanceOf(Date)
    })

    it('should create a relay message with optional fields', () => {
      const message = createMessage({
        message: '0xmessage',
        attestation: '0xattestation',
      })

      expect(message.message).toBe('0xmessage')
      expect(message.attestation).toBe('0xattestation')
    })

    it('should create a relay message with outbound relay fields', () => {
      const message = createMessage({
        destinationChainId: new ChainId(11155111),
        taskType: 'CCTP_OUTBOUND_RELAY',
        metadata: { withdrawalId: 'wd-123', callbackUrl: 'https://api.example.com/callback' },
      })

      expect(message.destinationChainId?.value).toBe(11155111)
      expect(message.taskType).toBe('CCTP_OUTBOUND_RELAY')
      expect(message.metadata).toEqual({
        withdrawalId: 'wd-123',
        callbackUrl: 'https://api.example.com/callback',
      })
    })

    it('should leave outbound relay fields undefined when not provided', () => {
      const message = createMessage()

      expect(message.destinationChainId).toBeUndefined()
      expect(message.taskType).toBeUndefined()
      expect(message.metadata).toBeUndefined()
    })

    it('should generate unique IDs', () => {
      const message1 = createMessage()
      const message2 = createMessage()

      expect(message1.id).not.toBe(message2.id)
    })
  })

  describe('isAssigned', () => {
    it('should return false for unassigned message', () => {
      const message = createMessage()
      expect(message.isAssigned).toBe(false)
    })

    it('should return true after assignment', () => {
      const message = createMessage()
      message.assignTo('0xoperator')
      expect(message.isAssigned).toBe(true)
    })
  })

  describe('assignTo', () => {
    it('should assign an operator to the message', () => {
      const message = createMessage()
      const operatorAddress = '0x1234567890123456789012345678901234567890'

      message.assignTo(operatorAddress)

      expect(message.assignedOperator).toBe(operatorAddress)
      expect(message.assignedAt).toBeInstanceOf(Date)
    })
  })

  describe('updateAttestation', () => {
    it('should update message and attestation', () => {
      const message = createMessage()

      message.updateAttestation('0xnewmessage', '0xnewattestation')

      expect(message.message).toBe('0xnewmessage')
      expect(message.attestation).toBe('0xnewattestation')
    })
  })

  describe('toJSON', () => {
    it('should serialize to JSON correctly', () => {
      const message = createMessage({
        message: '0xmessage',
        attestation: '0xattestation',
      })

      const json = message.toJSON()

      expect(json.id).toBe(message.id)
      expect(json.transactionHash).toBe(validTxHash)
      expect(json.sourceChainId).toBe(84532)
      expect(json.message).toBe('0xmessage')
      expect(json.attestation).toBe('0xattestation')
      expect(json.createdAt).toBeDefined()
    })

    it('should include outbound relay fields in JSON', () => {
      const message = createMessage({
        destinationChainId: new ChainId(11155111),
        taskType: 'CCTP_OUTBOUND_RELAY',
        metadata: { withdrawalId: 'wd-123' },
      })

      const json = message.toJSON()

      expect(json.destinationChainId).toBe(11155111)
      expect(json.taskType).toBe('CCTP_OUTBOUND_RELAY')
      expect(json.metadata).toEqual({ withdrawalId: 'wd-123' })
    })

    it('should omit outbound relay fields when not set', () => {
      const message = createMessage()
      const json = message.toJSON()

      expect(json.destinationChainId).toBeUndefined()
      expect(json.taskType).toBeUndefined()
      expect(json.metadata).toBeUndefined()
    })

    it('should include assignment info when assigned', () => {
      const message = createMessage()
      message.assignTo('0xoperator')

      const json = message.toJSON()

      expect(json.assignedOperator).toBe('0xoperator')
      expect(json.assignedAt).toBeDefined()
    })
  })
})
