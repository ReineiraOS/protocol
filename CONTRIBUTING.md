# Contributing to ReineiraOS

Thanks for your interest in contributing. ReineiraOS is public infrastructure for
confidential settlement; contributions of all kinds are welcome.

## Contributor License Agreement (required)

By submitting a pull request or other contribution to this repository, you accept and
agree to the [Contributor License Agreement](CLA.md). The CLA is required for
contributions to the core protocol and the SDK. You retain copyright in your
contribution and grant Reineira Labs Limited the license described in the CLA.

## Licensing

This repository is multi-licensed by layer — see [LICENSE](LICENSE) and [NOTICE](NOTICE):

- **Core protocol** (`packages/escrow`, `packages/recourse`, `packages/orchestration`) — Functional Source License 1.1 (FSL-1.1-ALv2; non-compete, converts to Apache-2.0 after two years).
- **Shared interfaces / base contracts** (`packages/shared`) and **operator services** (`packages/offchain`) — Apache License 2.0.
- **SDK and other builder-facing edges** (`packages/sdk`, …) — MIT.

New code inherits the license of the package it lands in. Match the existing
`SPDX-License-Identifier` header used by that package; do not introduce a different
license without discussing it first.

## Development

Requires Node.js >= 20, pnpm >= 9, and [Foundry](https://book.getfoundry.sh/) for the
Solidity packages.

```bash
pnpm install            # install workspace dependencies
pnpm compile            # compile all Solidity packages
pnpm test               # run all tests
```

Per package:

```bash
pnpm --filter @reineira-os/escrow test
cd packages/escrow && forge test -vv
```

## Pull requests

- Branch from `main` and keep each PR focused on one change.
- Fill out the [pull request template](.github/pull_request_template.md).
- Run `pnpm format` and `pnpm lint` before pushing. CI runs build, tests, coverage,
  Slither, and Aderyn.
- Commit messages follow [Conventional Commits](https://www.conventionalcommits.org/)
  (`feat:`, `fix:`, `chore:`, …); the SDK release is automated from them.

## Reporting issues

- **Bugs and feature requests** — open an issue using the templates in
  [.github/ISSUE_TEMPLATE](.github/ISSUE_TEMPLATE/).
- **Security vulnerabilities** — do **not** open a public issue. Follow the disclosure
  process in [SECURITY.md](SECURITY.md).

## Code of conduct

This project follows the [Contributor Covenant](CODE_OF_CONDUCT.md). By participating,
you agree to uphold it.
