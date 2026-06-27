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

// Permissionless settlement entry point. Verifies the Circle attestation
// on-chain and funds the confidential escrow atomically. Anyone may call it.
const EscrowReceiverABI = [
  {
    name: 'settle',
    type: 'function',
    stateMutability: 'nonpayable',
    inputs: [
      { name: 'message', type: 'bytes' },
      { name: 'attestation', type: 'bytes' },
    ],
    outputs: [],
  },
]

const MESSAGE_TRANSMITTER_V2_TESTNET = '0xE737e5cEBEEBa77EFE34D4aa090756590b1CE275'
// Arbitrum Sepolia — chain the confidential escrow / receiver are deployed on.
const DEFAULT_ESCROW_CHAIN_ID = 421614

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

    // Fail loud at startup rather than silently at the first settlement.
    if (!this.privateKey) {
      this.logger.warn('PRIVATE_KEY is not set — settlement transactions cannot be signed')
    }
    if (!this.configService.get<string>('ESCROW_RECEIVER_ADDRESS')) {
      this.logger.warn(
        'ESCROW_RECEIVER_ADDRESS is not set — escrow settlement (settle) will fail until configured',
      )
    }
  }

  private getChainConfig(chainId: number): ChainConfig {
    const existing = this.chains.get(chainId)
    if (existing) {
      return existing
    }

    const rpcUrl = this.rpcUrls[chainId.toString()] || this.configService.get<string>('RPC_URL')
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

  getOperatorAddress(): string {
    if (!this.privateKey) {
      return ''
    }
    try {
      return new Wallet(this.privateKey).address
    } catch {
      // Malformed PRIVATE_KEY — surface it as a warning instead of crashing
      // service startup with an opaque ethers error.
      this.logger.warn('PRIVATE_KEY is not a valid private key')
      return ''
    }
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

      const receipt = (await tx.wait()) as ContractTransactionReceipt | null
      const confirmedHash = receipt?.hash ?? tx.hash
      this.logger.log(`Relay transaction confirmed: ${confirmedHash}`)

      return {
        success: true,
        transactionHash: confirmedHash,
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

  async settle(message: string, attestation: string): Promise<MessageRelayResult> {
    const parsedChainId = Number(this.configService.get<string>('ESCROW_CHAIN_ID'))
    const escrowChainId = Number.isNaN(parsedChainId) ? DEFAULT_ESCROW_CHAIN_ID : parsedChainId

    try {
      const receiverAddress = this.configService.get<string>('ESCROW_RECEIVER_ADDRESS')
      if (!receiverAddress) {
        throw new Error('Missing ESCROW_RECEIVER_ADDRESS configuration')
      }

      const { signer } = this.getChainConfig(escrowChainId)
      const contract = new Contract(receiverAddress, EscrowReceiverABI, signer)

      this.logger.log(`Settling escrow via ${receiverAddress} on chain ${escrowChainId}`)

      const tx = (await contract.settle(message, attestation)) as ContractTransactionResponse
      this.logger.log(`Settle transaction submitted: ${tx.hash}`)

      const receipt = (await tx.wait()) as ContractTransactionReceipt | null
      const confirmedHash = receipt?.hash ?? tx.hash
      this.logger.log(`Settle transaction confirmed: ${confirmedHash}`)

      return {
        success: true,
        transactionHash: confirmedHash,
      }
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error)
      this.logger.error(`Settle failed on chain ${escrowChainId}: ${errorMessage}`)

      return {
        success: false,
        error: errorMessage,
      }
    }
  }
}
