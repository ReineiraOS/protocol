import type { Network, NetworkAddresses } from "../types/index.js";

export const TESTNET_ADDRESSES: NetworkAddresses = {
  // Tokens
  confidentialUSDC: "0x42E47f9bA89712C317f60A72C81A610A2b68c48a",

  // Escrow
  escrow: "0xF50A9CF008a79CFCA39aa9a345aa06e8D12727E2",
  escrowReceiver: "0xe0E6CC9Ee62Fa36b96eC4F50CDc462Fd14aa0fD3",

  // Recourse
  policyRegistry: "0x17a3222BD2167C7620815CD6a1C8d215F11CAa25",
  coverageManager: "0x636084Da863569bd90c94C1C7a5180eBF8F88AAd",
  poolFactory: "0x278c43aB5B8726EbdFD6E7352c128aDA48269442",

  // Orchestration
  operatorRegistry: "0x5Ac3a3750e0a9f7d4ddBC0B52c3f13E8f927FB59",
  taskExecutor: "0x4D239335f39E585Bb75631C4683538EFC496a5EB",
  feeManager: "0x639f5cB99DcF9681A0461A1452c3845811d3308A",
  cctpHandler: "0x575186a64B9FC49E135A2440DC4A1395edc0F3aD",

  // External
  usdc: "0x75faf114eafb1BDbe2F0316DF893fd58CE46AA4d",
  cctpMessageTransmitter: "0xE737e5cEBEEBa77EFE34D4aa090756590b1CE275",
  trustedForwarder: "0x7ceA357B5AC0639F89F9e378a1f03Aa5005C0a25",
  governanceToken: "0xb847e041bB3bC78C3CD951286AbCa28593739D12",

  // Plain (non-FHE) — mainnet launch path. 2026-06-15 Arb Sepolia redeploy
  // (verified on Arbiscan; supersedes the 2026-06-14 plain addresses).
  plainEscrow: "0xAf4e9b2f19a2BF7CF05B7eAae20369FBE3823B8D",
  plainEscrowReceiver: "0x495b4E97C1983B79B926994D8278E06b9BbdC834",
  plainRecoursePool: "0xb07967Ac5d301C65C70Fe3C0B7B8513B15B23047",
  plainPoolFactory: "0x2AA20E195290426ad626F65C540FCE2A58DFF9AF",
  plainPolicyRegistry: "0x44A8314006E036047586bA90cD3FC153B8990361",
  plainCoverageManager: "0xE93191EE7C275E2C8a93FE9A6a2a67f2124daB8E",
};

const ADDRESSES_BY_NETWORK: Partial<Record<Network, NetworkAddresses>> = {
  testnet: TESTNET_ADDRESSES,
};

export function getAddresses(network: Network): NetworkAddresses {
  const addresses = ADDRESSES_BY_NETWORK[network];
  if (!addresses) {
    throw new Error(
      `Network "${network}" is not supported yet. Available: ${Object.keys(ADDRESSES_BY_NETWORK).join(", ")}`,
    );
  }
  return addresses;
}

// CCTP constants
export const CCTP_ETHEREUM_SEPOLIA = {
  domain: 0,
  usdc: "0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238",
  tokenMessenger: "0x8FE6B999Dc680CcFDD5Bf7EB0974218be2542DAA", // TokenMessengerV2
};

export const CCTP_BASE_SEPOLIA = {
  domain: 6,
  usdc: "0x036CbD53842c5426634e7929541eC2318f3dCF7e",
  tokenMessenger: "0x8FE6B999Dc680CcFDD5Bf7EB0974218be2542DAA", // TokenMessengerV2
};

export const CCTP_ARBITRUM_SEPOLIA_DOMAIN = 3;

// Chain IDs for coordinator submission
export const CHAIN_ID_ETHEREUM_SEPOLIA = 11155111;
export const CHAIN_ID_BASE_SEPOLIA = 84532;
export const CHAIN_ID_ARBITRUM_SEPOLIA = 421614;

// CCTP task type hash (keccak256 of the relay task)
export const CCTP_RELAY_TASK_TYPE =
  "0x7f590974bc33c0198dbfa46b88b7e202d51129d9e12c8181dc58fc3f234def67";
