// Contract ABIs extracted from compiled Foundry artifacts.
// Only includes functions/events the SDK uses — not full ABIs.

export const CONFIDENTIAL_ESCROW_ABI = [
  "function create(tuple(uint256 ctHash, uint8 securityZone, uint8 utype, bytes signature) encryptedOwner, tuple(uint256 ctHash, uint8 securityZone, uint8 utype, bytes signature) encryptedAmount, address resolver, bytes resolverData) returns (uint256 escrowId)",
  "function fund(uint256 escrowId, tuple(uint256 ctHash, uint8 securityZone, uint8 utype, bytes signature) encryptedPayment)",
  "function fundFrom(uint256 escrowId, uint256 amount)",
  "function redeem(uint256 escrowId)",
  "function redeemMultiple(uint256[] escrowIds)",
  "function exists(uint256 escrowId) view returns (bool)",
  "function total() view returns (uint256 count)",
  "function getOwner(uint256 escrowId) view returns (uint256 owner)",
  "function getAmount(uint256 escrowId) view returns (uint256 amount)",
  "function getPaidAmount(uint256 escrowId) view returns (uint256 paidAmount)",
  "function getRedeemedStatus(uint256 escrowId) view returns (uint256 isRedeemed)",
  "function getCaller(uint256 escrowId) view returns (uint256)",
  "function paymentToken() view returns (address)",
  "function getConditionResolver(uint256 escrowId) view returns (address)",
  "function setUnderwriterFee(uint256 escrowId, uint256 holder, uint256 effectiveBps, address recipient)",
  "function setCoverageManager(address coverageManager)",
  "function getFee(uint256 escrowId, uint8 kind) view returns (uint256 bps, address recipient, bool set)",
  "function getTotalStampedBps(uint256 escrowId) view returns (uint256)",
  "event EscrowCreated(uint256 indexed escrowId)",
  "event EscrowFunded(uint256 indexed escrowId, address indexed payer)",
  "event EscrowRedeemed(uint256 indexed escrowId)",
  "event EscrowBatchRedeemed(uint256[] escrowIds)",
  "event FeeStamped(uint256 indexed escrowId, uint8 indexed kind, uint16 bps, address recipient)",
  "event FeeDistributed(uint256 indexed escrowId, uint8 indexed kind, uint256 amount, address recipient)",
  "event CoverageManagerSet(address indexed coverageManager)",
] as const;

export const CCTP_ESCROW_RECEIVER_ABI = [
  "function settle(bytes message, bytes attestation)",
  "function buildHookData(uint256 escrowId) pure returns (bytes)",
  "event EscrowSettled(uint256 indexed escrowId, address indexed relayer, uint256 usdcReceived, uint64 confidentialAmountPaid)",
] as const;

export const FHERC20_ABI = [
  "function setOperator(address operator, uint48 until)",
  "function isOperator(address holder, address spender) view returns (bool)",
  "function confidentialBalanceOf(address account) view returns (uint256)",
  "function confidentialTransfer(address to, tuple(uint256 ctHash, uint8 securityZone, uint8 utype, bytes signature) inValue) returns (uint256 transferred)",
  "function confidentialTransfer(address to, uint256 value) returns (uint256 transferred)",
  "function confidentialTransferFrom(address from, address to, uint256 value) returns (uint256 transferred)",
  "function balanceOf(address account) view returns (uint256)",
  "function decimals() view returns (uint8)",
  "function name() view returns (string)",
  "function symbol() view returns (string)",
  "function totalSupply() view returns (uint256)",
  "function approve(address spender, uint256 value) pure returns (bool)",
  "function transfer(address to, uint256 value) pure returns (bool)",
  "function transferFrom(address from, address to, uint256 value) pure returns (bool)",
  "event OperatorSet(address indexed holder, address indexed operator, uint48 until)",
  "event ConfidentialTransfer(address indexed from, address indexed to, uint256 value_hash)",
] as const;

