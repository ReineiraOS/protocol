import { Command } from 'commander'
import chalk from 'chalk'
import { loadConfig, getParentOptions } from '../utils/config'
import { createWallet } from '../utils/provider'
import { getRegistryContract, getERC20Contract } from '../utils/contracts'
import { formatStake, formatDuration } from '../utils/format'

export const statusCommand = new Command('status')
  .description('Show operator status')
  .action(async function (this: Command) {
    try {
      const config = loadConfig(getParentOptions(this))
      const wallet = createWallet(config)
      const registry = getRegistryContract(config.registryAddress, wallet)

      const info = await registry.getOperatorInfo(wallet.address)
      const tokenAddress = await registry.stakingToken()
      const token = getERC20Contract(tokenAddress, wallet)
      const decimals = await token.decimals()
      const symbol = await token.symbol()
      const minStake = await registry.minStake()

      // Fetch UNBOND_PERIOD from contract
      let unbondPeriod: bigint
      try {
        unbondPeriod = await registry.UNBOND_PERIOD()
      } catch {
        // Fallback to default if not available
        unbondPeriod = BigInt(7 * 24 * 60 * 60)
      }

      console.log('')
      console.log('Operator Status')
      console.log('═'.repeat(45))
      console.log(`Address:     ${wallet.address}`)
      console.log('─'.repeat(45))

      // Registration status
      const isRegistered = info.stake > 0n || info.isActive
      console.log(`Registered:  ${isRegistered ? chalk.green('Yes') : chalk.gray('No')}`)

      if (!isRegistered) {
        console.log(`
Not registered. Run 'register --stake <amount>' to start.`)
        console.log(`Minimum stake: ${formatStake(minStake, decimals)} ${symbol}`)
        return
      }

      // Active status
      const activeStatus = info.isActive
        ? chalk.green('Active')
        : info.unbondRequestTime > 0n
          ? chalk.yellow('Unbonding')
          : chalk.red('Inactive')
      console.log(`Status:      ${activeStatus}`)

      // Slashed status
      if (info.slashed) {
        console.log(`Slashed:     ${chalk.red('Yes - permanently disabled')}`)
      }

      // Stake
      const stakeColor = info.stake >= minStake ? chalk.green : chalk.red
      console.log(`Stake:       ${stakeColor(formatStake(info.stake, decimals))} ${symbol}`)

      // Unbonding info
      if (info.unbondRequestTime > 0n) {
        const unlockTime = Number(info.unbondRequestTime) + Number(unbondPeriod)
        const now = Math.floor(Date.now() / 1000)
        const remaining = unlockTime - now

        console.log('─'.repeat(45))
        if (remaining > 0) {
          console.log(`Unbond:      ${chalk.yellow(formatDuration(remaining) + ' remaining')}`)
        } else {
          console.log(`Unbond:      ${chalk.green('Ready to withdraw')}`)
        }
      }

      console.log('═'.repeat(45))
    } catch (err) {
      console.error(chalk.red('Error:'), err instanceof Error ? err.message : 'Unknown error')
      process.exit(1)
    }
  })
