import { Controller, Get, Res } from '@nestjs/common'
import { Response } from 'express'
import { readFileSync } from 'fs'
import { join } from 'path'
import * as yaml from 'js-yaml'

@Controller('api')
export class OpenApiController {
  private readonly openapiPath = join(__dirname, '..', '..', '..', 'openapi.yaml')

  @Get('openapi.json')
  getOpenApiJson(@Res() res: Response): void {
    const document = yaml.load(readFileSync(this.openapiPath, 'utf8'))
    res.json(document)
  }

  @Get('openapi.yaml')
  getOpenApiYaml(@Res() res: Response): void {
    res.setHeader('Content-Type', 'text/yaml')
    res.send(readFileSync(this.openapiPath, 'utf8'))
  }
}
