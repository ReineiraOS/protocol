import { Command } from 'commander'
import { parseUnits } from 'ethers'
import { loadConfig, getParentOptions } from '../utils/config'
import { createWallet } from '../utils/provider'
import { getRegistryContract, getERC20Contract } from '../utils/contracts'
import { log, formatStake } from '../utils/format'

export const registerCommand = new Command('register')
  .description('Register as an operator with initial stake')
  .requiredOption('--stake <amount>', 'Stake amount (in token units)')
  .action(async function (this: Command, options: { stake: string }) {
    try {
      const config = loadConfig(getParentOptions(this))
      const wallet = createWallet(config)
      const registry = getRegistryContract(config.registryAddress, wallet)

      // Check if already registered
      const info = await registry.getOperatorInfo(wallet.address)
      if (info.isActive) {
        log.error('Already registered as operator')
        process.exit(1)
      }

      // Get staking token and min stake
      const tokenAddress = await registry.stakingToken()
      const minStake = await registry.minStake()
      const token = getERC20Contract(tokenAddress, wallet)
      const decimals = await token.decimals()

      const stakeAmount = parseUnits(options.stake, decimals)

      if (stakeAmount < minStake) {
        log.error(`Stake must be at least ${formatStake(minStake, decimals)} tokens`)
        process.exit(1)
      }

      // Check balance
      const balance = await token.balanceOf(wallet.address)
      if (balance < stakeAmount) {
        log.error(`Insufficient balance: ${formatStake(balance, decimals)} < ${options.stake}`)
        process.exit(1)
      }

      // Approve tokens
      log.info('Approving tokens...')
      const approveTx = await token.approve(config.registryAddress, stakeAmount)
      await approveTx.wait()
      log.tx(approveTx.hash)

      // Register
      log.info('Registering operator...')
      const registerTx = await registry.registerOperator(stakeAmount)
      await registerTx.wait()
      log.tx(registerTx.hash)

      log.success(`Registered as operator with ${options.stake} stake`)
      log.info(`Address: ${wallet.address}`)
    } catch (err) {
      log.error(err instanceof Error ? err.message : 'Registration failed')
      process.exit(1)
    }
  })
