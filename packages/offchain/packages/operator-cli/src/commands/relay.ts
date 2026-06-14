import { Command } from 'commander'
import { keccak256, EventLog, AbiCoder } from 'ethers'
import { loadConfig, getParentOptions } from '../utils/config'
import { createProvider, createWalletWithProvider } from '../utils/provider'
import { waitForAttestation, DOMAINS } from '../utils/cctp'
import { log } from '../utils/format'
import { getTaskExecutorContract, getRegistryContract } from '../utils/contracts'
import { TASK_TYPES } from '@reineira-ops/shared'

interface RelayOptions {
  txHash: string
  message?: string
  attestation?: string
  skipClaim?: boolean
}

export const relayCommand = new Command('relay')
  .description('Relay a CCTP message to the destination chain')
  .requiredOption('--tx-hash <hash>', 'Source chain transaction hash')
  .option('--message <hex>', 'CCTP message (if already fetched)')
  .option('--attestation <hex>', 'Circle attestation (if already fetched)')
  .option('--skip-claim', 'Skip claiming the task (for permissionless execution)')
  .action(async function (this: Command, options: RelayOptions) {
    try {
      const config = loadConfig(getParentOptions(this), true)

      if (!config.taskExecutorAddress) {
        throw new Error('Missing TASK_EXECUTOR_ADDRESS. Set it in .env or use --executor flag')
      }

      const provider = createProvider(config.rpcUrl)
      const wallet = createWalletWithProvider(config.privateKey, provider)

      log.info(`Operator address: ${wallet.address}`)

      let message = options.message
      let attestation = options.attestation

      if (!message || !attestation) {
        log.info(`Fetching attestation for tx ${options.txHash}...`)
        const attestationResult = await waitForAttestation(options.txHash, DOMAINS.ETHEREUM_SEPOLIA)

        message = attestationResult.message
        attestation = attestationResult.attestation

        console.log('─'.repeat(50))
        console.log(`Event Nonce:     ${attestationResult.eventNonce}`)
        console.log(`Status:          ${attestationResult.status}`)
        console.log(`Message:         ${message.slice(0, 40)}...`)
        console.log(`Attestation:     ${attestation.slice(0, 40)}...`)
        log.success('Attestation received')
      }

      const messageHash = keccak256(message)
      log.info(`Message hash: ${messageHash}`)

      // Encode the CCTP payload as CCTPPayload struct (tuple of bytes, bytes)
      const abiCoder = AbiCoder.defaultAbiCoder()
      const payload = abiCoder.encode(['(bytes,bytes)'], [[message, attestation]])

      // Task hash = keccak256(message) - must match CCTPHandler.getTaskHash()
      const taskHash = messageHash
      log.info(`Task hash: ${taskHash}`)

      // Optionally claim the task first
      if (!options.skipClaim) {
        const registry = getRegistryContract(config.registryAddress, wallet)

        // Check if we can execute
        const canExecute = await registry.canExecuteTask(wallet.address, taskHash)
        if (!canExecute) {
          log.info('Claiming task...')
          const claimTx = await registry.claimTask(taskHash)
          await claimTx.wait()
          log.tx(claimTx.hash)
          log.success('Task claimed')
        }
      }

      const executor = getTaskExecutorContract(config.taskExecutorAddress, wallet)

      log.info('Executing task...')
      const tx = await executor.executeTask(TASK_TYPES.CCTP_RELAY, payload)

      log.tx(tx.hash)
      log.info('Waiting for confirmation...')

      const receipt = await tx.wait()

      if (receipt && receipt.status === 1) {
        log.success('Task executed successfully!')

        console.log('\nTask Details')
        console.log('─'.repeat(50))
        console.log(`Transaction:     ${receipt.hash}`)
        console.log(`Block:           ${receipt.blockNumber}`)
        console.log(`Gas Used:        ${receipt.gasUsed.toString()}`)

        // Look for TaskExecuted event from TaskExecutor
        const taskEvent = receipt.logs.find(
          (l): l is EventLog => l instanceof EventLog && l.fragment?.name === 'TaskExecuted',
        )

        if (taskEvent) {
          // TaskExecuted(bytes32 taskType, bytes32 taskHash, address operator, uint256 operatorFee)
          const args = taskEvent.args as unknown as [string, string, string, bigint]
          console.log(`Task Type:       CCTP_RELAY`)
          console.log(`Task Hash:       ${args[1]}`)
          console.log(`Operator:        ${args[2]}`)
          console.log(`Fee Earned:      ${Number(args[3]) / 1e6} USDC`)
        }
      } else {
        log.error('Task execution failed')
        process.exit(1)
      }
    } catch (err) {
      log.error(err instanceof Error ? err.message : 'Relay failed')
      process.exit(1)
    }
  })
