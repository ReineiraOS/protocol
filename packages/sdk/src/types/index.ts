import type { ethers } from "ethers";

export type Network = "testnet" | "mainnet";

/** Common options shared by all config shapes. */
export interface SDKConfigBase {
  network: Network;
  /**
   * Override deployed contract addresses. Useful for local/test environments.
   * Any provided fields override the defaults for the selected network.
   */
  addresses?: Partial<NetworkAddresses>;
  /**
   * Coordinator URL for operator relay (CCTP settlement).
   * When set, fund() with crossChain auto-submits the burn tx to the coordinator.
   */
  coordinatorUrl?: string;
  /**
   * Called during FHE initialization with status updates.
   * FHE init takes 2-5 seconds — use this to show a loading indicator.
   */
  onFHEInit?: (status: "starting" | "done" | "error") => void;
}

/** Config using a private key — SDK creates provider + signer for you. */
export interface SDKConfigWithKey extends SDKConfigBase {
  privateKey: string;
  rpcUrl: string;
}

/** Config using an existing signer — for wagmi, RainbowKit, MetaMask, etc. */
export interface SDKConfigWithSigner extends SDKConfigBase {
  signer: ethers.Signer;
  /** Optional — if omitted, derived from signer.provider. */
  provider?: ethers.Provider;
}

export type SDKConfig = SDKConfigWithKey | SDKConfigWithSigner;

// ─── Escrow ─────────────────────────────────────────────────

/** Params for the sdk.escrow.create() shorthand. */
export interface CreateEscrowParams {
  /** Amount in USDC base units (6 decimals). 1 USDC = 1_000000n. Use sdk.usdc(1000) for convenience. */
  amount: bigint;
  /** Recipient address. */
  owner: string;
  /** Condition resolver address. Omit for unconditional escrow. */
  resolver?: string;
  /** ABI-encoded data passed to resolver.onConditionSet(). */
  resolverData?: string;
  /** Attach recourse coverage at creation time. */
  recourse?: RecourseParams;
}

export interface RecourseParams {
  pool: string;
  policy: string;
  coverageAmount: bigint;
  expiry: number;
  policyData?: string;
  riskProof?: string;
}

// ─── Funding ────────────────────────────────────────────────

/** Options for escrow.fund(). */
export interface FundOptions {
  /**
   * If true, automatically approve the contract as operator if not already approved.
   * If false (default), throws ApprovalRequiredError when approval is missing.
   */
  autoApprove?: boolean;

  /**
   * Cross-chain funding config. When present, funds via CCTP from a source chain
   * instead of locally. Operators handle attestation and settlement.
   */
  crossChain?: CrossChainConfig;

  /**
   * If true AND crossChain is set, blocks until the operator settles the escrow.
   * Returns a FundResult with settlement info.
   */
  waitForSettlement?: boolean;

  /** Timeout in ms for settlement waiting. Defaults to 600_000 (10 min). */
  settlementTimeoutMs?: number;
}

/** Source chain config for cross-chain funding via CCTP. */
export interface CrossChainConfig {
  /** RPC URL for the source chain (e.g. Ethereum Sepolia). */
  sourceRpc: string;
  /** Private key for the source chain wallet. Required if sourceSigner is not provided. */
  sourcePrivateKey?: string;
  /** Ethers signer connected to the source chain. Takes precedence over sourcePrivateKey. */
  sourceSigner?: ethers.Signer;
}

/** Result of escrow.fund(). Shape depends on whether crossChain was used. */
export interface FundResult {
  /** Transaction hash and receipt for the funding tx (local) or burn tx (cross-chain). */
  tx: TransactionResult;
  /** Relay task ID from the coordinator. Only set for cross-chain with coordinator configured. */
  relayTaskId?: string;
  /** Settlement info. Only set when crossChain + waitForSettlement: true. */
  settlement?: SettlementResult;
  /**
   * Wait for settlement. Only available for cross-chain funding.
   * Listens for EscrowFunded event on the destination chain.
   */
  waitForSettlement?: (timeoutMs?: number) => Promise<SettlementResult>;
}

