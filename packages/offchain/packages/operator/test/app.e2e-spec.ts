import { Test, TestingModule } from '@nestjs/testing'
import { INestApplication } from '@nestjs/common'
import request, { Agent } from 'supertest'
import { Subject } from 'rxjs'
import { AppModule } from '../src/app.module'
import { COORDINATOR_CLIENT_PORT, RelayEvent } from '../src/domain/ports/coordinator-client.port'
import { ATTESTATION_PROVIDER_PORT } from '../src/domain/ports/attestation-provider.port'
import { MESSAGE_RELAY_PORT } from '../src/domain/ports/message-relay.port'
import { Attestation } from '../src/domain/entities/attestation.entity'

interface StatusResponse {
  isRunning: boolean
  isConnected: boolean
  operatorAddress: string
}

interface JobStatusResponse {
  totalJobs: number
  pending: number
  fetchingAttestation: number
  claiming: number
  executing: number
  completed: number
  failed: number
}

interface JobResponse {
  id: string
  transactionHash: string
  sourceChainId: number
  status: string
}

describe('Operator (e2e)', () => {
  let app: INestApplication
  let server: Agent
  let relayEventsSubject: Subject<RelayEvent>

  const validTxHash = '0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef'
  const validMessage = '0x000000010000000600000000abcdef'
  const validAttestation = '0xabcdef1234567890'

  const coordinatorClientMock = {
    connect: jest.fn(),
    disconnect: jest.fn(),
    isConnected: jest.fn().mockReturnValue(true),
  }

  const attestationProviderMock = {
    getAttestation: jest.fn(),
    waitForAttestation: jest.fn().mockResolvedValue(
      new Attestation({
        message: validMessage,
        attestation: validAttestation,
        status: 'complete',
        eventNonce: '0x1234',
      }),
    ),
  }

  const messageRelayMock = {
    relayMessage: jest.fn().mockResolvedValue({
      success: true,
      transactionHash: validTxHash,
    }),
    settle: jest.fn().mockResolvedValue({
      success: true,
      transactionHash: validTxHash,
    }),
    getOperatorAddress: jest.fn().mockReturnValue('0x1234567890123456789012345678901234567890'),
  }

  beforeAll(async () => {
    relayEventsSubject = new Subject<RelayEvent>()
    coordinatorClientMock.connect.mockReturnValue(relayEventsSubject.asObservable())

    const moduleFixture: TestingModule = await Test.createTestingModule({
      imports: [AppModule],
    })
      .overrideProvider(COORDINATOR_CLIENT_PORT)
      .useValue(coordinatorClientMock)
      .overrideProvider(ATTESTATION_PROVIDER_PORT)
      .useValue(attestationProviderMock)
      .overrideProvider(MESSAGE_RELAY_PORT)
      .useValue(messageRelayMock)
      .compile()

    app = moduleFixture.createNestApplication()
    await app.init()
    server = request(app.getHttpServer() as Parameters<typeof request>[0])
  })

  afterAll(async () => {
    relayEventsSubject.complete()
    await app.close()
  })

  describe('GET /status', () => {
    it('should return operator status', async () => {
      const response = await server.get('/status').expect(200)

      const body = response.body as StatusResponse
      expect(body).toHaveProperty('isRunning')
      expect(body).toHaveProperty('isConnected')
      expect(body).toHaveProperty('operatorAddress')
    })
  })

  describe('GET /status/jobs', () => {
    it('should return job status counts', async () => {
      const response = await server.get('/status/jobs').expect(200)

      const body = response.body as JobStatusResponse
      expect(body).toHaveProperty('totalJobs')
      expect(body).toHaveProperty('pending')
      expect(body).toHaveProperty('completed')
      expect(body).toHaveProperty('failed')
    })
  })

  describe('GET /status/jobs/all', () => {
    it('should return all jobs', async () => {
      const response = await server.get('/status/jobs/all').expect(200)

      const body = response.body as JobResponse[]
      expect(Array.isArray(body)).toBe(true)
    })
  })

  describe('Relay Event Processing', () => {
    it('should process relay event and update job status', async () => {
      const event: RelayEvent = {
        id: 'e2e-test-id',
        transactionHash: validTxHash,
        sourceChainId: 6,
        message: validMessage,
        attestation: validAttestation,
        createdAt: new Date().toISOString(),
      }

      // Emit the event
      relayEventsSubject.next(event)

      // Wait for processing
      await new Promise((resolve) => setTimeout(resolve, 200))

      // Check job was processed
      const response = await server.get('/status/jobs').expect(200)

      const body = response.body as JobStatusResponse
      expect(body.totalJobs).toBeGreaterThan(0)
    })

    it('should handle multiple relay events', async () => {
      const events: RelayEvent[] = [
        {
          id: 'e2e-test-1',
          transactionHash: '0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
          sourceChainId: 6,
          message: validMessage,
          attestation: validAttestation,
          createdAt: new Date().toISOString(),
        },
        {
          id: 'e2e-test-2',
          transactionHash: '0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
          sourceChainId: 6,
          message: validMessage,
          attestation: validAttestation,
          createdAt: new Date().toISOString(),
        },
      ]

      // Emit events
      for (const event of events) {
        relayEventsSubject.next(event)
      }

      // Wait for processing
      await new Promise((resolve) => setTimeout(resolve, 300))

      // Check jobs were processed
      const response = await server.get('/status/jobs/all').expect(200)

      const body = response.body as JobResponse[]
      expect(body.length).toBeGreaterThanOrEqual(2)
    })

    it('should handle failed relay execution', async () => {
      // Mock failed settlement
      messageRelayMock.settle.mockResolvedValueOnce({
        success: false,
        error: 'E2E test failure',
      })

      const event: RelayEvent = {
        id: 'e2e-fail-test',
        transactionHash: '0xcccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc',
        sourceChainId: 6,
        message: validMessage,
        attestation: validAttestation,
        createdAt: new Date().toISOString(),
      }

      relayEventsSubject.next(event)

      // Wait for processing
      await new Promise((resolve) => setTimeout(resolve, 200))

      // Check job status
      const response = await server.get('/status/jobs').expect(200)

      const body = response.body as JobStatusResponse
      expect(body.failed).toBeGreaterThan(0)
    })
  })
})
