import { Command } from 'commander'
import { loadConfig, getParentOptions } from '../utils/config'
import { createWallet } from '../utils/provider'
import { getRegistryContract, getERC20Contract } from '../utils/contracts'
import { log, formatStake, formatDuration } from '../utils/format'

const UNBOND_PERIOD = 7 * 24 * 60 * 60

export const withdrawCommand = new Command('withdraw')
  .description('Withdraw stake after unbonding period')
  .action(async function (this: Command) {
    try {
      const config = loadConfig(getParentOptions(this))
      const wallet = createWallet(config)
      const registry = getRegistryContract(config.registryAddress, wallet)

      const info = await registry.getOperatorInfo(wallet.address)

      if (info.stake === 0n) {
        log.error('No stake to withdraw')
        process.exit(1)
      }

      if (info.unbondRequestTime === 0n) {
        log.error('No unbond request. Run `unbond` first')
        process.exit(1)
      }

      const unlockTime = Number(info.unbondRequestTime) + UNBOND_PERIOD
      const now = Math.floor(Date.now() / 1000)

      if (now < unlockTime) {
        const remaining = unlockTime - now
        log.error(`Unbonding not complete. ${formatDuration(remaining)} remaining`)
        process.exit(1)
      }

      const tokenAddress = await registry.stakingToken()
      const token = getERC20Contract(tokenAddress, wallet)
      const decimals = await token.decimals()
      const symbol = await token.symbol()

      log.info(`Withdrawing ${formatStake(info.stake, decimals)} ${symbol}...`)
      const tx = await registry.withdrawStake()
      await tx.wait()
      log.tx(tx.hash)

      log.success(`Withdrawn ${formatStake(info.stake, decimals)} ${symbol}`)
    } catch (err) {
      log.error(err instanceof Error ? err.message : 'Withdraw failed')
      process.exit(1)
    }
  })
