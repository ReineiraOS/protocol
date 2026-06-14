import chalk from 'chalk'
import { formatUnits } from 'ethers'

export function formatStake(amount: bigint, decimals = 18): string {
  return formatUnits(amount, decimals)
}

export function formatTimestamp(ts: bigint): string {
  if (ts === 0n) return 'N/A'
  return new Date(Number(ts) * 1000).toISOString()
}

export function formatDuration(seconds: number): string {
  const days = Math.floor(seconds / 86400)
  const hours = Math.floor((seconds % 86400) / 3600)
  const mins = Math.floor((seconds % 3600) / 60)
  if (days > 0) return `${days}d ${hours}h`
  if (hours > 0) return `${hours}h ${mins}m`
  return `${mins}m`
}

export const log = {
  info: (msg: string) => console.log(chalk.blue('ℹ'), msg),
  success: (msg: string) => console.log(chalk.green('✓'), msg),
  warn: (msg: string) => console.log(chalk.yellow('⚠'), msg),
  error: (msg: string) => console.log(chalk.red('✗'), msg),
  tx: (hash: string) => console.log(chalk.gray(`  tx: ${hash}`)),
}
