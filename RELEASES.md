# Release Notes

ReineiraOS is programmable, confidential settlement infrastructure for stablecoins —
escrow, recourse (on‑chain insurance), and an operator orchestration network, on
Arbitrum with Fhenix FHE and Circle CCTP V2.

---

## v1.0.0 — First public release

**Status:** this is the first open‑source cut of the protocol. The current
Arbitrum Sepolia testnet deployment **predates this release** (it was deployed
2026‑04‑29 / orchestration 2026‑01‑25). The changes below therefore require a
**fresh deploy** — they are **not** an in‑place upgrade of the live addresses.
See [Deployment status](#deployment-status) and [Migration guide](#migration-guide).

Baseline for these notes = the code deployed to testnet (~2026‑04‑29).

### At a glance

- 🌐 **Plain (non‑FHE) deployment path** added next to the confidential stack, so the
  protocol can launch on mainnet before Fhenix FHE is available there.
- 🧩 **Unified `IEscrow` abstraction** — one escrow API across plain and confidential
  engines (and future funding modes).
- 🟢 **Zero protocol fee** — the protocol takes no cut anywhere; the fee mechanism is
  removed from the code, not just set to zero.
- 🏷️ **Insurance → Recourse** rename across all contracts, packages and the SDK.
- 🛡️ **Recourse upgrades** — multiple coverages per escrow, open/private pools with
  multi‑owner roles, and timelocked yield‑allocation controls.
- 📦 Repo opened for public review with security scanning (Slither, Aderyn) and a
  clear multi‑license model.

---

### 🚨 Breaking changes

**Escrow**

- **Protocol fee removed.** `registerFeeModule` / `getFeeModule` and the
  `FeeModuleRegistered` / `FeeModuleScheduledForReplace` / `FeeModuleReplaced` events
  are gone. `FeeKind` is now `{ Condition=0, Underwriter=1, Reserved=2 }` (the
  `Protocol` kind and its numbering are removed). Requires redeploy.
- **Insurance fee hook replaced.** `setInsuranceManager` / `setFeeFromInsurance` and the
  `InsuranceManagerSet` / `FeeSet` events are replaced by `setCoverageManager(address)`
  and `setUnderwriterFee(escrowId, holder, effectiveBps, recipient)`.
- **`EscrowSettled` (CCTP receiver) event fields changed** to `(uint256 usdcAmount,
uint256 escrowAmount)`. Update indexers/log decoders.
- **`IConditionResolver` plugins must implement `getConditionFee(escrowId) → (uint16
bps, address recipient)` and ERC‑165 `supportsInterface`**, or they will not register.

**Recourse (formerly Insurance)**

- **Package renamed** `@reineira-os/insurance` → `@reineira-os/recourse`; all
  `Insurance*` identifiers → `Recourse*`; confidential contracts now carry a
  `Confidential*` prefix (e.g. `ConfidentialRecoursePool`).
- **`createPool` signature changed** from `createPool(token)` to
  `createPool(token, initialManager, guardian, isOpen)`.
- **`PoolCreated` event** is now `(poolId, pool, creator, manager, guardian, isOpen)`
  (was `(poolId, pool, underwriter)`); pool getter `underwriter()` is replaced by
  `creator()` / `manager()` / `guardian()`.
- **Underwriter‑policy interface split:** `IUnderwriterPolicy` is now the plain variant
  (`evaluateRisk → uint256`, `judge → bool`); the FHE variant is the new
  `IConfidentialUnderwriterPolicy` (`euint64` / `ebool`).
- Inline events/errors moved to shared interfaces + error libraries, so error selectors
  are namespaced (e.g. `CoverageLib.InvalidPool`, not a local `InvalidPool`).

**Orchestration**

- **`FeeManager` is operator‑fee‑only.** `calculateFee(amount)` now returns a single
  `uint256 operatorFee` (was a `(protocolFee, operatorFee, totalFee)` tuple);
  `setFeeConfig` and `initialize` drop the `protocolFeeBps` argument; `protocolFeeBps()`,
  `accumulatedProtocolFees()`, `withdrawProtocolFees()` and `ProtocolFeesWithdrawn` are
  removed. `FeeCollected` / `FeeConfigUpdated` event signatures changed.

**SDK (`@reineira-os/sdk`, v1.0.0)**

- `sdk.insurance.*` → `sdk.recourse.*`; builder `.insurance({…})` → `.recourse({…})`;
  `InsuranceModule/Params/EventName` → `Recourse*`; `queryInsuranceEvents` →
  `queryRecourseEvents`.
- Removed `registerFeeModule` / `getFeeModule` / `FeeModuleRegistered` from the escrow
  ABIs; `FeeManager.calculateFee` returns operator fee only.
- `onPoolCreated` callback widened to `(poolId, pool, creator, manager, guardian, isOpen)`.
- `NetworkAddresses.simpleCondition` removed; **all testnet addresses must be re‑pulled**
  (redeploy).

**Tokens**

- The `tokens` package (`ConfidentialUSDC`, `@reineira-os/tokens`) was **removed from
  the repo** — the protocol is now token‑agnostic. The deployed `ConfidentialUSDC`
  (`0x42E47f9bA89712C317f60A72C81A610A2b68c48a`) remains live on‑chain but is no longer
  shipped as source.

---

### ✨ New features

- **Plain (non‑FHE) mode.** Plain `Escrow`, CCTP receiver, `RecoursePool`,
  `PoolFactory`, `PolicyRegistry`, `CoverageManager`, plus SDK plain modules
  (`sdk.escrowPlain`, `sdk.recoursePlain`) and `PLAIN_*` ABIs. Same lifecycle, no FHE
  dependency — the mainnet launch path while Fhenix FHE is unavailable on mainnet.
- **Unified `IEscrow` abstraction.** Opaque `create(bytes, resolver, data)` /
  `fund(id, bytes)` / `budget(id) → bytes` / `release(id, recipient, bytes)` plus the
  typed convenience overloads, so integrators target plain and confidential escrows
  (and future funding modes) through one interface. Both escrows now expose ERC‑165.
- **Multiple coverages per escrow** (up to `MAX_COVERAGES_PER_ESCROW = 5`), with
  `getCoveragesForEscrow` / `isCoveragePaid` and per‑(escrow, coverage) duplicate‑payout
  guards.
- **Open vs private pools + multi‑owner roles.** Pools carry an `isOpen` flag and three
  roles — immutable **Creator**, transferable **Manager** (`transferManager`, premium
  claims, voucher signing), reserved **Guardian**. Private pools gate `purchaseCoverage`
  behind EIP‑712 Manager‑signed `CoverageInvite` vouchers (`revokeInvite`, `usedCount`,
  `isInviteRevoked`).
- **`StrategyRouter` + `IYieldAdapter`** — timelocked yield‑allocation controls
  (per‑adapter debt caps, deployment‑bps and claims‑buffer limits, 1‑day timelock on
  risk‑increasing changes). _Foundation/controls only in v1.0 — not yet wired into live
  pool liquidity._
- **Batch redemption** with `MAX_BATCH_SIZE = 20` (`EmptyArray` / `BatchSizeExceeded`
  guards).

---

### ➖ Removed

- Escrow `ProtocolFeeModule` / `ConfidentialProtocolFeeModule` plugins and the
  `IProtocolFeeModule` / `IConfidentialProtocolFeeModule` / `IFeeModule` interfaces.
- Orchestration protocol‑fee accounting (`protocolFeeBps`, `accumulatedProtocolFees`,
  `withdrawProtocolFees`).
- `tokens` package (see Breaking).
- `SimpleCondition` example plugin (and `addresses.simpleCondition` from the SDK).
- The single‑coverage‑per‑escrow constraint (`EscrowAlreadyCovered`) and redundant
  `exists` flags on escrow/stake structs.

---

### 🔁 Behavior changes

- **Fees are charged only for the CCTP‑relay task type.** Automation / agent‑call tasks
  incur zero operator fee (previously the fee path ran for every task type).
- Confidential redemptions always succeed at the call level and **silently transfer zero
  on a failed authorization check** (FHE `select`, no revert) to avoid leaking state.
- Fees are stamped in (encrypted) basis points at create / condition‑set / coverage
  purchase and distributed proportionally on redeem; the running total is bounded by
  `MAX_TOTAL_BPS = 10000` (plain reverts `FeeBudgetExceeded`; confidential silently caps).
- Confidential `FeeStamped` / `FeeDistributed` emit `0` for the amount fields (encrypted
  values cannot appear in event logs).
- Key‑based SDK config uses a sequential‑nonce wallet to avoid nonce collisions under
  concurrent sends.

---

### 🔒 Security & correctness

- Pre‑audit pattern‑validation pass across the contracts (reentrancy, access control,
  input validation, checks‑effects‑interactions).
- `forge` lint: `SafeCast` on the production basis‑point casts; targeted, documented
  lint suppressions only for test/mock casts.
- New CI security scanning on every change: **Slither** and **Aderyn**, plus coverage
  thresholds.
- `StrategyRouter` uses `nonReentrant`, `SafeERC20.forceApprove`, a 1‑day timelock on
  risk‑increasing changes (lowering caps is immediate), and a claims‑buffer guard.
- Per‑(escrow, coverage) duplicate‑payout guard on disputes.

---

### 📦 Packages & licensing

Six packages: `escrow`, `recourse`, `orchestration` (Solidity), `shared` (interfaces,
libraries, base contracts), `offchain` (operator/coordinator/CLI), `sdk` (TypeScript).

| Area                                                        | License                                   |
| ----------------------------------------------------------- | ----------------------------------------- |
| Core protocol — `escrow`, `recourse`, `orchestration`       | FSL‑1.1‑ALv2 (→ Apache‑2.0 after 2 years) |
| `shared`, `offchain`                                        | Apache‑2.0                                |
| `sdk`                                                       | MIT                                       |
| Vendored — `FHEMeta.sol` (Fhenix CoFHE), CCTP V2 interfaces | BSD‑3‑Clause‑Clear                        |

Copyright © 2026 Reineira Labs Limited. See `LICENSE` / `NOTICE`.

---

### Deployment status

The documented Arbitrum Sepolia addresses are the **pre‑release** confidential stack
(escrow & recourse deployed 2026‑04‑29; orchestration 2026‑01‑25). They still carry the
protocol‑fee logic and the old `Insurance*` ABI names, so the current source is **not
byte‑compatible** with them.

Storage layout changed in `Escrow`, `ConfidentialEscrow` and `FeeManager`, so this
release ships via a **fresh deploy, not a UUPS upgrade**. New addresses (plain and
confidential) will be published in each package's
`deployments/arbitrumSepolia.json` after redeploy.

---

### Migration guide

**On‑chain integrators (deployed testnet addresses)**

- Treat the live addresses as the previous version; integrate against the redeployed
  contracts once published. Regenerate all ABIs.
- Update indexers for: removed fee‑module events, the changed `FeeCollected` /
  `FeeConfigUpdated` / `EscrowSettled` / `PoolCreated` signatures, the `FeeKind`
  reordering, and the `Insurance*` → `Recourse*` renames.

**Plugin authors**

- Condition resolvers: add `getConditionFee` and ERC‑165 `supportsInterface`.
- Underwriter policies: implement `IUnderwriterPolicy` (plain, `uint256`/`bool`) or
  `IConfidentialUnderwriterPolicy` (FHE, `euint64`/`ebool`).

**SDK consumers**

- `sdk.insurance` → `sdk.recourse`; builder `.insurance()` → `.recourse()`.
- Drop `registerFeeModule` / `getFeeModule` / `FeeModuleRegistered`; `calculateFee`
  returns operator fee only.
- Re‑pull all contract addresses; remove `addresses.simpleCondition`; update
  `onPoolCreated` to the six‑argument signature.
- For mainnet / plain mode use `sdk.escrowPlain` / `sdk.recoursePlain`; for private pools
  pass `invite` + `inviteSig` to `purchaseCoverage`.

---

### Known limitations (v1.0)

- Confidential operations require Fhenix CoFHE and run on testnet only; use plain mode
  for the mainnet launch path.
- `StrategyRouter` ships as allocation **controls/foundation** and is not yet wired into
  live pool liquidity.
- The deployed testnet contracts are superseded by this release and await redeploy.
