# Reineira Protocol — Confidential Escrow

Confidential escrow settlement protocol using FHE (Fully Homomorphic Encryption) via Fhenix CoFHE and CCTP V2 for cross-chain USDC transfers.

## Architecture

- **ConfidentialEscrow** - Manages encrypted escrows with confidential amounts and owners
- **CCTPV2EscrowReceiver** - Bridge receiver that settles escrows from cross-chain USDC transfers

> **Note:** The escrow settles in any ERC-7984 / FHERC20 confidential token configured at deployment — it does not bundle a specific token implementation.

> **Note:** Relayer network contracts have been moved to the [@reineira-os/orchestration](../orchestration) repository.

All core contracts use UUPS upgradeable proxy pattern for testnet iteration.

## Prerequisites

- Node.js >= 18
- npm >= 9

## Setup

```bash
npm install
cp .env.example .env
# Edit .env with your configuration
```

## Environment Variables

```
PRIVATE_KEY=               # Deployer private key (without 0x prefix)
ARBITRUM_SEPOLIA_RPC_URL=  # Arbitrum Sepolia RPC endpoint
ARBISCAN_API_KEY=          # For Arbitrum contract verification (optional)

# Optional: Use existing tokens (deploy mocks if empty)
CONFIDENTIAL_TOKEN_ADDRESS=
```

## Development

```bash
# Compile contracts
npm run compile

# Run tests
npm test

# Format code
npm run format

# Lint
npm run lint
```

## Deployment

### Deploy Escrow System (Arbitrum Sepolia)

Deploys ConfidentialEscrow and CCTPV2EscrowReceiver:

```bash
npm run deploy
```

### Local Development

```bash
npm run deploy:local
```

## Contract Address Management

Store deployed addresses in `deployments/<network>.json`.

### Arbitrum Sepolia Deployments

| Contract                         | Address                                      |
| -------------------------------- | -------------------------------------------- |
| Confidential token (interim)     | `0x42E47f9bA89712C317f60A72C81A610A2b68c48a` |
| ConfidentialEscrow               | `0xbe1eEB78504B71beEE1b33D3E3D367A2F9a549A6` |
| CCTPV2ConfidentialEscrowReceiver | `0x67AE0C5fE86716441B38b73A66F21c6aC8e338d0` |

The confidential token above is an **interim** deployment. The protocol is token-agnostic; the configured confidential token is expected to be replaced by a standardized one (see the `confidentialUsdc` note in `CCTPV2ConfidentialEscrowReceiver`).

Condition resolvers implement the `IConditionResolver` interface declared in [@reineira-os/shared](../shared).

### External Dependencies (Arbitrum Sepolia)

| Contract                    | Address                                      |
| --------------------------- | -------------------------------------------- |
| USDC                        | `0x75faf114eafb1BDbe2F0316DF893fd58CE46AA4d` |
| CCTP V2 MessageTransmitter  | `0xE737e5cEBEEBa77EFE34D4aa090756590b1CE275` |
| Trusted Forwarder (ERC2771) | `0x7ceA357B5AC0639F89F9e378a1f03Aa5005C0a25` |

## Admin Tasks

Contracts are UUPS-upgradeable (testnet only). Deployment uses the Foundry scripts in `script/` (`Deploy.s.sol`, `ConfidentialDeploy.s.sol`).

```bash
# Read the implementation behind a UUPS proxy (ERC-1967 slot)
cast implementation <PROXY> --rpc-url $ARBITRUM_SEPOLIA_RPC_URL

# Query state on a deployed contract
cast call <PROXY> "<signature>" [args] --rpc-url $ARBITRUM_SEPOLIA_RPC_URL

# Upgrade a UUPS proxy to a freshly deployed implementation
cast send <PROXY> "upgradeToAndCall(address,bytes)" <NEW_IMPL> 0x \
  --rpc-url $ARBITRUM_SEPOLIA_RPC_URL --private-key $PRIVATE_KEY
```

## Project Structure

```
contracts/
  core/           # Main contract implementations
  interfaces/     # Contract interfaces
  abstracts/      # Base contracts (TestnetCoreBase)
  extensions/     # Contract extensions
  libraries/      # Shared libraries
  mocks/          # Test mocks
script/           # Foundry scripts (Deploy.s.sol, ConfidentialDeploy.s.sol)
test/
  unit/           # Unit tests
  integration/    # Integration tests
  fixtures/       # Test fixtures
deployments/      # Deployed contract addresses per network
```

## Related Repositories

- [@reineira-os/orchestration](../orchestration) - Relayer network orchestration

## License

FSL-1.1-ALv2
