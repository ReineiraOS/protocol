import { Controller, Sse, Param, Req, Logger, Get } from '@nestjs/common'
import { Observable, map, finalize } from 'rxjs'
import { Request } from 'express'
import { CoordinatorService } from '../../application/services/coordinator.service'
import { RelayEventDto } from '../../application/dto/relay-event.dto'

interface MessageEvent {
  data: string
  type?: string
  id?: string
  retry?: number
}

// TEMPORARY: SSE subscription will be deprecated in favor of a more robust messaging system
@Controller('operators')
export class OperatorController {
  private readonly logger = new Logger(OperatorController.name)

  constructor(private readonly coordinatorService: CoordinatorService) {}

  @Sse(':address/subscribe')
  subscribe(@Param('address') address: string, @Req() req: Request): Observable<MessageEvent> {
    this.logger.log(`Operator ${address} connecting via SSE`)

    req.on('close', () => {
      this.logger.log(`Operator ${address} disconnected`)
      this.coordinatorService.unsubscribeOperator(address)
    })

    return this.coordinatorService.subscribeOperator(address).pipe(
      map((event: RelayEventDto) => ({
        data: JSON.stringify(event),
        type: 'relay',
        id: event.id,
      })),
      finalize(() => {
        this.logger.log(`SSE stream finalized for ${address}`)
      }),
    )
  }

  @Get('stats')
  getStats(): { subscribedCount: number; operators: string[] } {
    return {
      subscribedCount: this.coordinatorService.getSubscribedOperatorCount(),
      operators: this.coordinatorService.getSubscribedOperators(),
    }
  }
}
