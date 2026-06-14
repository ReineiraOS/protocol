import { Test, TestingModule } from '@nestjs/testing'
import { CoordinatorService } from './coordinator.service'
import { MessageRepository } from '../../infrastructure/repositories/message.repository'
import { take, toArray } from 'rxjs/operators'

describe('CoordinatorService', () => {
  let service: CoordinatorService
  let repository: MessageRepository

  const validTxHash = '0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef'
  const validTxHash2 = '0xfedcba0987654321fedcba0987654321fedcba0987654321fedcba0987654321'

  beforeEach(async () => {
    const module: TestingModule = await Test.createTestingModule({
      providers: [CoordinatorService, MessageRepository],
    }).compile()

    service = module.get<CoordinatorService>(CoordinatorService)
    repository = module.get<MessageRepository>(MessageRepository)
  })

  afterEach(() => {
    // Clean up any subscribed operators
    const operators = service.getSubscribedOperators()
    operators.forEach((o) => service.unsubscribeOperator(o))
  })

  describe('submitTransaction', () => {
    it('should create and save a relay message', () => {
      const dto = {
        transactionHash: validTxHash,
        sourceChainId: 84532,
      }

      const message = service.submitTransaction(dto)

      expect(message.id).toBeDefined()
      expect(message.transactionHash.value).toBe(validTxHash)
      expect(message.sourceChainId.value).toBe(84532)

      const savedMessage = repository.findById(message.id)
      expect(savedMessage).toBeDefined()
    })

    it('should distribute to subscribed operator', (done) => {
      const operatorAddress = '0xoperator1'

      service.subscribeOperator(operatorAddress).subscribe((event) => {
        expect(event.transactionHash).toBe(validTxHash)
        expect(event.sourceChainId).toBe(84532)
        done()
      })

      service.submitTransaction({
        transactionHash: validTxHash,
        sourceChainId: 84532,
      })
    })

    it('should pass through destinationChainId, taskType, and metadata', (done) => {
      const operatorAddress = '0xoperator1'

      service.subscribeOperator(operatorAddress).subscribe((event) => {
        expect(event.destinationChainId).toBe(11155111)
        expect(event.taskType).toBe('CCTP_OUTBOUND_RELAY')
        expect(event.metadata).toEqual({
          withdrawalId: 'wd-123',
          callbackUrl: 'https://api.example.com/callback',
        })
        done()
      })

      service.submitTransaction({
        transactionHash: validTxHash,
        sourceChainId: 84532,
        destinationChainId: 11155111,
        taskType: 'CCTP_OUTBOUND_RELAY',
        metadata: {
          withdrawalId: 'wd-123',
          callbackUrl: 'https://api.example.com/callback',
        },
      })
    })

    it('should save relay message with outbound relay fields', () => {
      const message = service.submitTransaction({
        transactionHash: validTxHash,
        sourceChainId: 84532,
        destinationChainId: 11155111,
        taskType: 'CCTP_OUTBOUND_RELAY',
        metadata: { withdrawalId: 'wd-123' },
      })

      expect(message.destinationChainId?.value).toBe(11155111)
      expect(message.taskType).toBe('CCTP_OUTBOUND_RELAY')
      expect(message.metadata).toEqual({ withdrawalId: 'wd-123' })

      const savedMessage = repository.findById(message.id)
      expect(savedMessage?.destinationChainId?.value).toBe(11155111)
      expect(savedMessage?.taskType).toBe('CCTP_OUTBOUND_RELAY')
    })
  })

  describe('subscribeOperator', () => {
    it('should add operator to subscribed list', () => {
      const operatorAddress = '0xoperator1'

      service.subscribeOperator(operatorAddress)

      expect(service.getSubscribedOperatorCount()).toBe(1)
      expect(service.getSubscribedOperators()).toContain(operatorAddress.toLowerCase())
    })

    it('should not duplicate operator subscriptions', () => {
      const operatorAddress = '0xoperator1'

      service.subscribeOperator(operatorAddress)
      service.subscribeOperator(operatorAddress)

      expect(service.getSubscribedOperatorCount()).toBe(1)
    })

    it('should normalize addresses to lowercase', () => {
      const operatorAddress = '0xOperator1'

      service.subscribeOperator(operatorAddress)

      expect(service.getSubscribedOperators()).toContain('0xoperator1')
    })
  })

  describe('unsubscribeOperator', () => {
    it('should remove operator from subscribed list', () => {
      const operatorAddress = '0xoperator1'

      service.subscribeOperator(operatorAddress)
      service.unsubscribeOperator(operatorAddress)

      expect(service.getSubscribedOperatorCount()).toBe(0)
    })

    it('should handle unsubscribing non-existent operator', () => {
      expect(() => service.unsubscribeOperator('0xnonexistent')).not.toThrow()
    })
  })

  describe('round-robin distribution', () => {
    it('should distribute messages in round-robin order', (done) => {
      const operator1 = '0xoperator1'
      const operator2 = '0xoperator2'
      const operator1Events: string[] = []
      const operator2Events: string[] = []
      let completedCount = 0

      // Submit 4 transactions
      const hashes = [
        validTxHash,
        validTxHash2,
        '0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        '0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
      ]

      function checkCompletion() {
        completedCount++
        if (completedCount === 2) {
          // Each operator should get 2 transactions
          expect(operator1Events.length).toBe(2)
          expect(operator2Events.length).toBe(2)
          // First operator should get odd transactions (0, 2)
          expect(operator1Events[0]).toBe(hashes[0])
          expect(operator1Events[1]).toBe(hashes[2])
          // Second operator should get even transactions (1, 3)
          expect(operator2Events[0]).toBe(hashes[1])
          expect(operator2Events[1]).toBe(hashes[3])
          done()
        }
      }

      service
        .subscribeOperator(operator1)
        .pipe(take(2), toArray())
        .subscribe((events) => {
          operator1Events.push(...events.map((e) => e.transactionHash))
          checkCompletion()
        })

      service
        .subscribeOperator(operator2)
        .pipe(take(2), toArray())
        .subscribe((events) => {
          operator2Events.push(...events.map((e) => e.transactionHash))
          checkCompletion()
        })

      hashes.forEach((hash) => {
        service.submitTransaction({
          transactionHash: hash,
          sourceChainId: 84532,
        })
      })
    })

    it('should distribute all to single operator when alone', (done) => {
      const operatorAddress = '0xoperator1'
      const receivedHashes: string[] = []

      service
        .subscribeOperator(operatorAddress)
        .pipe(take(2), toArray())
        .subscribe((events) => {
          receivedHashes.push(...events.map((e) => e.transactionHash))
          expect(receivedHashes.length).toBe(2)
          expect(receivedHashes[0]).toBe(validTxHash)
          expect(receivedHashes[1]).toBe(validTxHash2)
          done()
        })

      service.submitTransaction({
        transactionHash: validTxHash,
        sourceChainId: 84532,
      })

      service.submitTransaction({
        transactionHash: validTxHash2,
        sourceChainId: 84532,
      })
    })
  })

  describe('getMessage', () => {
    it('should return message by ID', () => {
      const dto = {
        transactionHash: validTxHash,
        sourceChainId: 84532,
      }

      const createdMessage = service.submitTransaction(dto)
      const foundMessage = service.getMessage(createdMessage.id)

      expect(foundMessage).toBeDefined()
      expect(foundMessage?.id).toBe(createdMessage.id)
    })

    it('should return undefined for non-existent ID', () => {
      const message = service.getMessage('non-existent-id')
      expect(message).toBeUndefined()
    })
  })
})
