import { Injectable, Logger, OnModuleDestroy } from '@nestjs/common'
import { ConfigService } from '@nestjs/config'
import { Subject, Observable } from 'rxjs'
import EventSource from 'eventsource'
import { CoordinatorClientPort, RelayEvent } from '../../domain/ports/coordinator-client.port'

@Injectable()
export class SseCoordinatorClientAdapter implements CoordinatorClientPort, OnModuleDestroy {
  private readonly logger = new Logger(SseCoordinatorClientAdapter.name)
  private eventSource: EventSource | null = null
  private readonly relayEvents$ = new Subject<RelayEvent>()
  private reconnectAttempts = 0
  private readonly maxReconnectAttempts = 10
  private readonly reconnectDelayMs = 5000
  private readonly coordinatorUrl: string
  private readonly operatorAddress: string

  constructor(configService: ConfigService) {
    this.coordinatorUrl = configService.get<string>('COORDINATOR_URL', 'http://localhost:3001')
    this.operatorAddress = configService.get<string>('OPERATOR_ADDRESS', '')
  }

  connect(): Observable<RelayEvent> {
    if (!this.coordinatorUrl || !this.operatorAddress) {
      throw new Error('Missing coordinatorUrl or operatorAddress in configuration')
    }

    this.establishConnection()
    return this.relayEvents$.asObservable()
  }

  private establishConnection(): void {
    const url = `${this.coordinatorUrl}/operators/${this.operatorAddress}/subscribe`
    this.logger.log(`Connecting to coordinator at ${url}`)

    this.eventSource = new EventSource(url)

    this.eventSource.onopen = () => {
      this.logger.log('Connected to coordinator SSE stream')
      this.reconnectAttempts = 0
    }

    this.eventSource.addEventListener('relay', (event: MessageEvent) => {
      try {
        const relayEvent = JSON.parse(event.data as string) as RelayEvent
        this.logger.log(
          `Received relay event: ${relayEvent.id} for tx ${relayEvent.transactionHash}`,
        )
        this.relayEvents$.next(relayEvent)
      } catch (error) {
        const errorMessage = error instanceof Error ? error.message : String(error)
        this.logger.error(`Failed to parse relay event: ${errorMessage}`)
      }
    })

    this.eventSource.onerror = (error) => {
      this.logger.error(`SSE connection error: ${JSON.stringify(error)}`)
      this.handleReconnect()
    }
  }

  private handleReconnect(): void {
    if (this.eventSource) {
      this.eventSource.close()
      this.eventSource = null
    }

    if (this.reconnectAttempts < this.maxReconnectAttempts) {
      this.reconnectAttempts++
      this.logger.log(
        `Reconnecting to coordinator (attempt ${this.reconnectAttempts}/${this.maxReconnectAttempts})...`,
      )
      setTimeout(() => {
        this.establishConnection()
      }, this.reconnectDelayMs)
    } else {
      this.logger.error('Max reconnection attempts reached. Giving up.')
      this.relayEvents$.error(new Error('Max reconnection attempts reached'))
    }
  }

  disconnect(): void {
    if (this.eventSource) {
      this.logger.log('Disconnecting from coordinator')
      this.eventSource.close()
      this.eventSource = null
    }
    this.relayEvents$.complete()
  }

  onModuleDestroy(): void {
    this.disconnect()
  }

  isConnected(): boolean {
    return this.eventSource !== null && this.eventSource.readyState === EventSource.OPEN
  }
}
