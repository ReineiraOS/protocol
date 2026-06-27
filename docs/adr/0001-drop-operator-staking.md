# ADR 0001 — Drop the operator staking stack; permissionless settlement

- **Status:** Accepted
- **Date:** 2026-06-27
- **Supersedes:** the on-chain `orchestration` operator network (registry, slashing, fees, task router)

## Context

Cross-chain settlement was routed through an on-chain operator network in the
`orchestration` package: `OperatorRegistry` (GOV staking, task claiming with an
exclusive→permissionless window), `OperatorSlashingManager` (optimistic
propose/challenge/vote slashing), `FeeManager` (operator fees), `TaskExecutor`
(task router gated on `canExecuteTask`), and `CCTPHandler` (the CCTP relay).

A component audit established the load-bearing fact:

- `CCTPV2EscrowReceiver.settle(message, attestation)` and its confidential twin
  are already `external` and **permissionless**, and they verify Circle's CCTP
  attestation on-chain (`receiveMessage`). The settlement outcome is fully
  determined by `(message, attestation)`.
- The `escrow` and `recourse` packages have **no compile- or deploy-time
  dependency** on `orchestration`; coupling was one-directional
  (`CCTPHandler → escrowReceiver.settle()`), and all staking coupling lived
  _inside_ `orchestration`.

Therefore the operator stack was an access **gate** over an action that is
already safe for anyone to perform. It added no settlement safety — only
liveness coordination and an unused fee/slashing apparatus (protocol and
operator fees were already zero).

## Decision

Collapse to **one permissionless, trustless settlement environment**:

1. Delete the on-chain operator staking stack — `OperatorRegistry`,
   `OperatorSlashingManager`, `FeeManager`, `TaskExecutor`, `CCTPHandler`,
   `TaskLib`, `CCTPMessageLib`, and their interfaces/mocks/tests/scripts.
   The whole `orchestration` package is removed.
2. Keep `CCTPV2Forwarder` (the non-FHE, permissionless direct-to-wallet
   forwarder) and relocate it into `escrow/contracts/receivers/`.
3. Promote `CCTPV2EscrowReceiver.settle()` as the public settlement entry point.

### Trust model after

- **Settlement safety** = Circle CCTP attestation, verified on-chain in `settle()`.
- **Liveness** = a thin relayer bot, with a permissionless backstop (anyone may
  call `settle()` if the bot is down). The relayer affects _speed_, never _safety_.
- **Recourse capital** = LP liquidity + premiums; claims cap at pool liquidity.

## Consequences

**Positive**

- ~1,400 LOC Solidity removed and a whole mini-governance retired; the protocol
  is escrow + recourse + receivers plus one bot.
- Settlement is censorship-resistant and self-healing (permissionless backstop).
- No GOV token / staking economy to bootstrap or secure.

**Negative / accepted trade-offs**

- **Coverage ceiling:** with operator staking gone and no restaking backstop,
  recourse claims cap at LP pool liquidity (truncate above it). Chosen trade.
- The off-chain `operators` service and the SDK `bridge` module still reference
  the old task-execution path; they keep working against existing deployments
  (they bind by ABI/address, not import) and are rewired in a follow-up.
- Existing testnet `orchestration` deployments remain on-chain but unused; new
  deploys omit them.

## Scale dials (deferred — add only on a real trigger)

1. **Permissioned operators** — a stakeless allowlist + sanctions oracle gating
   `settle()` callers. _Trigger:_ a regulator/partner requires KYC'd operators.
2. **Multi-task orchestration** — reintroduce a `TaskExecutor`-style router when
   a non-attestation-deterministic task type exists (`AUTOMATION`, `AGENT_CALL`).
3. **Deep recourse backstop** — an EigenLayer AVS with redistributable slashing
   as a junior tranche behind LP liquidity; operators opt into restaking.
   _Trigger:_ coverage needed above the LP pool, or externally-secured capital.

## References

- Working checklist: `TODO-LIGHTWEIGHT-REDESIGN.md`
- Implementation status: `docs/IMPLEMENTATION-STATUS.md` (§8)
