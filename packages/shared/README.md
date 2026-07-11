# @reineira-os/shared

> **Status: testnet, pre-audit.** Insurance-coded interface names are protocol abstractions. Only
> mock underwriter policies ship today; no live carrier capacity or production underwriting is
> provided. See [`../../docs/IMPLEMENTATION-STATUS.md`](../../docs/IMPLEMENTATION-STATUS.md).

Base contracts, interfaces, and mocks shared across all ReineiraOS protocol packages.

## Contents

### Common

| Contract              | Description                                                                                     |
| --------------------- | ----------------------------------------------------------------------------------------------- |
| `TestnetCoreBase`     | Base for all upgradeable contracts (Initializable + UUPS + Ownable + ReentrancyGuard + ERC2771) |
| `TestnetPausableBase` | TestnetCoreBase + PausableUpgradeable                                                           |
| `FHEMeta`             | Library for FHE encrypted input validation and conversion                                       |

### Interfaces

| Interface                   | Description                                                                 |
| --------------------------- | --------------------------------------------------------------------------- |
| `ICore`                     | Base interface (CoreInitialized event, ZeroAddress/Unauthorized errors)     |
| `IConditionResolver`        | Pluggable escrow release conditions (`isConditionMet`, `onConditionSet`)    |
| `IUnderwriterPolicy`        | Pluggable recourse risk evaluation and dispute judgment (encrypted returns) |
| `ICCTPV2MessageTransmitter` | Circle CCTP V2 message transmitter                                          |
| `ICCTPV2EscrowReceiver`     | Cross-chain escrow receiver hook                                            |
| `IFHERC20Wrapper`           | FHE token wrapping interface                                                |

### Mocks

| Contract   | Description                       |
| ---------- | --------------------------------- |
| `MockUSDC` | Basic ERC20 USDC mock for testing |

## Usage

Other packages import from this package via the workspace:

```solidity
import { TestnetCoreBase } from "@reineira-os/shared/contracts/common/TestnetCoreBase.sol";
import { IConditionResolver } from "@reineira-os/shared/contracts/interfaces/extensions/IConditionResolver.sol";
```

## Rules

- If a contract is needed by multiple packages, it belongs here.
- Never copy contracts between packages.
