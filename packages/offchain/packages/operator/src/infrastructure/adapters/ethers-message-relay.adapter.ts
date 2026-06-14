import { Injectable, Logger } from '@nestjs/common'
import { ConfigService } from '@nestjs/config'
import {
  Contract,
  JsonRpcProvider,
  Wallet,
  NonceManager,
  Signer,
  ContractTransactionResponse,
  ContractTransactionReceipt,
} from 'ethers'
import { MessageRelayPort, MessageRelayResult } from '../../domain/ports/message-relay.port'

const MessageTransmitterV2ABI = [
  {
    name: 'receiveMessage',
    type: 'function',
    stateMutability: 'nonpayable',
    inputs: [
      { name: 'message', type: 'bytes' },
      { name: 'attestation', type: 'bytes' },
    ],
    outputs: [{ name: 'success', type: 'bool' }],
  },
]

const MESSAGE_TRANSMITTER_V2_TESTNET = '0xE737e5cEBEEBa77EFE34D4aa090756590b1CE275'

interface ChainConfig {
  provider: JsonRpcProvider
  signer: Signer
}

@Injectable()
export class EthersMessageRelayAdapter implements MessageRelayPort {
  private readonly logger = new Logger(EthersMessageRelayAdapter.name)
  private readonly chains = new Map<number, ChainConfig>()
  private readonly rpcUrls: Record<string, string>
  private readonly privateKey: string

  constructor(private readonly configService: ConfigService) {
    this.privateKey = configService.get<string>('PRIVATE_KEY', '')
    const rpcUrlsJson = configService.get<string>('DESTINATION_RPC_URLS', '{}')
    try {
      this.rpcUrls = JSON.parse(rpcUrlsJson) as Record<string, string>
    } catch {
      this.rpcUrls = {}
    }
  }

  private getChainConfig(chainId: number): ChainConfig {
    const existing = this.chains.get(chainId)
    if (existing) {
      return existing
    }

    const rpcUrl = this.rpcUrls[chainId.toString()]
    if (!rpcUrl) {
      throw new Error(`No RPC URL configured for chain ${chainId}`)
    }

    if (!this.privateKey) {
      throw new Error('Missing PRIVATE_KEY configuration')
    }

    const provider = new JsonRpcProvider(rpcUrl)
    const baseWallet = new Wallet(this.privateKey, provider)
    const signer = new NonceManager(baseWallet)

    const config: ChainConfig = { provider, signer }
    this.chains.set(chainId, config)

    this.logger.log(`Initialized message relay for chain ${chainId}`)
    return config
  }

  async relayMessage(
    destinationChainId: number,
    message: string,
    attestation: string,
  ): Promise<MessageRelayResult> {
    try {
      const { signer } = this.getChainConfig(destinationChainId)

      const transmitterAddress =
        this.configService.get<string>('MESSAGE_TRANSMITTER_V2_ADDRESS') ||
        MESSAGE_TRANSMITTER_V2_TESTNET

      const contract = new Contract(transmitterAddress, MessageTransmitterV2ABI, signer)

      this.logger.log(`Relaying message to chain ${destinationChainId}`)

      const tx = (await contract.receiveMessage(
        message,
        attestation,
      )) as ContractTransactionResponse

      this.logger.log(`Relay transaction submitted: ${tx.hash}`)

      const receipt = (await tx.wait()) as ContractTransactionReceipt
      this.logger.log(`Relay transaction confirmed: ${receipt.hash}`)

      return {
        success: true,
        transactionHash: receipt.hash,
      }
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error)
      this.logger.error(`Relay failed for chain ${destinationChainId}: ${errorMessage}`)

      return {
        success: false,
        error: errorMessage,
      }
    }
  }
}
