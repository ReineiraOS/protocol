export { ReineiraSDK } from "./sdk.js";

// Modules
export { EscrowModule } from "./modules/escrow.js";
export { EscrowInstance } from "./modules/escrow-instance.js";
export { EscrowBuilder } from "./modules/escrow-builder.js";
export { RecourseModule } from "./modules/recourse.js";
export { PoolInstance, type StakeResult } from "./modules/pool-instance.js";
export { CoverageInstance, CoverageStatus } from "./modules/coverage-instance.js";
export { BridgeModule, type CoordinatorHealth } from "./modules/bridge.js";

// Plain (non-FHE) modules — mainnet launch path
export { PlainEscrowModule } from "./modules/escrow-plain.js";
export { PlainEscrowInstance, type PlainFundOptions } from "./modules/escrow-plain-instance.js";
export { PlainRecourseModule } from "./modules/recourse-plain.js";
export {
  PlainPoolInstance,
  type PlainStakeOptions,
  type PlainStakeResult,
} from "./modules/pool-plain-instance.js";
export { PlainCoverageInstance } from "./modules/coverage-plain-instance.js";
export {
  EventsModule,
  type Unsubscribe,
  type EscrowEventName,
  type RecourseEventName,
} from "./modules/events.js";

// Crypto
export { FHEClient, injectCofhe } from "./crypto/fhe.js";

// Types
export type {
  SDKConfig,
  SDKConfigWithKey,
  SDKConfigWithSigner,
  Network,
  CreateEscrowParams,
  RecourseParams,
  FundOptions,
  FundResult,
  CrossChainConfig,
  SettlementResult,
  BridgeBurnResult,
  PurchaseCoverageParams,
  CreatePoolParams,
  PollOptions,
  EscrowInfo,
  ApprovalOptions,
  NetworkAddresses,
  TransactionResult,
  TokenBalances,
  CreatePlainEscrowParams,
  CreatePlainPoolParams,
  PurchasePlainCoverageParams,
  CoverageInvite,
} from "./types/index.js";
export { PlainCoverageStatus } from "./types/index.js";

// Errors
export {
  ReineiraError,
  FHEInitError,
  EncryptionError,
  EscrowNotFoundError,
  InsufficientFundsError,
  TransactionFailedError,
  ConditionNotMetError,
  CoverageNotActiveError,
  ValidationError,
  TimeoutError,
  ApprovalRequiredError,
} from "./errors/index.js";

// Constants
export { getAddresses, TESTNET_ADDRESSES } from "./constants/addresses.js";

// Utils
export { encodeHookData, padAddress, encodeResolverData } from "./utils/encoding.js";
export { pollUntil } from "./utils/polling.js";
export { usdc, formatUsdc } from "./utils/amounts.js";
export { walletClientToSigner, publicClientToProvider } from "./utils/viem.js";
