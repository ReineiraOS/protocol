# Security Policy

ReineiraOS is testnet-only software, provided "AS IS", without warranty or
liability of any kind — see [LICENSE](LICENSE). Nothing in this document creates
any obligation, guarantee, service-level commitment, or reward, and it may change
at any time without notice.

## Reporting a vulnerability

If you believe you have found a security issue in the smart contracts in this
repository, please report it privately. **Do not open a public issue or pull
request for a suspected vulnerability.**

Email **engineering@reineira.xyz** with a description of the issue, the affected
component (package, contract, function), and reproduction steps if you have them.

Reports are reviewed at our sole discretion. We do not commit to acknowledging,
responding to, remediating, or rewarding any report, or to any timeline.

## Scope

On-chain contracts under `packages/escrow`, `packages/recourse`, and
`packages/shared`.

Out of scope: third-party dependencies (OpenZeppelin, Fhenix CoFHE,
`fhenix-confidential-contracts`, Circle CCTP) — report those to their respective
maintainers; the SDK and off-chain services; and any issue that depends on
testnet-only privileges (e.g. the deployer key on Arbitrum Sepolia).
