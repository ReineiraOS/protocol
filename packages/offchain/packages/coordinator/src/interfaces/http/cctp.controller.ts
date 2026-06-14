import { Controller, Post, Body, HttpCode, HttpStatus } from '@nestjs/common'
import { CoordinatorService } from '../../application/services/coordinator.service'
import { SubmitTransactionDto } from '../../application/dto/submit-transaction.dto'
import { SubmitTransactionResponseDto } from '../../application/dto/submit-transaction-response.dto'

@Controller('bridges/cctp/transactions')
export class CCTPController {
  constructor(private readonly coordinatorService: CoordinatorService) {}

  @Post()
  @HttpCode(HttpStatus.ACCEPTED)
  submit(@Body() dto: SubmitTransactionDto): SubmitTransactionResponseDto {
    const message = this.coordinatorService.submitTransaction(dto)

    return {
      id: message.id,
      status: 'queued',
      message: 'CCTP transaction queued for relay',
    }
  }
}
