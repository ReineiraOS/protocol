# Reineira Protocol -- Orchestration

Decentralized operator network for cross-chain message relay and agentic task orchestration. Manages operator registration, staking, task execution, and fee distribution.

## Architecture

### Core Contracts

- **OperatorRegistry** - Manages operator registration, staking, task claiming, and slashing
- **TaskExecutor** - Routes task execution to domain-specific handlers with fee collection
- **OperatorSlashingManager** - Decentralized slashing via optimistic dispute resolution
- **FeeManager** - Fee calculation and distribution between operators and protocol

### Handlers (Domain-Specific)

- **CCTPHandler** - Handles CCTP relay tasks (settling USDC escrows)
- Future: AutomationHandler, AgentCallHandler

### Libraries

- **TaskLib** - Task type constants and hash generation
- **CCTPMessageLib** - CCTP message parsing and validation

### Utilities

- **CCTPV2Forwarder** - Bridge receiver that forwards USDC to user wallets (non-FHE chains)

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
ARBISCAN_API_KEY=          # For contract verification (optional)

# Required: Escrow receiver from escrow deployment
ESCROW_RECEIVER_ADDRESS=

# Optional: Use existing tokens (deploy mocks if empty)
STAKING_TOKEN_ADDRESS=

# Operator System Configuration
MIN_STAKE=5000000000000000000000  # 5000 tokens (18 decimals)
EXCLUSIVE_WINDOW=60    # Exclusive claim window in seconds
PERMISSIONLESS_DELAY=600 # Time until permissionless in seconds

# Fee Configuration (in basis points, 100 = 1%)
PROTOCOL_FEE_BPS=30    # 0.3% to protocol
OPERATOR_FEE_BPS=50    # 0.5% to operator
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

### Deploy Operator System (Arbitrum Sepolia)

Deploys OperatorRegistry, FeeManager, TaskExecutor, and CCTPHandler:

```bash
npm run deploy
```

## Contract Address Management

Store deployed addresses in `deployments/<network>.json`.

### Arbitrum Sepolia Deployments

| Contract            | Address                                      |
| ------------------- | -------------------------------------------- |
| MockGovernanceToken | `0xb847e041bB3bC78C3CD951286AbCa28593739D12` |
| OperatorRegistry    | `0x1422ccC8B42079D810835631a5DFE1347a602959` |
| FeeManager          | `0x5a11DC96CEfd2fB46759F08aCE49515aa23F0156` |
| TaskExecutor        | `0x7F24077A3341Af05E39fC232A77c21A03Bbd2262` |
| CCTPHandler         | `0xb37A83461B01097e1E440405264dA59EE9a3F273` |

### External Dependencies (Arbitrum Sepolia)

| Contract                    | Address                                      |
| --------------------------- | -------------------------------------------- |
| Trusted Forwarder (ERC2771) | `0x7ceA357B5AC0639F89F9e378a1f03Aa5005C0a25` |
| Escrow Receiver             | `0x198Ca6b6116ef0de2b443F4602DbeD8f052C014d` |

### Ethereum Sepolia Deployments

| Contract        | Address                                      |
| --------------- | -------------------------------------------- |
| CCTPV2Forwarder | `0x394E2973807E4EE441b4336096c1E6AE02008eBD` |

### External Dependencies (Ethereum Sepolia)

| Contract                   | Address                                      |
| -------------------------- | -------------------------------------------- |
| USDC                       | `0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238` |
| CCTP V2 MessageTransmitter | `0x7865fAfC2db2093669d92c0F33AeEF291086BEFD` |

### Operator System Configuration

| Parameter            | Value                |
| -------------------- | -------------------- |
| Min Stake            | 5000 GOV (18 dec)    |
| Exclusive Window     | 60 seconds           |
| Permissionless Delay | 600 seconds (10 min) |
| Unbond Period        | 7 days               |
| Protocol Fee BPS     | 30 (0.3%)            |
| Operator Fee BPS     | 50 (0.5%)            |

## Admin Tasks

```bash
# Upgrade contracts (UUPS, testnet only).
# Set PROXY_ADDRESS (and optional TRUSTED_FORWARDER) in the environment first.
forge script script/Upgrade.s.sol:UpgradeRegistry        --rpc-url $ARBITRUM_SEPOLIA_RPC_URL --broadcast
forge script script/Upgrade.s.sol:UpgradeTaskExecutor    --rpc-url $ARBITRUM_SEPOLIA_RPC_URL --broadcast
forge script script/Upgrade.s.sol:UpgradeCCTPHandler     --rpc-url $ARBITRUM_SEPOLIA_RPC_URL --broadcast
forge script script/Upgrade.s.sol:UpgradeSlashingManager --rpc-url $ARBITRUM_SEPOLIA_RPC_URL --broadcast
forge script script/Upgrade.s.sol:UpgradeFeeManager      --rpc-url $ARBITRUM_SEPOLIA_RPC_URL --broadcast
```

## Project Structure

```
contracts/
  core/           # Core contract implementations
    OperatorRegistry.sol         # Operator staking & task claiming
    TaskExecutor.sol             # Task routing to handlers
    OperatorSlashingManager.sol  # Decentralized slashing
    FeeManager.sol               # Fee distribution
    CCTPV2Forwarder.sol          # Bridge receiver
  handlers/       # Domain-specific task handlers
    CCTPHandler.sol              # CCTP relay handler
  interfaces/
    core/         # Core interfaces (IOperatorRegistry, ITaskExecutor, IFeeManager, etc.)
    handlers/     # Handler interfaces (ICCTPHandler)
  libraries/      # Utility libraries
    TaskLib.sol                  # Task type constants
    CCTPMessageLib.sol           # CCTP message parsing
  abstracts/      # Base contracts
    TestnetPausableBase.sol      # With Pausable support
    TestnetCoreBase.sol          # Without Pausable
  mocks/          # Test mocks
script/           # Foundry scripts (Deploy.s.sol, Upgrade.s.sol)
test/
  unit/           # Unit tests
  fixtures/       # Test fixtures
deployments/      # Deployed contract addresses per network
```

## Related Repositories

- [@reineira-os/escrow](../escrow) - Confidential escrow settlement (FHE)

## License

FSL-1.1-ALv2
