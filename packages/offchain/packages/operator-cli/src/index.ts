#!/usr/bin/env node
import { Command } from 'commander'
import { registerCommand } from './commands/register'
import { stakeCommand } from './commands/stake'
import { unbondCommand } from './commands/unbond'
import { withdrawCommand } from './commands/withdraw'
import { statusCommand } from './commands/status'
import { bridgeCommand } from './commands/bridge'
import { relayCommand } from './commands/relay'
import { createEscrowCommand } from './commands/create-escrow'
import { redeemEscrowCommand } from './commands/redeem-escrow'
import { forwardCommand } from './commands/forward'

const program = new Command()

program
  .name('reineira-operator')
  .description('Reineira operator CLI for CCTP bridge relay')
  .version('0.1.0')
  .option('--rpc <url>', 'RPC endpoint URL (destination)', process.env.RPC_URL)
  .option('--rpc-source <url>', 'Source chain RPC URL', process.env.RPC_URL_SOURCE)
  .option('--private-key <key>', 'Operator private key', process.env.PRIVATE_KEY)
  .option(
    '--registry <address>',
    'OperatorRegistry contract address',
    process.env.OPERATOR_REGISTRY_ADDRESS,
  )
  .option(
    '--executor <address>',
    'TaskExecutor contract address',
    process.env.TASK_EXECUTOR_ADDRESS,
  )

program.addCommand(registerCommand)
program.addCommand(stakeCommand)
program.addCommand(unbondCommand)
program.addCommand(withdrawCommand)
program.addCommand(statusCommand)
program.addCommand(bridgeCommand)
program.addCommand(relayCommand)
program.addCommand(createEscrowCommand)
program.addCommand(redeemEscrowCommand)
program.addCommand(forwardCommand)

program.parse()
