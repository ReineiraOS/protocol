/**
 * Task type constants - keccak256 hashes of task type strings
 */
export const TASK_TYPES = {
  CCTP_RELAY: '0x7f590974bc33c0198dbfa46b88b7e202d51129d9e12c8181dc58fc3f234def67',
  CCTP_OUTBOUND_RELAY: 'CCTP_OUTBOUND_RELAY',
} as const

/**
 * Contract addresses for Arbitrum Sepolia.
 *
 * The on-chain operator stack (OperatorRegistry / TaskExecutor / FeeManager /
 * CCTPHandler) was removed — settlement is permissionless via the escrow
 * receiver's `settle(message, attestation)` entry point.
 */
export const CONTRACTS = {
  ARBITRUM_SEPOLIA: {
    ESCROW: '0xF50A9CF008a79CFCA39aa9a345aa06e8D12727E2',
    ESCROW_RECEIVER: '0xe0E6CC9Ee62Fa36b96eC4F50CDc462Fd14aa0fD3',
  },
} as const

export const MESSAGE_TRANSMITTER_V2 = {
  TESTNET: '0xE737e5cEBEEBa77EFE34D4aa090756590b1CE275',
} as const