export const COVERAGE_MANAGER_ABI = [
  "function purchaseCoverage(tuple(uint256 ctHash, uint8 securityZone, uint8 utype, bytes signature) encryptedHolder, address pool, address policy, uint256 escrowId, tuple(uint256 ctHash, uint8 securityZone, uint8 utype, bytes signature) encryptedCoverageAmount, uint256 coverageExpiry, bytes policyData, bytes riskProof) returns (uint256 coverageId)",
  "function purchaseCoverage(tuple(uint256 ctHash, uint8 securityZone, uint8 utype, bytes signature) encryptedHolder, address pool, address policy, uint256 escrowId, tuple(uint256 ctHash, uint8 securityZone, uint8 utype, bytes signature) encryptedCoverageAmount, uint256 coverageExpiry, bytes policyData, bytes riskProof, tuple(address pool, address invitee, uint256 maxUses, uint256 deadline, uint256 inviteId) invite, bytes inviteSig) returns (uint256 coverageId)",
  "function dispute(uint256 coverageId, bytes disputeProof)",
  "function revokeInvite(address pool, bytes32 digest)",
  "function coverageStatus(uint256 coverageId) view returns (uint8)",
  "function escrow() view returns (address)",
  "function poolFactory() view returns (address)",
  "function usedCount(bytes32 digest) view returns (uint256)",
  "function isInviteRevoked(bytes32 digest) view returns (bool)",
  "event CoveragePurchased(uint256 indexed coverageId)",
  "event DisputeFiled(uint256 indexed coverageId)",
  "event CoverageClaimed(uint256 indexed coverageId)",
  "event CoverageExpired(uint256 indexed coverageId)",
  "event InviteConsumed(address indexed pool, bytes32 indexed digest, address indexed invitee)",
  "event InviteRevoked(address indexed pool, bytes32 indexed digest, address by)",
] as const;

export const RECOURSE_POOL_ABI = [
  "function stake(tuple(uint256 ctHash, uint8 securityZone, uint8 utype, bytes signature) encryptedAmount) returns (uint256 stakeId)",
  "function unstake(uint256 stakeId)",
  "function addPolicy(address policy)",
  "function removePolicy(address policy)",
  "function isPolicy(address policy) view returns (bool)",
  // payClaim: amount & return are euint64 (encrypted), encoded as uint256
  "function payClaim(uint256 coverageId, uint256 amount) returns (uint256 actualPayout)",
  "function creator() view returns (address)",
  "function manager() view returns (address)",
  "function guardian() view returns (address)",
  "function isOpen() view returns (bool)",
  "function domainSeparator() view returns (bytes32)",
  "function transferManager(address newManager)",
  "function paymentToken() view returns (address)",
  "function coverageManager() view returns (address)",
  "function claimRewards(uint256 stakeId)",
  // These return euint64 encrypted handles (uint256), NOT plaintext values
  "function totalLiquidity() view returns (uint256)",
  "function stakedAmount(uint256 stakeId) view returns (uint256)",
  "function pendingRewards(uint256 stakeId) view returns (uint256)",
  "event Staked(uint256 indexed stakeId)",
  "event Unstaked(uint256 indexed stakeId)",
  "event PolicyAdded(address indexed policy)",
  "event PolicyRemoved(address indexed policy)",
  "event ClaimPaid()",
  "event PremiumReceived()",
  "event RewardsClaimed(uint256 indexed stakeId)",
  "event ManagerTransferred(address indexed previous, address indexed next)",
] as const;

export const POOL_FACTORY_ABI = [
  "function createPool(address paymentToken, address initialManager, address guardian, bool isOpen) returns (uint256 poolId, address pool)",
  "function pool(uint256 poolId) view returns (address)",
  "function poolCount() view returns (uint256)",
  "function isPool(address) view returns (bool)",
  "event PoolCreated(uint256 indexed poolId, address indexed pool, address indexed creator, address manager, address guardian, bool isOpen)",
] as const;

export const POLICY_REGISTRY_ABI = [
  "function registerPolicy(address policy) returns (uint256 policyId)",
  "function isPolicy(address policy) view returns (bool)",
  "function policy(uint256 policyId) view returns (address)",
  "function policyCount() view returns (uint256)",
  "event PolicyRegistered(uint256 indexed policyId, address indexed policy, address indexed creator)",
] as const;

export const CONDITION_RESOLVER_ABI = [
  "function isConditionMet(uint256 escrowId) view returns (bool)",
] as const;

// CCTP TokenMessenger ABI (Ethereum Sepolia source chain)
export const CCTP_TOKEN_MESSENGER_ABI = [
  "function depositForBurnWithHook(uint256 amount, uint32 destinationDomain, bytes32 mintRecipient, address burnToken, bytes32 destinationCaller, uint256 maxFee, uint32 minFinalityThreshold, bytes hookData) returns (uint64)",
] as const;

// Standard ERC20 ABI (for USDC on source chain)
export const ERC20_ABI = [
  "function approve(address spender, uint256 amount) returns (bool)",
  "function allowance(address owner, address spender) view returns (uint256)",
  "function balanceOf(address account) view returns (uint256)",
  "function transfer(address to, uint256 amount) returns (bool)",
] as const;

// Plain (non-FHE) contract ABIs — mainnet launch path