/** Result returned when cross-chain settlement completes. */
export interface SettlementResult {
  /** Address of the operator/relayer that settled the escrow. */
  payer: string;
  /** Block number of the settlement transaction. */
  blockNumber: number;
}

/** @internal — bridge module params */
export interface BridgeBurnResult {
  burnTx: TransactionResult;
  relayTaskId?: string;
}

// ─── Recourse ──────────────────────────────────────────────

export interface PurchaseCoverageParams {
  pool: string;
  policy: string;
  escrowId: bigint;
  coverageAmount: bigint;
  expiry: number;
  policyData?: string;
  riskProof?: string;
}

export interface CreatePoolParams {
  paymentToken: string;
  /** Optional Pool Manager address. Defaults to the caller (Creator) when omitted. */
  initialManager?: string;
  /** Optional Guardian address. Zero address allowed; no in-pool powers in v1. */
  guardian?: string;
  /** True for open pools (any buyer). False for private (voucher-gated). Defaults to true. */
  isOpen?: boolean;
}

export interface CoverageInvite {
  pool: string;
  invitee: string;
  maxUses: bigint;
  deadline: bigint;
  inviteId: bigint;
}

export interface PollOptions {
  pollIntervalMs?: number;
  timeoutMs?: number;
}

export interface EscrowInfo {
  exists: boolean;
  escrowId: bigint;
}

/** Options for operator approval. */
export interface ApprovalOptions {
  /** Approval duration in seconds. Defaults to 1 year. */
  durationSeconds?: number;
}

export interface NetworkAddresses {
  confidentialUSDC: string;
  escrow: string;
  escrowReceiver: string;
  policyRegistry: string;
  coverageManager: string;
  poolFactory: string;
  usdc: string;
  cctpMessageTransmitter: string;
  trustedForwarder: string;
  governanceToken: string;

  /** Plain (non-FHE) contract addresses — mainnet launch path */
  plainEscrow: string;
  plainEscrowReceiver: string;
  plainRecoursePool: string;
  plainPoolFactory: string;
  plainPolicyRegistry: string;
  plainCoverageManager: string;
}

// ─── Plain SDK ──────────────────────────────────────────────

export interface CreatePlainEscrowParams {
  /** Amount in USDC base units (6 decimals). */
  amount: bigint;
  /** Recipient address. */
  owner: string;
  /** Optional condition resolver address. */
  resolver?: string;
  /** ABI-encoded data passed to the resolver. */
  resolverData?: string;
}

export interface CreatePlainPoolParams {
  paymentToken: string;
  /** Optional Pool Manager address. Defaults to the caller (Creator) when omitted. */
  initialManager?: string;
  /** Optional Guardian address. Zero address allowed; no in-pool powers in v1. */
  guardian?: string;
  /** True for open pools (any buyer). False for private (voucher-gated). Defaults to true. */
  isOpen?: boolean;
}

export interface PurchasePlainCoverageParams {
  holder: string;
  pool: string;
  policy: string;
  escrowId: bigint;
  coverageAmount: bigint;
  expiry: number;
  policyData?: string;
  riskProof?: string;
  /** EIP-712 coverage invite. Required when buying from a private pool. */
  invite?: CoverageInvite;
  /** Manager's signature over the invite. Required when invite is provided. */
  inviteSig?: string;
}

export enum PlainCoverageStatus {
  None = 0,
  Active = 1,
  Expired = 2,
  Claimed = 3,
}

/** Returned from all state-changing SDK methods. */
export interface TransactionResult {
  /** Transaction hash */
  hash: string;
  /** Block number the tx was included in */
  blockNumber: number;
  /** Gas used by the transaction */
  gasUsed: bigint;
}

/** Token balance info for a wallet. */
export interface TokenBalances {
  /**
   * Encrypted balance handle for Confidential USDC.
   * This is an FHE ciphertext handle, not a plaintext amount.
   * A non-zero value indicates the account has interacted with cUSDC,
   * but the actual balance is encrypted and cannot be read without a permit.
   */
  confidentialUSDC: bigint;
  /** Plain USDC balance on Arbitrum (in 6-decimal units). */
  usdc: bigint;
  /** Native ETH balance (for gas). */
  eth: bigint;
}
