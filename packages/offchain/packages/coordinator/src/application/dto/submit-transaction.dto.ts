import { IsString, IsNumber, IsOptional, IsObject, Matches, Min } from 'class-validator'

export class SubmitTransactionDto {
  @IsString()
  @Matches(/^0x[a-fA-F0-9]{64}$/, {
    message: 'Transaction hash must be 0x followed by 64 hex characters',
  })
  transactionHash: string

  @IsNumber()
  @Min(0)
  sourceChainId: number

  @IsOptional()
  @IsNumber()
  @Min(0)
  destinationChainId?: number

  @IsOptional()
  @IsString()
  taskType?: string

  @IsOptional()
  @IsObject()
  metadata?: Record<string, string>
}
