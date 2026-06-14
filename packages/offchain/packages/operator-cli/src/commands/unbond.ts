import { Command } from 'commander'
import { loadConfig, getParentOptions } from '../utils/config'
import { createWallet } from '../utils/provider'
import { getRegistryContract, getERC20Contract } from '../utils/contracts'
import { log, formatStake, formatDuration } from '../utils/format'
import * as readline from 'readline'

const UNBOND_PERIOD = 7 * 24 * 60 * 60 // 7 days in seconds

function confirm(question: string): Promise<boolean> {
  const rl = readline.createInterface({
    input: process.stdin,
    output: process.stdout,
  })
  return new Promise((resolve) => {
    rl.question(question, (answer) => {
      rl.close()
      resolve(answer.toLowerCase() === 'y' || answer.toLowerCase() === 'yes')
    })
  })
}

export const unbondCommand = new Command('unbond')
  .description('Start unbonding period to exit (7 days)')
  .option('--confirm', 'Skip confirmation prompt')
  .action(async function (this: Command, options: { confirm?: boolean }) {
    try {
      const config = loadConfig(getParentOptions(this))
      const wallet = createWallet(config)
      const registry = getRegistryContract(config.registryAddress, wallet)

      const info = await registry.getOperatorInfo(wallet.address)

      if (!info.isActive && info.unbondRequestTime === 0n) {
        log.error('Not registered as operator')
        process.exit(1)
      }

      if (info.unbondRequestTime > 0n) {
        const unlockTime = Number(info.unbondRequestTime) + UNBOND_PERIOD
        const remaining = unlockTime - Math.floor(Date.now() / 1000)
        if (remaining > 0) {
          log.warn(`Already unbonding. ${formatDuration(remaining)} remaining`)
        } else {
          log.info('Unbonding complete. Run `withdraw` to claim stake')
        }
        process.exit(0)
      }

      const tokenAddress = await registry.stakingToken()
      const token = getERC20Contract(tokenAddress, wallet)
      const decimals = await token.decimals()
      const symbol = await token.symbol()

      console.log('')
      console.log('Warning: Unbonding')
      console.log('─'.repeat(40))
      console.log(`Stake to unbond: ${formatStake(info.stake, decimals)} ${symbol}`)
      console.log('Unbond period:   7 days')
      console.log('You will be removed from active operators immediately.')
      console.log('Stake can be withdrawn after the unbond period.')
      console.log('')

      if (!options.confirm) {
        const proceed = await confirm('Proceed with unbonding? (y/N): ')
        if (!proceed) {
          log.info('Cancelled')
          process.exit(0)
        }
      }

      log.info('Requesting unbond...')
      const tx = await registry.requestUnbond()
      await tx.wait()
      log.tx(tx.hash)

      const unlockDate = new Date(Date.now() + UNBOND_PERIOD * 1000)
      log.success('Unbonding started')
      log.info(`Stake available for withdrawal: ${unlockDate.toISOString()}`)
    } catch (err) {
      log.error(err instanceof Error ? err.message : 'Unbond failed')
      process.exit(1)
    }
  })
