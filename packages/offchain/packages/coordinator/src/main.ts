import { NestFactory } from '@nestjs/core'
import { ValidationPipe } from '@nestjs/common'
import { AppModule } from './app.module'

async function bootstrap() {
  const app = await NestFactory.create(AppModule)

  app.useGlobalPipes(
    new ValidationPipe({
      whitelist: true,
      transform: true,
      forbidNonWhitelisted: true,
    }),
  )

  app.enableCors()

  const port = process.env.PORT || 3001
  await app.listen(port)

  console.log(`Coordinator service running on http://localhost:${port}`)
  console.log(`OpenAPI spec available at http://localhost:${port}/api/openapi.json`)
}

void bootstrap()
