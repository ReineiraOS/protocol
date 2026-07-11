# ReineiraOS

> [!WARNING]
> **Experimental.** This repository is an experimental R&D sandbox, not production
> software. Contracts, interfaces, and deployed addresses may change or break at any time.
>
> **Current focus: recourse.** Active work is scoped to the recourse layer only. The full
> settlement (escrow) flow is out of scope here for now and will be delivered later on demand.
> The focused, independent recourse build lives in
> [`ReineiraOS/recourse`](https://github.com/ReineiraOS/recourse).

Testnet settlement and recourse infrastructure used by Reineira's execution-accountability
stack. The current demonstration rail is operator-funded stablecoin self-bonding on Arbitrum;
carrier and insurance interfaces are mock R&D only. Powered in part by Fhenix CoFHE.

## Packages

| Package                  | Description                                                          |
| ------------------------ | -------------------------------------------------------------------- |
| `@reineira-os/shared`    | Shared Solidity contracts, interfaces, and base configs              |
| `@reineira-os/escrow`    | Confidential escrow protocol (FHE-encrypted) — settlement flow, delivered on demand |
| `@reineira-os/recourse`  | Recourse protocol — **current focus**; underwriter policies are mock-only |
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
