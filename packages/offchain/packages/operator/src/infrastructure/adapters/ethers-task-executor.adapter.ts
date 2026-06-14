import { Injectable, Logger } from '@nestjs/common'
import { ConfigService } from '@nestjs/config'
import {
  Contract,
  JsonRpcProvider,
  Wallet,
  keccak256,
  AbiCoder,
  ContractTransactionResponse,
  ContractTransactionReceipt,
} from 'ethers'
import { TaskExecutorPort, TaskResult, OperatorStatus } from '../../domain/ports/task-executor.port'

interface TaskClaim {
  operator: string
  claimTime: bigint
  executed: boolean
}

interface OperatorInfo {
  stake: bigint
  unbondRequestTime: bigint
  isActive: boolean
  slashed: boolean
}

const TaskExecutorABI = [
  {
    name: 'executeTask',
    type: 'function',
    stateMutability: 'nonpayable',
    inputs: [
      { name: 'taskType', type: 'bytes32' },
      { name: 'payload', type: 'bytes' },
    ],
    outputs: [{ name: 'result', type: 'bytes' }],
  },
  {
    anonymous: false,
    inputs: [
      { indexed: true, name: 'taskType', type: 'bytes32' },
      { indexed: true, name: 'taskHash', type: 'bytes32' },
      { indexed: true, name: 'operator', type: 'address' },
      { indexed: false, name: 'operatorFee', type: 'uint256' },
    ],
    name: 'TaskExecuted',
    type: 'event',
  },
]

const OperatorRegistryABI = [
  {
    name: 'claimTask',
    type: 'function',
    stateMutability: 'nonpayable',
    inputs: [{ name: 'taskHash', type: 'bytes32' }],
    outputs: [],
  },
  {
    name: 'canExecuteTask',
    type: 'function',
    stateMutability: 'view',
    inputs: [
      { name: 'caller', type: 'address' },
      { name: 'taskHash', type: 'bytes32' },
    ],
    outputs: [{ name: '', type: 'bool' }],
  },
  {
    name: 'getTaskClaim',
    type: 'function',
    stateMutability: 'view',
    inputs: [{ name: 'taskHash', type: 'bytes32' }],
    outputs: [
      {
        name: '',
        type: 'tuple',
        components: [
          { name: 'operator', type: 'address' },
          { name: 'claimTime', type: 'uint256' },
          { name: 'executed', type: 'bool' },
        ],
      },
    ],
  },
  {
    name: 'getOperatorInfo',
    type: 'function',
    stateMutability: 'view',
    inputs: [{ name: 'operator', type: 'address' }],
    outputs: [
      {
        name: '',
        type: 'tuple',
        components: [
          { name: 'stake', type: 'uint256' },
          { name: 'unbondRequestTime', type: 'uint256' },
          { name: 'isActive', type: 'bool' },
          { name: 'slashed', type: 'bool' },
        ],
      },
    ],
  },
  {
    name: 'isOperatorActive',
    type: 'function',
    stateMutability: 'view',
    inputs: [{ name: 'operator', type: 'address' }],
    outputs: [{ name: '', type: 'bool' }],
  },
]

@Injectable()
export class EthersTaskExecutorAdapter implements TaskExecutorPort {
  private readonly logger = new Logger(EthersTaskExecutorAdapter.name)
  private provider: JsonRpcProvider | null = null
  private wallet: Wallet | null = null
  private walletAddress: string | null = null
  private executorContract: Contract | null = null
  private registryContract: Contract | null = null
  private readonly operatorAddress: string

  // Mutex for serializing write transactions to prevent nonce collisions.
  // Each write TX fetches a fresh nonce from the chain via 'pending' count,
  // so external nonce changes (e.g. CLI transactions) are handled correctly.
  private txMutex: Promise<void> = Promise.resolve()
  private managedNonce: number | null = null

  constructor(private readonly configService: ConfigService) {
    this.operatorAddress = configService.get<string>('OPERATOR_ADDRESS', '')
  }

  /**
   * Acquire a nonce for a write transaction. Serializes concurrent calls
   * and fetches the latest pending nonce from the chain to handle external
   * nonce changes (e.g. CLI transactions sharing the same wallet).
   */
  private acquireNonce(): Promise<{ nonce: number; release: () => void }> {
    return new Promise((resolve) => {
      this.txMutex = this.txMutex.then(async () => {
        // Fetch fresh pending nonce from chain
        const chainNonce = await this.provider!.getTransactionCount(this.walletAddress!, 'pending')

        // Use the higher of chain nonce or our tracked nonce to handle
        // both external nonce advances and our own pending transactions
        const nonce =
          this.managedNonce !== null ? Math.max(chainNonce, this.managedNonce) : chainNonce

        this.managedNonce = nonce + 1
        this.logger.debug(`Acquired nonce ${nonce} (chain: ${chainNonce}, next: ${nonce + 1})`)

        let released = false
        const release = () => {
          if (!released) {
            released = true
          }
        }

        resolve({ nonce, release })
      })
    })
  }

