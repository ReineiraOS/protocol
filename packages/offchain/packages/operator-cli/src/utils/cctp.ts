import { Contract, Wallet } from 'ethers'
import TokenMessengerV2ABI from '../abis/TokenMessengerV2.json'
import MessageTransmitterV2ABI from '../abis/MessageTransmitterV2.json'
import ERC20ABI from '../abis/ERC20.json'

export const DOMAINS = {
  ETHEREUM_SEPOLIA: 0,
  ARBITRUM_SEPOLIA: 3,
  BASE_SEPOLIA: 6,
} as const

export const CCTP_ADDRESSES = {
  ethereumSepolia: {
    usdc: '0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238',
    tokenMessenger: '0x8FE6B999Dc680CcFDD5Bf7EB0974218be2542DAA', // TokenMessengerV2
    messageTransmitter: '0xE737e5cEBEEBa77EFE34D4aa090756590b1CE275',
  },
  arbitrumSepolia: {
    usdc: '0x75faf114eafb1BDbe2F0316DF893fd58CE46AA4d',
    tokenMessenger: '0x8FE6B999Dc680CcFDD5Bf7EB0974218be2542DAA', // TokenMessengerV2
    messageTransmitter: '0xE737e5cEBEEBa77EFE34D4aa090756590b1CE275',
  },
  baseSepolia: {
    usdc: '0x036CbD53842c5426634e7929541eC2318f3dCF7e',
    tokenMessenger: '0x8FE6B999Dc680CcFDD5Bf7EB0974218be2542DAA', // TokenMessengerV2
    messageTransmitter: '0xE737e5cEBEEBa77EFE34D4aa090756590b1CE275',
  },
  // Contracts deployed on Arbitrum Sepolia (destination chain)
  arbitrumSepoliaContracts: {
    escrowReceiver: '0x67AE0C5fE86716441B38b73A66F21c6aC8e338d0',
    escrow: '0xbe1eEB78504B71beEE1b33D3E3D367A2F9a549A6',
  },
} as const

export function getUSDC(address: string, wallet: Wallet): Contract {
  return new Contract(address, ERC20ABI, wallet)
}

export function getTokenMessengerV2(address: string, wallet: Wallet): Contract {
  return new Contract(address, TokenMessengerV2ABI, wallet)
}

export function getMessageTransmitterV2(address: string, wallet: Wallet): Contract {
  return new Contract(address, MessageTransmitterV2ABI, wallet)
}

interface CCTPMessage {
  message: string
  eventNonce: string
  attestation: string
  cctpVersion: number
  status: string
  decodedMessage?: {
    sourceDomain: string
    destinationDomain: string
    nonce: string
    sender: string
    recipient: string
    destinationCaller: string
    messageBody: string
  }
}

export interface AttestationResponse {
  message: string
  attestation: string
  status: string
  eventNonce: string
}

export async function waitForAttestation(
  txHash: string,
  sourceDomain: number = DOMAINS.ETHEREUM_SEPOLIA,
  timeoutMs = 300000,
  pollIntervalMs = 2000,
): Promise<AttestationResponse> {
  const baseUrl = 'https://iris-api-sandbox.circle.com'
  const startTime = Date.now()

  while (Date.now() - startTime < timeoutMs) {
    try {
      const response = await fetch(
        `${baseUrl}/v2/messages/${sourceDomain}?transactionHash=${txHash}`,
      )

      if (!response.ok) {
        await sleep(pollIntervalMs)
        continue
      }

      const data = (await response.json()) as {
        messages?: CCTPMessage[]
      }

      if (data.messages && data.messages.length > 0) {
        const msg = data.messages[0]
        const elapsed = Math.floor((Date.now() - startTime) / 1000)
        process.stdout.write(`\r  Status: ${msg.status} (${elapsed}s elapsed)`)

        // Check if attestation is ready (not PENDING)
        if (msg.attestation && msg.attestation !== 'PENDING') {
          console.log() // New line after status updates
          return {
            message: msg.message,
            attestation: msg.attestation,
            status: msg.status,
            eventNonce: msg.eventNonce,
          }
        }
      }
    } catch {
      // Ignore errors, keep polling
    }

    await sleep(pollIntervalMs)
  }

  throw new Error('Attestation timeout')
}

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms))
}