export const PLAIN_ESCROW_ABI = [
  "function create(address owner, uint256 amount, address resolver, bytes resolverData) returns (uint256 escrowId)",
  "function fund(uint256 escrowId, uint256 amount)",
  "function redeem(uint256 escrowId)",
  "function redeemMultiple(uint256[] escrowIds)",
  "function exists(uint256 escrowId) view returns (bool)",
  "function total() view returns (uint256 count)",
  "function getOwner(uint256 escrowId) view returns (address)",
  "function getAmount(uint256 escrowId) view returns (uint256)",
  "function getPaidAmount(uint256 escrowId) view returns (uint256)",
  "function getRedeemedStatus(uint256 escrowId) view returns (bool)",
  "function paymentToken() view returns (address)",
  "function getConditionResolver(uint256 escrowId) view returns (address)",
  "function setUnderwriterFee(uint256 escrowId, address holder, uint16 effectiveBps, address recipient)",
  "function setCoverageManager(address coverageManager)",
  "function getFee(uint256 escrowId, uint8 kind) view returns (uint16 bps, address recipient, bool set)",
  "function getTotalStampedBps(uint256 escrowId) view returns (uint16)",
  "event EscrowCreated(uint256 indexed escrowId)",
  "event EscrowFunded(uint256 indexed escrowId, address indexed payer)",
  "event EscrowRedeemed(uint256 indexed escrowId)",
  "event EscrowBatchRedeemed(uint256[] escrowIds)",
  "event FeeStamped(uint256 indexed escrowId, uint8 indexed kind, uint16 bps, address recipient)",
  "event FeeDistributed(uint256 indexed escrowId, uint8 indexed kind, uint256 amount, address recipient)",
  "event CoverageManagerSet(address indexed coverageManager)",
] as const;

export const PLAIN_CCTP_ESCROW_RECEIVER_ABI = [
  "function settle(bytes message, bytes attestation)",
  "function buildHookData(uint256 escrowId) pure returns (bytes)",
  "event EscrowSettled(uint256 indexed escrowId, address indexed relayer, uint256 usdcReceived, uint256 amountPaid)",
] as const;

export const PLAIN_RECOURSE_POOL_ABI = [
  "function stake(uint256 amount) returns (uint256 stakeId)",
  "function unstake(uint256 stakeId)",
  "function addPolicy(address policy)",
  "function removePolicy(address policy)",
  "function isPolicy(address policy) view returns (bool)",
  "function payClaim(uint256 coverageId, uint256 amount) returns (uint256 actualPayout)",
  "function receivePremium(uint256 coverageId, uint256 premium)",
  "function creator() view returns (address)",
  "function manager() view returns (address)",
  "function guardian() view returns (address)",
  "function isOpen() view returns (bool)",
  "function domainSeparator() view returns (bytes32)",
  "function transferManager(address newManager)",
  "function paymentToken() view returns (address)",
  "function coverageManager() view returns (address)",
  "function totalLiquidity() view returns (uint256)",
  "function stakedAmount(uint256 stakeId) view returns (uint256)",
  "function pendingRewards(uint256 stakeId) view returns (uint256)",
  "function claimRewards(uint256 stakeId)",
  "function claimPremiums(uint256 amount)",
  "event Staked(uint256 indexed stakeId)",
  "event Unstaked(uint256 indexed stakeId)",
  "event PolicyAdded(address indexed policy)",
  "event PolicyRemoved(address indexed policy)",
  "event ClaimPaid()",
  "event PremiumReceived()",
  "event RewardsClaimed(uint256 indexed stakeId)",
  "event ManagerTransferred(address indexed previous, address indexed next)",
] as const;

export const PLAIN_COVERAGE_MANAGER_ABI = [
  "function purchaseCoverage(address holder, address pool, address policy, uint256 escrowId, uint256 coverageAmount, uint256 coverageExpiry, bytes policyData, bytes riskProof) returns (uint256 coverageId)",
  "function purchaseCoverage(address holder, address pool, address policy, uint256 escrowId, uint256 coverageAmount, uint256 coverageExpiry, bytes policyData, bytes riskProof, tuple(address pool, address invitee, uint256 maxUses, uint256 deadline, uint256 inviteId) invite, bytes inviteSig) returns (uint256 coverageId)",
  "function dispute(uint256 coverageId, bytes disputeProof)",
  "function revokeInvite(address pool, bytes32 digest)",
  "function coverageStatus(uint256 coverageId) view returns (uint8)",
  "function escrow() view returns (address)",
  "function poolFactory() view returns (address)",
  "function usedCount(bytes32 digest) view returns (uint256)",
  "function isInviteRevoked(bytes32 digest) view returns (bool)",
  "event CoveragePurchased(uint256 indexed coverageId)",
  "event DisputeFiled(uint256 indexed coverageId)",
  "event CoverageClaimed(uint256 indexed coverageId)",
  "event CoverageExpired(uint256 indexed coverageId)",
  "event InviteConsumed(address indexed pool, bytes32 indexed digest, address indexed invitee)",
  "event InviteRevoked(address indexed pool, bytes32 indexed digest, address by)",
] as const;
