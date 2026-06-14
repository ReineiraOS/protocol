import { Controller, Get, Param } from '@nestjs/common'
import { OperatorService } from '../../application/services/operator.service'
import { RelayJobDto, RelayJobStatusDto } from '../../application/dto/relay-job.dto'

@Controller('status')
export class StatusController {
  constructor(private readonly operatorService: OperatorService) {}

  @Get()
  getStatus(): { isRunning: boolean; isConnected: boolean; operatorAddress: string } {
    return this.operatorService.getStatus()
  }

  @Get('jobs')
  getJobStatus(): RelayJobStatusDto {
    return this.operatorService.getJobStatus()
  }

  @Get('jobs/all')
  getJobs(): RelayJobDto[] {
    return this.operatorService.getJobs()
  }

  @Get('jobs/:id')
  getJob(@Param('id') id: string): RelayJobDto | undefined {
    return this.operatorService.getJob(id)
  }
}
