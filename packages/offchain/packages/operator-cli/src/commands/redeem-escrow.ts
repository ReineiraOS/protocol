import { Command } from 'commander'
import { Contract, ContractTransactionResponse } from 'ethers'
import { loadConfig, getParentOptions } from '../utils/config'
import { createProvider, createWalletWithProvider } from '../utils/provider'
import { log } from '../utils/format'
import { CCTP_ADDRESSES } from '../utils/cctp'
import ConfidentialEscrowABI from '../abis/ConfidentialEscrow.json'

interface RedeemEscrowOptions {
  escrowId: string
  escrowIds?: string
}

export const redeemEscrowCommand = new Command('redeem-escrow')
  .description('Redeem rUSDC from one or more confidential escrows')
  .option('--escrow-id <id>', 'Single escrow ID to redeem')
  .option('--escrow-ids <ids>', 'Comma-separated escrow IDs to batch redeem')
  .action(async function (this: Command, options: RedeemEscrowOptions) {
    try {
      const config = loadConfig(getParentOptions(this), true)

      if (!options.escrowId && !options.escrowIds) {
        throw new Error('Provide --escrow-id or --escrow-ids')
      }

      const provider = createProvider(config.rpcUrl)
      const wallet = createWalletWithProvider(config.privateKey, provider)

      const escrow = new Contract(
        CCTP_ADDRESSES.arbitrumSepoliaContracts.escrow,
        ConfidentialEscrowABI,
        wallet,
      )

      if (options.escrowIds) {
        const ids = options.escrowIds.split(',').map((id) => BigInt(id.trim()))
        log.info(`Checking ${ids.length} escrows: [${ids.join(', ')}]`)

        const validIds: bigint[] = []
        for (const id of ids) {
          const exists = (await escrow.exists(id)) as boolean
          if (exists) {
            validIds.push(id)
          } else {
            log.warn(`Escrow #${id} does not exist, skipping`)
          }
        }

        if (validIds.length === 0) {
          log.error('No valid escrow IDs to redeem')
          process.exit(1)
        }

        log.info(`Redeeming ${validIds.length} escrows: [${validIds.join(', ')}]`)

        const tx = (await escrow.redeemMultiple(validIds)) as ContractTransactionResponse
        await tx.wait()
        log.tx(tx.hash)

        log.success('Batch redeem complete!')

        console.log('\nRedeem Details')
        console.log('─'.repeat(50))
        console.log(`Escrow IDs:      [${validIds.join(', ')}]`)
        console.log(`Redeemer:        ${wallet.address}`)
        console.log(`Transaction:     ${tx.hash}`)
        console.log('─'.repeat(50))
      } else {
        const escrowId = BigInt(options.escrowId)
        log.info(`Redeeming escrow #${escrowId}...`)

        const exists = (await escrow.exists(escrowId)) as boolean
        if (!exists) {
          throw new Error(`Escrow #${escrowId} does not exist`)
        }

        const tx = (await escrow.redeem(escrowId)) as ContractTransactionResponse
        await tx.wait()
        log.tx(tx.hash)

        log.success('Escrow redeemed!')

        console.log('\nRedeem Details')
        console.log('─'.repeat(50))
        console.log(`Escrow ID:       ${escrowId}`)
        console.log(`Redeemer:        ${wallet.address}`)
        console.log(`Transaction:     ${tx.hash}`)
        console.log('─'.repeat(50))
      }

      log.info('rUSDC transferred to your wallet. Use "forward" command to unwrap to USDC.')
    } catch (err) {
      log.error(err instanceof Error ? err.message : 'Failed to redeem escrow')
      process.exit(1)
    }
  })
