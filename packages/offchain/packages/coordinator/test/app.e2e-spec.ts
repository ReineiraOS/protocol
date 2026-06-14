import { Test, TestingModule } from '@nestjs/testing'
import { INestApplication, ValidationPipe } from '@nestjs/common'
import request from 'supertest'
import { AppModule } from '../src/app.module'
import { CoordinatorService } from '../src/application/services/coordinator.service'
import { take, toArray, firstValueFrom } from 'rxjs'

interface RelayEvent {
  id: string
  transactionHash: string
  sourceChainId: number
  createdAt: string
}

describe('Coordinator (e2e)', () => {
  let app: INestApplication
  let coordinatorService: CoordinatorService

  const validTxHash = '0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef'
  const validTxHash2 = '0xfedcba0987654321fedcba0987654321fedcba0987654321fedcba0987654321'

  beforeAll(async () => {
    const moduleFixture: TestingModule = await Test.createTestingModule({
      imports: [AppModule],
    }).compile()

    app = moduleFixture.createNestApplication()
    app.useGlobalPipes(
      new ValidationPipe({
        whitelist: true,
        transform: true,
        forbidNonWhitelisted: true,
      }),
    )
    coordinatorService = moduleFixture.get<CoordinatorService>(CoordinatorService)
    await app.init()
  })

  afterAll(async () => {
    await app.close()
  })

  describe('Transaction Submission (POST /bridges/cctp/transactions)', () => {
    afterEach(() => {
      // Clean up subscribed operators
      const operators = coordinatorService.getSubscribedOperators()
      operators.forEach((o) => coordinatorService.unsubscribeOperator(o))
    })

    it('should accept a valid transaction', async () => {
      const response = await request(app.getHttpServer())
        .post('/bridges/cctp/transactions')
        .send({
          transactionHash: validTxHash,
          sourceChainId: 84532,
        })
        .expect(202)

      expect(response.body).toHaveProperty('id')
      expect(response.body.status).toBe('queued')
      expect(response.body.message).toBe('CCTP transaction queued for relay')
    })

    it('should reject invalid transaction hash', async () => {
      await request(app.getHttpServer())
        .post('/bridges/cctp/transactions')
        .send({
          transactionHash: 'invalid-hash',
          sourceChainId: 84532,
        })
        .expect(400)
    })

    it('should reject transaction hash without 0x prefix', async () => {
      await request(app.getHttpServer())
        .post('/bridges/cctp/transactions')
        .send({
          transactionHash: '1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef',
          sourceChainId: 84532,
        })
        .expect(400)
    })

    it('should reject short transaction hash', async () => {
      await request(app.getHttpServer())
        .post('/bridges/cctp/transactions')
        .send({
          transactionHash: '0x1234',
          sourceChainId: 84532,
        })
        .expect(400)
    })

    it('should reject missing transaction hash', async () => {
      await request(app.getHttpServer())
        .post('/bridges/cctp/transactions')
        .send({
          sourceChainId: 84532,
        })
        .expect(400)
    })

    it('should reject invalid chain ID', async () => {
      await request(app.getHttpServer())
        .post('/bridges/cctp/transactions')
        .send({
          transactionHash: validTxHash,
          sourceChainId: -1,
        })
        .expect(400)
    })

    it('should reject missing chain ID', async () => {
      await request(app.getHttpServer())
        .post('/bridges/cctp/transactions')
        .send({
          transactionHash: validTxHash,
        })
        .expect(400)
    })

    it('should reject non-numeric chain ID', async () => {
      await request(app.getHttpServer())
        .post('/bridges/cctp/transactions')
        .send({
          transactionHash: validTxHash,
          sourceChainId: 'not-a-number',
        })
        .expect(400)
    })
  })

  describe('Operator Stats (GET /operators/stats)', () => {
    afterEach(() => {
      // Clean up subscribed operators
      const operators = coordinatorService.getSubscribedOperators()
      operators.forEach((o) => coordinatorService.unsubscribeOperator(o))
    })

    it('should return operator statistics with no operators', async () => {
      const response = await request(app.getHttpServer()).get('/operators/stats').expect(200)

      expect(response.body).toHaveProperty('subscribedCount', 0)
      expect(response.body).toHaveProperty('operators')
      expect(response.body.operators).toEqual([])
    })

    it('should return operator statistics with subscribed operators', async () => {
      // Subscribe operators via service
      coordinatorService.subscribeOperator('0xoperator1')
      coordinatorService.subscribeOperator('0xoperator2')

      const response = await request(app.getHttpServer()).get('/operators/stats').expect(200)

      expect(response.body.subscribedCount).toBe(2)
      expect(response.body.operators).toContain('0xoperator1')
      expect(response.body.operators).toContain('0xoperator2')
    })
  })

  describe('Full Flow: Transaction Distribution via Service', () => {
    it('should distribute transaction to subscribed operator', async () => {
      const operatorAddress = '0xoperator_single'

      // Subscribe operator and get first event
      const eventPromise = firstValueFrom(
        coordinatorService.subscribeOperator(operatorAddress).pipe(take(1)),
      )

      // Submit transaction via HTTP
      await request(app.getHttpServer())
        .post('/bridges/cctp/transactions')
        .send({
          transactionHash: validTxHash2,
          sourceChainId: 84532,
        })
        .expect(202)

      // Wait for event
      const event = (await eventPromise) as RelayEvent
      expect(event).toHaveProperty('id')
      expect(event.transactionHash).toBe(validTxHash2)
      expect(event.sourceChainId).toBe(84532)
      expect(event).toHaveProperty('createdAt')

      // Cleanup
      coordinatorService.unsubscribeOperator(operatorAddress)
    })

    it('should distribute transactions in round-robin to multiple operators', async () => {
      const operator1 = '0xoperator_rr_1'
      const operator2 = '0xoperator_rr_2'

      const txHashes = [
        '0x1111111111111111111111111111111111111111111111111111111111111111',
        '0x2222222222222222222222222222222222222222222222222222222222222222',
        '0x3333333333333333333333333333333333333333333333333333333333333333',
        '0x4444444444444444444444444444444444444444444444444444444444444444',
      ]

      // Subscribe operators and collect events
      const operator1EventsPromise = firstValueFrom(
        coordinatorService.subscribeOperator(operator1).pipe(take(2), toArray()),
      )

      const operator2EventsPromise = firstValueFrom(
        coordinatorService.subscribeOperator(operator2).pipe(take(2), toArray()),
      )

      // Submit transactions via HTTP sequentially to ensure order
      for (const hash of txHashes) {
        await request(app.getHttpServer()).post('/bridges/cctp/transactions').send({
          transactionHash: hash,
          sourceChainId: 84532,
        })
      }

      // Wait for events
      const operator1Events = (await operator1EventsPromise) as RelayEvent[]
      const operator2Events = (await operator2EventsPromise) as RelayEvent[]

      // Verify distribution
      const o1Hashes = operator1Events.map((e) => e.transactionHash)
      const o2Hashes = operator2Events.map((e) => e.transactionHash)

      expect(o1Hashes.length).toBe(2)
      expect(o2Hashes.length).toBe(2)

      // First operator should get transactions 0 and 2
      expect(o1Hashes).toContain(txHashes[0])
      expect(o1Hashes).toContain(txHashes[2])

      // Second operator should get transactions 1 and 3
      expect(o2Hashes).toContain(txHashes[1])
      expect(o2Hashes).toContain(txHashes[3])

      // Cleanup
      coordinatorService.unsubscribeOperator(operator1)
      coordinatorService.unsubscribeOperator(operator2)
    })

    it('should handle single operator receiving all transactions', async () => {
      const operatorAddress = '0xsingleoperator'

      const txHashes = [
        '0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        '0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
      ]

      // Subscribe and collect events
      const eventsPromise = firstValueFrom(
        coordinatorService.subscribeOperator(operatorAddress).pipe(take(2), toArray()),
      )

      // Submit transactions
      for (const hash of txHashes) {
        await request(app.getHttpServer()).post('/bridges/cctp/transactions').send({
          transactionHash: hash,
          sourceChainId: 84532,
        })
      }

      const events = (await eventsPromise) as RelayEvent[]

      expect(events.length).toBe(2)
      expect(events.map((e) => e.transactionHash)).toContain(txHashes[0])
      expect(events.map((e) => e.transactionHash)).toContain(txHashes[1])

      // Cleanup
      coordinatorService.unsubscribeOperator(operatorAddress)
    })
  })

  describe('Error Handling', () => {
    it('should handle empty request body', async () => {
      await request(app.getHttpServer()).post('/bridges/cctp/transactions').send({}).expect(400)
    })

    it('should handle malformed JSON', async () => {
      await request(app.getHttpServer())
        .post('/bridges/cctp/transactions')
        .set('Content-Type', 'application/json')
        .send('not-json')
        .expect(400)
    })

    it('should reject extra fields when forbidNonWhitelisted is enabled', async () => {
      const response = await request(app.getHttpServer())
        .post('/bridges/cctp/transactions')
        .send({
          transactionHash: validTxHash,
          sourceChainId: 84532,
          extraField: 'should cause error',
        })
        .expect(400)

      expect(Array.isArray(response.body.message)).toBe(true)
      expect(response.body.message[0]).toMatch(/extraField/)
    })
  })
})
