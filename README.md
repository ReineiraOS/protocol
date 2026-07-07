# ReineiraOS

FHE-encrypted stablecoin infrastructure on Arbitrum. Powered by Fhenix CoFHE.

## Packages

| Package                  | Description                                                          |
| ------------------------ | -------------------------------------------------------------------- |
| `@reineira-os/shared`    | Shared Solidity contracts, interfaces, and base configs              |
| `@reineira-os/escrow`    | Confidential escrow protocol (FHE-encrypted)                         |
| `@reineira-os/recourse`  | Recourse protocol with underwriter policies                          |
| `@reineira-os/operators` | Off-chain operator infrastructure (NestJS monorepo)                  |
| `@reineira-os/sdk`       | TypeScript SDK — the installable client for building on the protocol |

## Setup

```bash
pnpm install
```

## Build

```bash
pnpm compile                              # Compile all Solidity packages
pnpm test                                 # Run all tests
```

## Per-Package

```bash
pnpm --filter @reineira-os/escrow compile    # Compile escrow only
pnpm --filter @reineira-os/escrow test       # Test escrow only
pnpm --filter @reineira-os/recourse test    # Test recourse only
```

## Documentation

| Document                                               | Description                                                        |
| ------------------------------------------------------ | ------------------------------------------------------------------ |
| [Whitepaper](docs/ReineiraOS-Whitepaper.pdf)           | Protocol design and primitive definitions (cited as `§X` in code). |
| [Litepaper](docs/ReineiraOS-Litepaper.pdf)             | Condensed overview.                                                |
| [Implementation Status](docs/IMPLEMENTATION-STATUS.md) | What is shipped, partial, and planned vs. the whitepaper.          |

The protocol is **testnet · pre-audit · upgradeable** and not yet
feature-complete — see [Implementation Status](docs/IMPLEMENTATION-STATUS.md)
before relying on any whitepaper section. Full docs: [docs.reineira.xyz](https://docs.reineira.xyz).

## License

This repository is multi-licensed by layer — see [LICENSE](LICENSE) and [NOTICE](NOTICE):

- Core protocol (`escrow`, `recourse`) — **FSL-1.1-ALv2** (non-compete; each version converts to Apache-2.0 two years after release)
- Shared interfaces / base contracts (`shared`) and operator services (`offchain`) — **Apache-2.0**
- SDK (`sdk`) — **MIT**
