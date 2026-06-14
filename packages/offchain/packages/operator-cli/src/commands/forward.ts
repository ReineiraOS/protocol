import { Command } from 'commander'
import { Contract, ContractTransactionResponse, EventLog } from 'ethers'
import { loadConfig, getParentOptions } from '../utils/config'
import { createProvider, createWalletWithProvider } from '../utils/provider'
import { log } from '../utils/format'
import { CCTP_ADDRESSES } from '../utils/cctp'
import ConfidentialEscrowABI from '../abis/ConfidentialEscrow.json'

interface ForwardRedeemOptions {
  escrowId: string
  escrowIds?: string
}

const forwardRedeemCommand = new Command('redeem')
  .description('Redeem from escrow')
  .option('--escrow-id <id>', 'Single escrow ID to redeem')
  .option('--escrow-ids <ids>', 'Comma-separated escrow IDs to batch redeem')
  .action(async function (this: Command, options: ForwardRedeemOptions) {
    try {
      const config = loadConfig(getParentOptions(this.parent!), true)

      if (!options.escrowId && !options.escrowIds) {
        throw new Error('Provide --escrow-id or --escrow-ids')
      }

      const escrowAddress = CCTP_ADDRESSES.arbitrumSepoliaContracts.escrow
      if (!escrowAddress) {
        throw new Error('Missing escrow address')
      }

      const provider = createProvider(config.rpcUrl)
      const wallet = createWalletWithProvider(config.privateKey, provider)

      const escrow = new Contract(escrowAddress, ConfidentialEscrowABI, wallet)

      if (options.escrowIds) {
        const ids = options.escrowIds.split(',').map((id) => BigInt(id.trim()))
        log.info(`Redeeming ${ids.length} escrows: [${ids.join(', ')}]`)

        const tx = (await escrow.redeemMultiple(ids)) as ContractTransactionResponse
        const receipt = await tx.wait()
        log.tx(tx.hash)

        parseEscrowEvents(escrow, receipt)
        log.success('Batch redeem complete!')
      } else {
        const escrowId = BigInt(options.escrowId)
        log.info(`Redeeming escrow #${escrowId}...`)

        const tx = (await escrow.redeem(escrowId)) as ContractTransactionResponse
        const receipt = await tx.wait()
        log.tx(tx.hash)

        parseEscrowEvents(escrow, receipt)
        log.success('Redeem complete!')
      }

      console.log('\nForward Details')
      console.log('─'.repeat(50))
      console.log(`Escrow Contract: ${escrowAddress}`)
      console.log('─'.repeat(50))
    } catch (err) {
      log.error(err instanceof Error ? err.message : 'Failed to forward redeem')
      process.exit(1)
    }
  })

function parseEscrowEvents(escrow: Contract, receipt: import('ethers').TransactionReceipt | null) {
  if (!receipt) return
  for (const eventLog of receipt.logs) {
    try {
      if (!(eventLog instanceof EventLog)) continue
      const parsed = escrow.interface.parseLog({
        topics: eventLog.topics as string[],
        data: eventLog.data,
      })
      if (parsed && parsed.name === 'EscrowRedeemed') {
        log.info(`  Redeemed: escrow #${parsed.args[0]}`)
      }
      if (parsed && parsed.name === 'EscrowBatchRedeemed') {
        log.info(`  Batch redeemed: escrows [${parsed.args[0]}]`)
      }
    } catch {
      // Not our event
    }
  }
}

export const forwardCommand = new Command('forward')
  .description('Redeem escrow(s)')
  .addCommand(forwardRedeemCommand)
