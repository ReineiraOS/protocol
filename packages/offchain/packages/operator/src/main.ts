import 'reflect-metadata'
import { NestFactory } from '@nestjs/core'
import { Logger } from '@nestjs/common'
import { AppModule } from './app.module'

async function bootstrap() {
  const logger = new Logger('Operator')

  logger.log('Starting Reineira Operator Service...')
  logger.log('─'.repeat(50))

  const app = await NestFactory.create(AppModule, {
    logger: ['error', 'warn', 'log'],
  })

  const port = process.env.PORT || 3002

  app.enableShutdownHooks()

  process.on('SIGINT', () => {
    logger.log('Received SIGINT, shutting down...')
    void app.close().then(() => process.exit(0))
  })

  process.on('SIGTERM', () => {
    logger.log('Received SIGTERM, shutting down...')
    void app.close().then(() => process.exit(0))
  })

  await app.listen(port)
  logger.log(`Operator service is running on port ${port}. Press Ctrl+C to stop.`)
}

bootstrap().catch((error) => {
  console.error('Failed to start operator:', error)
  process.exit(1)
})
