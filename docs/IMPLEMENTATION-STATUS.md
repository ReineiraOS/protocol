# Implementation Status

> **Maturity: testnet · pre-audit · upgradeable.** The protocol is under active
> development and is **not yet feature-complete**. This document is the
> authoritative record of what is implemented, what is partial, and what is
> still planned, mapped to the whitepaper. It exists so that the relationship
> between the specification and the deployed code is explicit rather than
> assumed. Where this document and the whitepaper disagree, **this document
> describes the code; the whitepaper describes the design intent.**

**Last reviewed:** 2026-06-15

## How to read this

| Status         | Meaning                                                                        |
| -------------- | ------------------------------------------------------------------------------ |
| ✅ Implemented | Contracts/services exist and carry test coverage. Pre-audit; not yet hardened. |
| 🟡 Partial     | The interface and wiring exist, but the production logic is a stub or mock.    |
| ⏳ Planned     | Specified in the whitepaper; not yet started in this repo.                     |

"Pre-audit" applies to **everything** below: no contract in this repository has
completed an external security audit, and all core contracts are UUPS-upgradeable
on testnet. Treat every line as subject to change.

## By package

| Package                  | Status         | Notes                                                                                                                                                 |
| ------------------------ | -------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------- |
| `@reineira-os/shared`    | ✅ Implemented | Base contracts, interfaces, and mocks shared across packages.                                                                                         |
| `@reineira-os/escrow`    | ✅ Implemented | Confidential FHE escrow + CCTP V2 cross-chain USDC. Core settlement paths covered by tests.                                                           |
| `@reineira-os/recourse`  | 🟡 Partial     | Pools, factory, registry, coverage manager, and router ship; underwriter policy and LP rewards do not (see below).                                    |
| `@reineira-os/operators` | 🟡 Partial     | Off-chain relayer infrastructure (NestJS). The on-chain operator staking stack (`orchestration`) was removed — settlement is permissionless (see §8). |
| `@reineira-os/sdk`       | ✅ Implemented | TypeScript client for the protocol.                                                                                                                   |

## By whitepaper section

| §     | Area                         | Status         | Notes                                                                                                                                                                            |
| ----- | ---------------------------- | -------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| §5    | Reineira Settlement Standard | ✅ Implemented | Open RSS interfaces present.                                                                                                                                                     |
| §6    | Escrow engine                | ✅ Implemented | Confidential escrow + cross-chain settlement.                                                                                                                                    |
| §7.2  | Recourse pool roles          | ✅ Implemented | Pool Creator / Manager / LP roles enforced in plain and confidential pools.                                                                                                      |
| §7.10 | Underwriter policy           | 🟡 Partial     | `IUnderwriterPolicy` is pluggable; only mocks ship. No production risk model.                                                                                                    |
| §7.x  | LP reward accounting         | 🟡 Partial     | `pendingRewards()` / `claimRewards()` are stubs (see Known gaps).                                                                                                                |
| §8    | Operator network             | 🟡 Partial     | On-chain operator staking/slashing/fees removed; settlement is permissionless and attestation-gated. Operators are relayers; restaking (EigenLayer) is a future opt-in backstop. |
| §9    | Cross-chain (L2/L3)          | 🟡 Partial     | CCTP V2 USDC paths ship; full L3 graduation path is roadmap.                                                                                                                     |
| §10   | Security                     | 🟡 Partial     | ReentrancyGuard, access control, replay protection in place; **no audit yet.**                                                                                                   |
| §11   | Governance                   | ⏳ Planned     | Ownable/UUPS today; decentralized governance is future work.                                                                                                                     |
| §12   | Tokenomics                   | ⏳ Planned     | No token. Described as design intent only.                                                                                                                                       |
| §13   | Licensing                    | ✅ Implemented | Per-layer licensing live — see [LICENSE](../LICENSE) / [NOTICE](../NOTICE).                                                                                                      |

## Known gaps

These are the items most likely to surprise a reviewer reading the code against
the whitepaper. They are disclosed deliberately.

1. **Underwriter policy is pluggable but not yet filled in (§7.10).**
   The `recourse` package ships the `IUnderwriterPolicy` interface and mocks
   (`MockUnderwriterPolicy`, `MockConfidentialUnderwriterPolicy`) that return a
   stored constant for `evaluateRisk()` / `judge()`. There is **no production
   risk-scoring or dispute policy** in this repository yet. Pools accept any
   `IUnderwriterPolicy`-conforming contract; supplying a real one is the work
   that remains.

2. **LP reward accounting is a stub (§7.x).**
   `pendingRewards()` returns `0` (`_encryptedZero` in the confidential pool) and
   `claimRewards()` validates ownership and emits `RewardsClaimed` **without
   transferring any value**. Premium distribution to LPs is not yet implemented.
   Manager premium withdrawal (`claimPremiums`) is implemented.

3. **Capital model is a single flat pool.**
   Pools hold one undifferentiated capital bucket. Tranching / waterfall
   seniority described as design intent is not implemented.

4. **Operator network simplified to permissionless settlement (§8).**
   The on-chain operator staking stack (`orchestration`: registration, staking,
   tasks, fees, slashing) has been removed. `CCTPV2EscrowReceiver.settle()` is
   permissionless and attestation-gated, so any party can settle a bridged
   message; operators are reduced to relayers. The off-chain `operators` service
   rewrite to call `settle()` directly is the remaining follow-up. Restaking
   (EigenLayer) is a future, opt-in recourse backstop, not built.

5. **No external audit.**
   No contract here has been audited. All core contracts are upgradeable on
   testnet. Do not treat any deployment as production-grade.

## How this is published

This file is the engineering-level record that travels with the code. The same
readiness picture is intended to be reflected, in product language, in:

- the **whitepaper** (an Implementation Status / roadmap note), and
- **[docs.reineira.xyz](https://docs.reineira.xyz)** (a public status page).

If you find a discrepancy between the code and any of these surfaces, that is a
bug in the documentation — please open an issue.
