# @reineira-os/sdk

TypeScript SDK for ReineiraOS — programmable confidential settlement on Arbitrum.

## Install

```bash
npm install @reineira-os/sdk
```

## Setup

```ts
import { ReineiraSDK } from "@reineira-os/sdk";

// From private key
const sdk = ReineiraSDK.create({
  network: "testnet",
  privateKey: process.env.PRIVATE_KEY!,
  rpcUrl: process.env.ARBITRUM_SEPOLIA_RPC!,
  coordinatorUrl: "https://coordinator.reineira.xyz", // optional — enables cross-chain
});

// From existing signer (wagmi, RainbowKit, MetaMask)
import { walletClientToSigner } from "@reineira-os/sdk";
const sdk = ReineiraSDK.create({
  network: "testnet",
  signer: walletClientToSigner(walletClient),
});

// FHE auto-initializes on first operation (~2-5s)
// Optional: warm up eagerly with progress callback
const sdk = ReineiraSDK.create({
  network: "testnet",
  privateKey: "0x...",
  rpcUrl: "...",
  onFHEInit: (status) => console.log("FHE:", status), // "starting" | "done" | "error"
});
```

## Escrow

### Create

```ts
// Simple
const escrow = await sdk.escrow.create({
  amount: sdk.usdc(1000),
  owner: "0xRecipient...",
});

// With condition resolver
const escrow = await sdk.escrow
  .build()
  .amount(sdk.usdc(1000))
  .owner("0xRecipient...")
  .condition("0xResolver...", encodedData)
  .create();
```

### Fund

```ts
// Approve first (explicit — for UIs with separate approval step)
await escrow.approve({ durationSeconds: 3600 });
await escrow.fund(sdk.usdc(1000));

// Or auto-approve in one step
await escrow.fund(sdk.usdc(1000), { autoApprove: true });

// Cross-chain from Ethereum Sepolia
const result = await escrow.fund(sdk.usdc(1000), {
  crossChain: {
    sourceRpc: process.env.ETH_SEPOLIA_RPC!,
    sourcePrivateKey: process.env.SOURCE_KEY!,
  },
});
// result.tx          — burn transaction on source chain
// result.relayTaskId — coordinator task ID (if coordinatorUrl set)

// Cross-chain + wait for operator settlement
const result = await escrow.fund(sdk.usdc(1000), {
  crossChain: { sourceRpc: "...", sourcePrivateKey: "..." },
  waitForSettlement: true,
  settlementTimeoutMs: 600_000,
});
// result.settlement.payer       — operator address
// result.settlement.blockNumber — settlement block
```

### Redeem

```ts
// Redeem to cUSDC (encrypted)
await escrow.redeem();

// Redeem + unwrap to plain USDC
await escrow.redeem({ unwrapTo: "0xRecipient..." });

// Batch redeem
await sdk.escrow.redeemMultiple([0n, 1n, 2n]);
await sdk.escrow.redeemMultiple([0n, 1n, 2n], { unwrapTo: "0xRecipient..." });
```

### Status

```ts
await escrow.exists(); // on-chain existence
await escrow.isFunded(); // EscrowFunded event emitted
await escrow.isConditionMet(); // resolver returns true (or no resolver)
await escrow.isRedeemable(); // exists + funded + condition met

// Wait for funding (event-driven)
const settlement = await escrow.waitForFunded(600_000);

// Poll until redeemable
await escrow.waitForRedeemable({ pollIntervalMs: 5000, timeoutMs: 300_000 });
```

### Existing Escrows

```ts
const escrow = sdk.escrow.get(42n);
await escrow.fund(sdk.usdc(100), { autoApprove: true });

const exists = await sdk.escrow.exists(42n);
const total = await sdk.escrow.total();
```

## Recourse

### Pool

```ts
const pool = await sdk.recourse.createPool({
  paymentToken: sdk.addresses.confidentialUSDC,
});
// pool.id, pool.address, pool.createTx.hash

await pool.addPolicy("0xPolicy...");
await pool.removePolicy("0xPolicy...");

// Stake / unstake
await pool.approve(); // explicit, or use autoApprove below
const { stakeId, tx } = await pool.stake(sdk.usdc(10000), { autoApprove: true });
await pool.unstake(stakeId);

// Queries
const count = await sdk.recourse.poolCount();
const pool = await sdk.recourse.getPool(0n);
```

### Coverage

