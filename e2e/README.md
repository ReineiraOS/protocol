# Plain Mode E2E Suite

> These tests exercise testnet/demo interfaces. Coverage purchase, disputes, and underwriter
> policies do not represent a live insurance product; underwriter logic is mock-only.

End-to-end smoke harness for the plain (non-FHE) protocol path.
Uses [`anvil`](https://book.getfoundry.sh/anvil/) + the plain `Deploy.s.sol`
scripts + `@reineira-os/sdk`'s plain modules.

## What it covers

- `flows/escrow.test.ts` — full plain escrow lifecycle: create → fund (with
  ERC20 auto-approve) → redeem; batch redeem; partial funding; existing-id
  re-instancing.
- `flows/recourse.test.ts` — pool creation, pool lookup, staking with
  auto-approve, total-liquidity / staked-amount views.
- `flows/errors.test.ts` — SDK error code semantics (`VALIDATION_FAILED`,
  `APPROVAL_REQUIRED`).

## What it does NOT cover

- Cross-chain CCTP settlement (would require a second chain + attestation
  service mock — out of scope for plain-mode launch smoke).
- Coverage purchase + dispute (requires an `IUnderwriterPolicy`
  implementation deployed; defer until a sample policy is bundled with the
  recourse package).
- FHE / confidential paths (covered by `forge test` per package).

## Running locally

Prereqs: `anvil`, `forge`, `cast` (Foundry), `pnpm`.

```bash
pnpm e2e          # from repo root — same as e2e/run.sh
# or
./e2e/run.sh
```

The orchestrator:

1. Builds `@reineira-os/sdk`.
2. Starts `anvil` in the background.
3. Deploys `MockUSDC`.
4. Runs plain `script/Deploy.s.sol` for escrow + recourse with the deployed
   USDC address piped through env vars.
5. Mints USDC to the deterministic deployer.
6. Writes `e2e/.addresses.local.json` (gitignored).
7. Runs `vitest` against the local stack.
8. Cleans up `anvil`.

## CI

A `workflow_dispatch`-triggered job at `.github/workflows/e2e.yml` lets
maintainers run the suite manually before merging changes that affect
plain-mode contracts, deploy scripts, or the SDK plain modules.
