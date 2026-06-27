#!/usr/bin/env node
import { Command } from 'commander'
import { bridgeCommand } from './commands/bridge'
import { relayCommand } from './commands/relay'
import { createEscrowCommand } from './commands/create-escrow'
import { redeemEscrowCommand } from './commands/redeem-escrow'
import { forwardCommand } from './commands/forward'

const program = new Command()

program
  .name('reineira')
  .description('Reineira development, debugging & deployment CLI (bridge, settle, escrow)')
  .version('0.1.0')
  .option('--rpc <url>', 'RPC endpoint URL (destination)', process.env.RPC_URL)
  .option('--rpc-source <url>', 'Source chain RPC URL', process.env.RPC_URL_SOURCE)
  .option('--private-key <key>', 'Signer private key', process.env.PRIVATE_KEY)
  .option(
    '--escrow-receiver <address>',
    'CCTPV2EscrowReceiver contract address',
    process.env.ESCROW_RECEIVER_ADDRESS,
  )

program.addCommand(bridgeCommand)
program.addCommand(relayCommand)
program.addCommand(createEscrowCommand)
program.addCommand(redeemEscrowCommand)
program.addCommand(forwardCommand)

program.parse()
