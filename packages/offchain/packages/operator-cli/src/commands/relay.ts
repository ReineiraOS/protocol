import { Command } from 'commander'
import { keccak256, EventLog } from 'ethers'
import { loadConfig, getParentOptions } from '../utils/config'
import { createProvider, createWalletWithProvider } from '../utils/provider'
import { waitForAttestation, DOMAINS } from '../utils/cctp'
import { log } from '../utils/format'
import { getEscrowReceiverContract } from '../utils/contracts'

interface RelayOptions {
  txHash: string
  message?: string
  attestation?: string
}

export const relayCommand = new Command('relay')
  .description('Settle a bridged CCTP message into the escrow (permissionless)')
  .requiredOption('--tx-hash <hash>', 'Source chain transaction hash')
  .option('--message <hex>', 'CCTP message (if already fetched)')
  .option('--attestation <hex>', 'Circle attestation (if already fetched)')
  .action(async function (this: Command, options: RelayOptions) {
    try {
      const config = loadConfig(getParentOptions(this), true)

      if (!config.escrowReceiverAddress) {
        throw new Error(
          'Missing ESCROW_RECEIVER_ADDRESS. Set it in .env or use --escrow-receiver flag',
        )
      }

      const provider = createProvider(config.rpcUrl)
      const wallet = createWalletWithProvider(config.privateKey, provider)

      log.info(`Relayer address: ${wallet.address}`)

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

      log.info(`Message hash: ${keccak256(message)}`)

      // Permissionless settlement: the receiver verifies the Circle attestation
      // on-chain and funds the escrow. No claim, no executor, no operator stake.
      const receiver = getEscrowReceiverContract(config.escrowReceiverAddress, wallet)

      log.info('Settling escrow...')
      const tx = await receiver.settle(message, attestation)

      log.tx(tx.hash)
      log.info('Waiting for confirmation...')

      const receipt = await tx.wait()

      if (receipt && receipt.status === 1) {
        log.success('Escrow settled successfully!')

        console.log('\nSettlement Details')
        console.log('─'.repeat(50))
        console.log(`Transaction:     ${receipt.hash}`)
        console.log(`Block:           ${receipt.blockNumber}`)
        console.log(`Gas Used:        ${receipt.gasUsed.toString()}`)

        // EscrowSettled(uint256 escrowId, address settler, uint256 usdcAmount, uint256 fundedAmount)
        const settledEvent = receipt.logs.find(
          (l): l is EventLog => l instanceof EventLog && l.fragment?.name === 'EscrowSettled',
        )

        if (settledEvent) {
          const args = settledEvent.args as unknown as [bigint, string, bigint, bigint]
          console.log(`Escrow ID:       ${args[0].toString()}`)
          console.log(`Settler:         ${args[1]}`)
          console.log(`USDC Received:   ${Number(args[2]) / 1e6} USDC`)
        }
      } else {
        log.error('Settlement failed')
        process.exit(1)
      }
    } catch (err) {
      log.error(err instanceof Error ? err.message : 'Relay failed')
      process.exit(1)
    }
  })
