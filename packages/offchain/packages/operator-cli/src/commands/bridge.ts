import { Command } from 'commander'
import { parseUnits, AbiCoder, zeroPadValue, ContractTransactionResponse } from 'ethers'
import { loadConfig, getParentOptions } from '../utils/config'
import { createProvider, createWalletWithProvider } from '../utils/provider'
import {
  getTokenMessengerV2,
  getUSDC,
  waitForAttestation,
  DOMAINS,
  CCTP_ADDRESSES,
} from '../utils/cctp'
import { log } from '../utils/format'

interface BridgeOptions {
  amount: string
  escrowId: string
  recipient?: string
  fast: boolean
  wait?: boolean
}

export const bridgeCommand = new Command('bridge')
  .description('Bridge USDC from Ethereum Sepolia to Arbitrum Sepolia with escrow hook')
  .requiredOption('--amount <amount>', 'Amount of USDC to bridge (e.g., "10.00")')
  .requiredOption('--escrow-id <id>', 'Escrow ID to include in hook data')
  .option(
    '--recipient <address>',
    'Recipient address on destination (default: CCTPV2EscrowReceiver)',
  )
  .option('--fast', 'Use Fast Transfer (default)', true)
  .option('--no-fast', 'Use Standard Transfer')
  .option('--wait', 'Wait for attestation and show message hash')
  .action(async function (this: Command, options: BridgeOptions) {
    try {
      const config = loadConfig(getParentOptions(this), false)

      if (!config.rpcUrlSource) {
        throw new Error('Missing --rpc-source or RPC_URL_SOURCE for source chain')
      }

      // Create wallet for Ethereum Sepolia (source chain)
      const sourceProvider = createProvider(config.rpcUrlSource)
      const sourceWallet = createWalletWithProvider(config.privateKey, sourceProvider)

      // Contract instances
      const usdc = getUSDC(CCTP_ADDRESSES.ethereumSepolia.usdc, sourceWallet)
      const tokenMessenger = getTokenMessengerV2(
        CCTP_ADDRESSES.ethereumSepolia.tokenMessenger,
        sourceWallet,
      )

      // Parse amount (USDC has 6 decimals)
      const amount = parseUnits(options.amount, 6)

      // Destination config
      const destinationDomain = DOMAINS.ARBITRUM_SEPOLIA
      const mintRecipient: string =
        options.recipient || CCTP_ADDRESSES.arbitrumSepoliaContracts.escrowReceiver

      // Encode escrow ID as hook data
      const abiCoder = AbiCoder.defaultAbiCoder()
      const hookData = abiCoder.encode(['uint256'], [options.escrowId])

      // Finality threshold: 1000 for fast, 2000 for standard
      const minFinalityThreshold = options.fast ? 1000 : 2000

      // Calculate maxFee (for fast transfer)
      // Base fast fee is 1 bps (0.01%), we add a small buffer (2 bps total)
      // Minimum fee of 0.01 USDC (10000 units) for small amounts
      const MIN_FEE = 10000n // 0.01 USDC
      const calculatedFee = (amount * 2n) / 10000n
      const maxFee = options.fast ? (calculatedFee < MIN_FEE ? MIN_FEE : calculatedFee) : 0n

      // Check USDC balance
      const balance = (await usdc.balanceOf(sourceWallet.address)) as bigint
      if (balance < amount) {
        log.error(`Insufficient USDC balance: ${balance.toString()} < ${amount.toString()}`)
        process.exit(1)
      }

      // Step 1: Approve USDC
      log.info(`Approving ${options.amount} USDC...`)
      const approveTx = (await usdc.approve(
        CCTP_ADDRESSES.ethereumSepolia.tokenMessenger,
        amount,
      )) as ContractTransactionResponse
      await approveTx.wait()
      log.tx(approveTx.hash)

      // Step 2: Call depositForBurnWithHook
      log.info(`Burning USDC with escrow ID ${options.escrowId}...`)

      // Convert recipient to bytes32
      const mintRecipientBytes32 = zeroPadValue(mintRecipient, 32)

      // destinationCaller = 0 means any address can receive
      const destinationCaller = zeroPadValue('0x0000000000000000000000000000000000000000', 32)

      const burnTx = (await tokenMessenger.depositForBurnWithHook(
        amount,
        destinationDomain,
        mintRecipientBytes32,
        CCTP_ADDRESSES.ethereumSepolia.usdc,
        destinationCaller,
        maxFee,
        minFinalityThreshold,
        hookData,
      )) as ContractTransactionResponse

      await burnTx.wait()
      log.tx(burnTx.hash)
      log.success('USDC burned successfully')

      console.log('\nBridge Details')
      console.log('─'.repeat(50))
      console.log(`Amount:          ${options.amount} USDC`)
      console.log(`Escrow ID:       ${options.escrowId}`)
      console.log(`Transfer Mode:   ${options.fast ? 'Fast (~30s)' : 'Standard (~15min)'}`)
      console.log(
        `Finality:        ${minFinalityThreshold} (${options.fast ? 'confirmed' : 'finalized'})`,
      )
      console.log(`Max Fee:         ${Number(maxFee) / 1e6} USDC`)
      console.log(`Source TX:       ${burnTx.hash}`)
      console.log(`Recipient:       ${mintRecipient}`)

      if (options.wait) {
        log.info('Waiting for attestation...')
        const attestationResult = await waitForAttestation(burnTx.hash, DOMAINS.ETHEREUM_SEPOLIA)

        console.log('─'.repeat(50))
        console.log(`Event Nonce:     ${attestationResult.eventNonce}`)
        console.log(`Status:          ${attestationResult.status}`)
        console.log(`Message:         ${attestationResult.message.slice(0, 40)}...`)
        console.log(`Attestation:     ${attestationResult.attestation.slice(0, 40)}...`)
        log.success('Attestation received - ready for relay')
      } else {
        console.log('─'.repeat(50))
        log.info('Use --wait flag to wait for attestation')
        log.info(
          `Check status: GET https://iris-api-sandbox.circle.com/v2/messages/${DOMAINS.ETHEREUM_SEPOLIA}?transactionHash=${burnTx.hash}`,
        )
      }
    } catch (err) {
      log.error(err instanceof Error ? err.message : 'Bridge failed')
      process.exit(1)
    }
  })
