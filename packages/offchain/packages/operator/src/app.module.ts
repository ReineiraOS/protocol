import { Module } from '@nestjs/common'
import { ConfigModule } from '@nestjs/config'
import { ATTESTATION_PROVIDER_PORT } from './domain/ports/attestation-provider.port'
import { TASK_EXECUTOR_PORT } from './domain/ports/task-executor.port'
import { COORDINATOR_CLIENT_PORT } from './domain/ports/coordinator-client.port'
import { MESSAGE_RELAY_PORT } from './domain/ports/message-relay.port'
import { RELAY_CALLBACK_PORT } from './domain/ports/relay-callback.port'
import { IrisAttestationProviderAdapter } from './infrastructure/adapters/iris-attestation-provider.adapter'
import { EthersTaskExecutorAdapter } from './infrastructure/adapters/ethers-task-executor.adapter'
import { SseCoordinatorClientAdapter } from './infrastructure/adapters/sse-coordinator-client.adapter'
import { EthersMessageRelayAdapter } from './infrastructure/adapters/ethers-message-relay.adapter'
import { HttpRelayCallbackAdapter } from './infrastructure/adapters/http-relay-callback.adapter'
import { RelayJobRepository } from './infrastructure/repositories/relay-job.repository'
import { OperatorService } from './application/services/operator.service'
import { StatusController } from './interfaces/http/status.controller'

@Module({
  imports: [
    ConfigModule.forRoot({
      isGlobal: true,
      envFilePath: ['.env', '../operator-cli/.env'],
    }),
  ],
  controllers: [StatusController],
  providers: [
    {
      provide: ATTESTATION_PROVIDER_PORT,
      useClass: IrisAttestationProviderAdapter,
    },
    {
      provide: TASK_EXECUTOR_PORT,
      useClass: EthersTaskExecutorAdapter,
    },
    {
      provide: COORDINATOR_CLIENT_PORT,
      useClass: SseCoordinatorClientAdapter,
    },
    {
      provide: MESSAGE_RELAY_PORT,
      useClass: EthersMessageRelayAdapter,
    },
    {
      provide: RELAY_CALLBACK_PORT,
      useClass: HttpRelayCallbackAdapter,
    },
    RelayJobRepository,
    OperatorService,
  ],
  exports: [OperatorService],
})
export class AppModule {}
