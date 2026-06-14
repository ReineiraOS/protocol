import { Command } from 'commander'
import { Contract, ContractTransactionResponse, ZeroAddress, parseUnits } from 'ethers'
import { loadConfig, getParentOptions } from '../utils/config'
import { createProvider, createWalletWithProvider } from '../utils/provider'
import { log } from '../utils/format'
import { CCTP_ADDRESSES } from '../utils/cctp'
import ConfidentialEscrowABI from '../abis/ConfidentialEscrow.json'

interface CreateEscrowOptions {
  owner?: string
  amount: string
  resolver?: string
}

export const createEscrowCommand = new Command('create-escrow')
  .description('Create a new confidential escrow on Arbitrum Sepolia')
  .requiredOption('--amount <amount>', 'Escrow amount in USDC (e.g., "100.00")')
  .option('--owner <address>', 'Escrow owner address (default: your wallet address)')
  .option('--resolver <address>', 'Condition resolver contract address (default: none)')
  .action(async function (this: Command, options: CreateEscrowOptions) {
    try {
      const config = loadConfig(getParentOptions(this), true)

      // Create wallet for Arbitrum Sepolia (destination chain)
      const provider = createProvider(config.rpcUrl)
      const wallet = createWalletWithProvider(config.privateKey, provider)

      const escrowOwner = options.owner || wallet.address
      const amount = parseUnits(options.amount, 6) // USDC has 6 decimals

      log.info('Creating escrow...')
      log.info(`  Owner: ${escrowOwner}`)
      log.info(`  Amount: ${options.amount} USDC`)

      log.info('Initializing FHE encryption...')

      const { createCofheConfig, createCofheClient } = await import('@cofhe/sdk/node')
      const { Encryptable } = await import('@cofhe/sdk')
      const { arbSepolia } = await import('@cofhe/sdk/chains')
      const { Ethers6Adapter } = await import('@cofhe/sdk/adapters')

      const { publicClient, walletClient } = await Ethers6Adapter(provider, wallet)

      const cofheClient = createCofheClient(createCofheConfig({ supportedChains: [arbSepolia] }))
      await cofheClient.connect(publicClient, walletClient)

      log.info('Encrypting escrow data...')

      const [encryptedOwner, encryptedAmount] = await cofheClient
        .encryptInputs([Encryptable.address(escrowOwner), Encryptable.uint64(amount)])
        .execute()

      // Create contract instance
      const escrow = new Contract(
        CCTP_ADDRESSES.arbitrumSepoliaContracts.escrow,
        ConfidentialEscrowABI,
        wallet,
      )

      // Create the escrow
      log.info('Submitting transaction...')
      const resolver = options.resolver || ZeroAddress
      const resolverData = '0x' // default empty resolver data
      const tx = (await escrow.create(
        encryptedOwner as unknown,
        encryptedAmount as unknown,
        resolver,
        resolverData,
      )) as ContractTransactionResponse

      const receipt = await tx.wait()
      log.tx(tx.hash)

      // Parse the EscrowCreated event to get the escrow ID
      let escrowId: string | undefined
      if (receipt && receipt.logs) {
        for (const eventLog of receipt.logs) {
          try {
            const parsed = escrow.interface.parseLog({
              topics: eventLog.topics as string[],
              data: eventLog.data,
            })
            if (parsed && parsed.name === 'EscrowCreated') {
              escrowId = String(parsed.args[0])
            }
          } catch {
            // Not our event, continue
          }
        }
      }

      log.success('Escrow created successfully!')

      console.log('\nEscrow Details')
      console.log('─'.repeat(50))
      console.log(`Escrow ID:       ${escrowId || 'Check transaction logs'}`)
      console.log(`Owner:           ${escrowOwner}`)
      console.log(`Amount:          ${options.amount} USDC`)
      console.log(`Escrow Contract: ${CCTP_ADDRESSES.arbitrumSepoliaContracts.escrow}`)
      console.log(`Transaction:     ${tx.hash}`)
      console.log('─'.repeat(50))

      if (escrowId) {
        log.info(`Use this Escrow ID (${escrowId}) when bridging USDC to settle this escrow`)
      }
    } catch (err) {
      log.error(err instanceof Error ? err.message : 'Failed to create escrow')
      process.exit(1)
    }
  })
