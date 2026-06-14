import { Module } from '@nestjs/common'
import { ConfigModule } from '@nestjs/config'
import { CoordinatorService } from './application/services/coordinator.service'
import { MessageRepository } from './infrastructure/repositories/message.repository'
import { CCTPController } from './interfaces/http/cctp.controller'
import { OpenApiController } from './interfaces/http/openapi.controller'
import { OperatorController } from './interfaces/sse/operator.controller'

@Module({
  imports: [ConfigModule.forRoot({ isGlobal: true })],
  controllers: [CCTPController, OpenApiController, OperatorController],
  providers: [CoordinatorService, MessageRepository],
})
export class AppModule {}