```ts
const coverage = await sdk.recourse.purchaseCoverage({
  pool: pool.address,
  policy: "0xPolicy...",
  escrowId: escrow.id,
  coverageAmount: sdk.usdc(50000),
  expiry: Math.floor(Date.now() / 1000) + 86400 * 30,
});
// coverage.id, coverage.createTx.hash

const status = await coverage.status(); // Active, Disputed, Claimed, Expired
await coverage.dispute("0xProofBytes...");

// Get existing coverage
const coverage = sdk.recourse.getCoverage(42n);
```

### Escrow + Recourse (one flow)

```ts
const escrow = await sdk.escrow
  .build()
  .amount(sdk.usdc(50000))
  .owner("0xRecipient...")
  .condition("0xResolver...")
  .recourse({
    pool: pool.address,
    policy: "0xPolicy...",
    coverageAmount: sdk.usdc(50000),
    expiry: Math.floor(Date.now() / 1000) + 86400 * 30,
  })
  .create();

escrow.coverage.id; // coverage was purchased atomically
```

## Cross-Chain (CCTP)

```ts
// Check operator network health
const health = await sdk.bridge.checkHealth();
// health.reachable, health.connectedOperators, health.operators

// Submit external burn tx to coordinator
const taskId = await sdk.bridge.submitToCoordinator("0xBurnTxHash...");
```

## Events

```ts
// Real-time listeners (returns unsubscribe function)
const unsub = sdk.events.onEscrowCreated((escrowId) => { ... });
const unsub = sdk.events.onEscrowFunded((escrowId, payer) => { ... }, escrowId);
const unsub = sdk.events.onEscrowRedeemed((escrowId) => { ... });
const unsub = sdk.events.onCoveragePurchased((coverageId) => { ... });
const unsub = sdk.events.onDisputeFiled((coverageId) => { ... });
const unsub = sdk.events.onPoolCreated((poolId, pool, underwriter) => { ... });

// Query past events
const logs = await sdk.events.queryEscrowEvents("EscrowCreated", fromBlock);

// Cleanup
sdk.events.removeAllListeners();
```

## Balances & Approval

```ts
const bal = await sdk.balances();
// bal.usdc  — plain USDC (6 decimals)
// bal.eth   — native ETH (for gas)
// bal.confidentialUSDC — FHE handle (not plaintext)

await sdk.isOperatorApproved(sdk.addresses.escrow);
await escrow.isApproved();
```

## Amount Helpers

```ts
sdk.usdc(1000); // 1000_000000n
sdk.usdc(0.5); // 500000n
sdk.usdc("1000"); // 1000_000000n

sdk.formatUsdc(1000_000000n); // "1,000.00"
sdk.formatUsdc(500000n); // "0.50"

// Also available as standalone imports
import { usdc, formatUsdc } from "@reineira-os/sdk";
```

## Errors

```ts
import {
  ApprovalRequiredError, // fund/stake without approval
  ValidationError, // invalid params
  TransactionFailedError, // on-chain revert (has .txHash)
  EscrowNotFoundError, // escrow doesn't exist
  TimeoutError, // waitForFunded/waitForRedeemable timeout
  FHEInitError, // cofhejs initialization failed
  EncryptionError, // FHE encryption failed
  CoverageNotActiveError, // dispute on non-active coverage
} from "@reineira-os/sdk";

try {
  await escrow.fund(sdk.usdc(100));
} catch (err) {
  if (err instanceof ApprovalRequiredError) {
    // err.spender, err.holder, err.code === "APPROVAL_REQUIRED"
    await escrow.approve();
    await escrow.fund(sdk.usdc(100));
  }
  if (err instanceof TransactionFailedError) {
    // err.txHash — link to block explorer
    // err.cause  — underlying RPC error
  }
}
```

## Transaction Results

Every mutation returns `TransactionResult`:

```ts
interface TransactionResult {
  hash: string;
  blockNumber: number;
  gasUsed: bigint;
}
```

Instances created by mutations carry `.createTx`:

```ts
escrow.createTx.hash;
pool.createTx.hash;
coverage.createTx.hash;
```

## Local Development

```ts
import { ReineiraSDK, injectCofhe } from "@reineira-os/sdk";

// For local FHE mocks: inject the CoFHE client before creating the SDK
const cofhe = require("@cofhe/sdk/node");
injectCofhe(cofhe);

const sdk = ReineiraSDK.create({
  network: "testnet",
  signer: localSigner,
  addresses: localDeploymentAddresses, // override deployed addresses
});
```

## License

MIT
