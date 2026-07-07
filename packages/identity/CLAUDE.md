# ERC-8004 Identity Package

This package implements the [ERC-8004: Trustless Agents](https://eips.ethereum.org/EIPS/eip-8004) standard as three upgradeable UUPS-proxy contracts on Arbitrum Sepolia.

## Contracts

### `AgentIdentityRegistry`

**Path:** `contracts/core/AgentIdentityRegistry.sol`

- ERC-721 + URIStorage for agent registration
- `register(agentURI, MetadataEntry[]) → agentId`
- `setAgentURI(agentId, newURI)`
- `setMetadata(agentId, key, value)` / `getMetadata(agentId, key)`
- `setAgentWallet(agentId, newWallet, deadline, signature)` — EIP-712 / ERC-1271 verification
- `getAgentWallet(agentId)` / `unsetAgentWallet(agentId)`
- Wallet auto-clears on token transfer (transferable by default; soulbound decision deferred)
- `__gap[50]`

### `AgentReputationRegistry`

**Path:** `contracts/core/AgentReputationRegistry.sol`

- `giveFeedback(agentId, value, valueDecimals, tag1, tag2, endpoint, feedbackURI, feedbackHash)`
  - Only non-owners can submit feedback
  - `value` is int128, `valueDecimals` 0–18
  - Emits `NewFeedback` event
- `revokeFeedback(agentId, feedbackIndex)` — author-only
- `appendResponse(agentId, clientAddress, feedbackIndex, responseURI, responseHash)` — counter-evidence
- `readFeedback`, `getLastIndex`, `getResponseCount`, `getClients`
- `__gap[50]`

### `AgentValidationRegistry`

**Path:** `contracts/core/AgentValidationRegistry.sol`

- `validationRequest(validator, agentId, requestURI, requestHash)` — agent-owner only
- `validationResponse(requestHash, response, responseURI, responseHash, tag)` — validator-only, 0–100
  - Can be called multiple times for progressive validation
- `getValidationStatus`, `getAgentValidations`, `getValidatorRequests`
- `__gap[50]`

## Architecture

All three contracts inherit from `TestnetCoreBase` (`@reineira-os/shared`), which provides:

- UUPS upgradeability
- `OwnableUpgradeable`
- `ReentrancyGuardUpgradeable`
- ERC-2771 meta-transaction support

## Dependencies

- `@openzeppelin/contracts ~5.2.0`
- `@openzeppelin/contracts-upgradeable ~5.2.0`
- `@reineira-os/shared workspace:*`

## Deployment

```bash
# Install
pnpm install

# Compile
forge build

# Test
forge test -vv

# Coverage
forge coverage

# Deploy to Arb Sepolia (set PRIVATE_KEY and optionally TRUSTED_FORWARDER)
forge script script/Deploy.s.sol --rpc-url $ARB_SEPOLIA_RPC --broadcast --verify
```

## Decisions Deferred

1. **Soulbound vs transferable `agentId`**: Currently fully transferable ERC-721. Soulbound can be enforced later via `_update` override.
2. **Encrypted-reputation variant**: Not implemented; plain-text reputation only.

## Tests

- `test/unit/AgentIdentityRegistry.t.sol` — registration, URI, metadata, wallet verification, transfers
- `test/unit/AgentReputationRegistry.t.sol` — feedback, revocation, responses, access control
- `test/unit/AgentValidationRegistry.t.sol` — requests, responses, progressive updates, view functions

All tests use Foundry with standard `Test` base (no FHE required for identity contracts).
