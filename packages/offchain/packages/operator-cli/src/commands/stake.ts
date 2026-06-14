import { Command } from 'commander'
import { parseUnits } from 'ethers'
import { loadConfig, getParentOptions } from '../utils/config'
import { createWallet } from '../utils/provider'
import { getRegistryContract, getERC20Contract } from '../utils/contracts'
import { log, formatStake } from '../utils/format'

const addCommand = new Command('add')
  .description('Add stake to your operator')
  .requiredOption('--amount <amount>', 'Amount to add')
  .action(async function (this: Command, options: { amount: string }) {
    try {
      const config = loadConfig(getParentOptions(this.parent!))
      const wallet = createWallet(config)
      const registry = getRegistryContract(config.registryAddress, wallet)

      const info = await registry.getOperatorInfo(wallet.address)
      if (!info.isActive && info.stake === 0n) {
        log.error('Not registered as operator')
        process.exit(1)
      }

      if (info.unbondRequestTime > 0n) {
        log.error('Cannot add stake while unbonding')
        process.exit(1)
      }

      const tokenAddress = await registry.stakingToken()
      const token = getERC20Contract(tokenAddress, wallet)
      const decimals = await token.decimals()
      const amount = parseUnits(options.amount, decimals)

      // Check balance
      const balance = await token.balanceOf(wallet.address)
      if (balance < amount) {
        log.error('Insufficient balance')
        process.exit(1)
      }

      // Approve and add stake
      log.info('Approving tokens...')
      const approveTx = await token.approve(config.registryAddress, amount)
      await approveTx.wait()
      log.tx(approveTx.hash)

      log.info('Adding stake...')
      const addTx = await registry.addStake(amount)
      await addTx.wait()
      log.tx(addTx.hash)

      const newInfo = await registry.getOperatorInfo(wallet.address)
      log.success(`Stake added. New total: ${formatStake(newInfo.stake, decimals)}`)
    } catch (err) {
      log.error(err instanceof Error ? err.message : 'Failed to add stake')
      process.exit(1)
    }
  })

const infoCommand = new Command('info')
  .description('Show stake information')
  .action(async function (this: Command) {
    try {
      const config = loadConfig(getParentOptions(this.parent!))
      const wallet = createWallet(config)
      const registry = getRegistryContract(config.registryAddress, wallet)

      const tokenAddress = await registry.stakingToken()
      const token = getERC20Contract(tokenAddress, wallet)
      const decimals = await token.decimals()
      const symbol = await token.symbol()
      const minStake = await registry.minStake()

      const info = await registry.getOperatorInfo(wallet.address)
      const balance = await token.balanceOf(wallet.address)

      console.log('')
      console.log('Stake Information')
      console.log('─'.repeat(40))
      console.log(`Current Stake:  ${formatStake(info.stake, decimals)} ${symbol}`)
      console.log(`Minimum Stake:  ${formatStake(minStake, decimals)} ${symbol}`)
      console.log(`Wallet Balance: ${formatStake(balance, decimals)} ${symbol}`)
    } catch (err) {
      log.error(err instanceof Error ? err.message : 'Failed to get stake info')
      process.exit(1)
    }
  })

export const stakeCommand = new Command('stake')
  .description('Manage operator stake')
  .addCommand(addCommand)
  .addCommand(infoCommand)