  private ensureInitialized(): void {
    if (this.wallet && this.executorContract && this.registryContract) {
      return
    }

    const rpcUrl = this.configService.get<string>('RPC_URL')
    const privateKey = this.configService.get<string>('PRIVATE_KEY')
    const executorAddress = this.configService.get<string>('TASK_EXECUTOR_ADDRESS')
    const registryAddress = this.configService.get<string>('OPERATOR_REGISTRY_ADDRESS')

    if (!rpcUrl || !privateKey || !executorAddress || !registryAddress) {
      throw new Error('Missing required configuration for task execution')
    }

    this.provider = new JsonRpcProvider(rpcUrl)
    const baseWallet = new Wallet(privateKey, this.provider)
    this.wallet = baseWallet
    this.walletAddress = baseWallet.address
    this.executorContract = new Contract(executorAddress, TaskExecutorABI, this.wallet)
    this.registryContract = new Contract(registryAddress, OperatorRegistryABI, this.wallet)

    this.logger.log(`Initialized task executor for operator ${this.walletAddress}`)
  }

  async canExecuteTask(taskHash: string): Promise<boolean> {
    this.ensureInitialized()

    const canExecute = (await this.registryContract!.canExecuteTask(
      this.walletAddress!,
      taskHash,
    )) as boolean

    this.logger.debug(`Can execute task ${taskHash}: ${String(canExecute)}`)
    return canExecute
  }

  async claimTask(taskHash: string): Promise<string | null> {
    this.ensureInitialized()

    try {
      const claim = (await this.registryContract!.getTaskClaim(taskHash)) as TaskClaim

      if (claim.operator !== '0x0000000000000000000000000000000000000000') {
        this.logger.debug(`Task ${taskHash} already claimed by ${claim.operator}`)
        return null
      }

      const { nonce, release } = await this.acquireNonce()
      try {
        this.logger.log(`Claiming task ${taskHash} (nonce: ${nonce})`)
        const tx = (await this.registryContract!.claimTask(taskHash, {
          nonce,
        })) as ContractTransactionResponse
        const receipt = (await tx.wait()) as ContractTransactionReceipt

        this.logger.log(`Task claimed: ${receipt.hash}`)
        return receipt.hash
      } finally {
        release()
      }
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error)
      this.logger.error(`Failed to claim task: ${errorMessage}`)
      return null
    }
  }

  async executeTask(taskType: string, payload: string): Promise<TaskResult> {
    this.ensureInitialized()

    // Compute task hash: keccak256(taskType + keccak256(payload))
    const abiCoder = AbiCoder.defaultAbiCoder()
    const payloadHash = keccak256(payload)
    const taskHash = keccak256(abiCoder.encode(['bytes32', 'bytes32'], [taskType, payloadHash]))

    this.logger.log(`Executing task ${taskHash} (type: ${taskType})`)

    try {
      const canExecute = await this.canExecuteTask(taskHash)
      if (!canExecute) {
        return {
          success: false,
          error: 'Not authorized to execute this task',
        }
      }

      const { nonce, release } = await this.acquireNonce()
      let tx: ContractTransactionResponse
      try {
        tx = (await this.executorContract!.executeTask(taskType, payload, {
          nonce,
        })) as ContractTransactionResponse
        this.logger.log(`Task transaction submitted: ${tx.hash} (nonce: ${nonce})`)
      } catch (submitError) {
        release()
        throw submitError
      }
      release()

      const receipt = (await tx.wait()) as ContractTransactionReceipt
      this.logger.log(`Task transaction confirmed: ${receipt.hash}`)

      // Extract operator fee from TaskExecuted event
      let operatorFee: bigint | undefined
      for (const log of receipt.logs) {
        try {
          const parsed = this.executorContract!.interface.parseLog({
            topics: log.topics as string[],
            data: log.data,
          })
          if (parsed?.name === 'TaskExecuted') {
            operatorFee = parsed.args[3] as bigint
            break
          }
        } catch {
          // Skip logs that don't match
        }
      }

      return {
        success: true,
        transactionHash: receipt.hash,
        operatorFee,
      }
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error)
      this.logger.error(`Task execution failed: ${errorMessage}`)

      return {
        success: false,
        error: errorMessage,
      }
    }
  }

  async getOperatorStatus(): Promise<OperatorStatus | null> {
    this.ensureInitialized()

    try {
      const info = (await this.registryContract!.getOperatorInfo(
        this.walletAddress!,
      )) as OperatorInfo

      return {
        address: this.walletAddress!,
        isActive: info.isActive,
        stake: info.stake,
        unbondRequestTime: info.unbondRequestTime,
        slashed: info.slashed,
      }
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error)
      this.logger.error(`Failed to get operator status: ${errorMessage}`)
      return null
    }
  }

  getOperatorAddress(): string {
    return this.operatorAddress || this.walletAddress || ''
  }
}
