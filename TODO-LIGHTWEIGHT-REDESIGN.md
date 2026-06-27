# TODO — Lightweight Redesign (drop the operator staking stack)

> **Decision:** collapse to one permissionless, trustless settlement environment. Delete the on-chain
> operator staking/slashing/fee stack; keep the operator _role_ (a relayer bot), not the operator _contracts_.
> See `docs/adr/0001-drop-operator-staking.md`.
>
> **Trust model after this work:**
>
> - **Settlement safety** = Circle CCTP attestation, verified on-chain inside `CCTPV2EscrowReceiver.settle()` (already permissionless).
> - **Liveness** = a thin relayer bot, with a permissionless backstop (anyone can call `settle()` if it's down).
> - **Recourse capital** = LP liquidity + premiums (claims cap at pool liquidity — see Accepted Trade-offs).

---

## PR 1 — On-chain teardown ✅ (this PR)

- [x] Branch `redesign/drop-operator-staking` from `main`; baseline build green.
- [x] Relocate `CCTPV2Forwarder` (+ interface + test) into `packages/escrow/contracts/receivers/`.
- [x] Delete the `orchestration` package: `OperatorRegistry`, `OperatorSlashingManager`, `FeeManager`,
      `TaskExecutor`, `CCTPHandler`, `TaskLib`, `CCTPMessageLib` + interfaces/mocks/tests/scripts.
- [x] Update CI (`ci.yml`, `coverage.yml`, `slither.yml`, `aderyn.yml`), `aderyn.toml`,
      `scripts/run-slither.sh`, root `package.json`, `README.md`, `docs/IMPLEMENTATION-STATUS.md`.
- [x] Add ADR `docs/adr/0001-drop-operator-staking.md`.
- [x] Verify: `forge test` escrow (145) + recourse (284) green; shared builds.

## PR 2 — Off-chain client adaptation (follow-up)

> Not blocking: the TS clients bind contracts by ABI/address, so they still build and run against
> existing deployments. This PR repoints them at permissionless `settle()`.

- [ ] **Operator service** (`packages/offchain/packages/operator`, 3,471 → ~1,000 LOC):
  - [ ] Collapse `RelayJob` state machine — remove `claiming` state and the claim/`markExecuted` path.
  - [ ] Gut `EthersMessageRelayAdapter` / `message-relay.port` (on-chain claim logic).
  - [ ] Repoint `EthersTaskExecutorAdapter` from `TaskExecutor.executeTask()` to `EscrowReceiver.settle(message, attestation)`.
  - [ ] Keep: SSE-or-poll watcher, Iris attestation provider, nonce mutex, exponential-backoff retry, `/status`.
- [ ] **Coordinator service** (`packages/offchain/packages/coordinator`, 1,169 LOC): delete for launch
      (round-robin assignment only matters with many competing relayers). Note it can return as an optional dedup layer.
- [ ] **Operator CLI** (`packages/offchain/packages/operator-cli`, ~half):
  - [ ] Remove commands: `register`, `stake`, `unbond`, `withdraw`.
  - [ ] Keep: `bridge`, `relay`, `create-escrow`, `redeem-escrow`, `forward`, `status`.
  - [ ] Update `utils/contracts.ts` — drop `OperatorRegistry`/`TaskExecutor` ABIs; add the `EscrowReceiver` ABI.
- [ ] **Shared TS** (`packages/offchain/packages/shared`): remove `OperatorInfo`/`TaskClaim` staking types;
      remove `FeeManager`/`OperatorRegistry`/`TaskExecutor` from the addresses map; add the receiver address.
- [ ] **SDK** (`packages/sdk/src/modules/bridge.ts`): replace the Coordinator HTTP POST with a direct
      `settle()` call or a call to the thin relayer endpoint; grep out remaining operator/coordinator refs.
- [ ] Update `e2e/` flows: replace "register operator → claim → executeTask" with "bridge → fetch attestation → `settle()`".
- [ ] Update `packages/offchain/README.md` (remove operator-economics/staking sections).

## KEEP — do not touch (the product)

- **Escrow:** `Escrow`, `ConfidentialEscrow`, `EscrowCondition`, both `CCTPV2*EscrowReceiver`, `CCTPV2Forwarder`.
- **Recourse:** `PoolFactory`, `RecoursePool`, `PolicyRegistry`, `CoverageManager`, `StrategyRouter` + all `Confidential*` twins.
- **Shared:** `TestnetCoreBase`, `TestnetPausableBase`, `FHEMeta`, all libraries, all interfaces.
- **Identity:** `AgentIdentityRegistry` / `AgentReputationRegistry` / `AgentValidationRegistry` — independent, untouched.

## DEFER — don't build now

- [ ] `RecoursePool.pendingRewards` / `claimRewards` are stubs (DEV-118). Do not build LP-reward accounting yet —
      EigenLayer `RewardsCoordinator` may own it if restaking lands (scale dial #3).
- [ ] StrategyRouter yield adapters: optional to wire at launch.

## SCALE DIALS — add only on a real trigger (not now)

1. **Permissioned operators** — a stakeless allowlist + sanctions oracle gating `settle()` callers.
   _Trigger:_ a regulator/partner requires KYC'd settlement operators.
2. **Multi-task orchestration** — reintroduce a `TaskExecutor`-style router when a task type exists that is
   **not** attestation-deterministic (`AUTOMATION`, `AGENT_CALL`). _Trigger:_ you build agentic/scheduled tasks.
3. **Deep recourse backstop** — EigenLayer AVS with **redistributable slashing** as a junior tranche behind
   LP liquidity; operators opt into restaking. _Trigger:_ coverage above the LP pool, or externally-secured capital.

## ACCEPTED TRADE-OFFS / RISKS

- **Coverage ceiling:** with operator staking gone and EigenLayer not grafted, recourse claims **cap at LP pool
  liquidity** (truncate above it). A chosen trade for simplicity — documented, not a surprise.
- **Liveness depends on the relayer's uptime** for _speed_, never for _safety_ — `settle()` is permissionless.
- Abandoned testnet orchestration deployments stay on-chain but unused; new deploys simply omit them.
