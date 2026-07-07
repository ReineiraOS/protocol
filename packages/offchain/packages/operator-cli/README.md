# @reineira-os/operator-cli

Development, debugging & deployment CLI for Reineira — bridge USDC, settle (relay) messages, and create/redeem FHE-encrypted escrows. Settlement is permissionless; there is no operator registration or staking.

## Installation

```bash
npm install @reineira-os/operator-cli
```

Or run directly with npx:

```bash
npx reineira-operator <command>
```

## Configuration

The CLI can be configured via command-line options or environment variables.

### Environment Variables

Create a `.env` file in your working directory:

```bash
# Destination chain RPC (Arbitrum Sepolia)
RPC_URL=https://arbitrum-sepolia-rpc.publicnode.com

# Source chain RPC (Ethereum Sepolia) - required for bridge command
RPC_URL_SOURCE=https://ethereum-sepolia-rpc.publicnode.com

# Signer private key
PRIVATE_KEY=your_private_key_here

# Settlement entry point (Arbitrum Sepolia)
ESCROW_RECEIVER_ADDRESS=0xe0E6CC9Ee62Fa36b96eC4F50CDc462Fd14aa0fD3
```

### Command-Line Options

| Option                        | Environment Variable      | Description                        |
| ----------------------------- | ------------------------- | ---------------------------------- |
| `--rpc <url>`                 | `RPC_URL`                 | Destination chain RPC endpoint URL |
| `--rpc-source <url>`          | `RPC_URL_SOURCE`          | Source chain RPC URL (for bridge)  |
| `--private-key <key>`         | `PRIVATE_KEY`             | Signer private key                 |
| `--escrow-receiver <address>` | `ESCROW_RECEIVER_ADDRESS` | CCTPV2EscrowReceiver address       |

## Commands

> The CLI is a development, debugging & deployment tool. There is **no operator
> registration or staking** — settlement is permissionless. Commands cover
> bridging, settling (relay), and escrow create/redeem.

### bridge

Bridge USDC from Ethereum Sepolia to Arbitrum Sepolia using Circle's CCTP V2 with escrow hook data.

```bash
reineira-operator bridge --amount <amount> --escrow-id <id> [options]
```

**Options:**

| Option                  | Description                              | Default              |
| ----------------------- | ---------------------------------------- | -------------------- |
| `--amount <amount>`     | Amount of USDC to bridge (e.g., "10.00") | Required             |
| `--escrow-id <id>`      | Escrow ID to include in hook data        | Required             |
| `--recipient <address>` | Recipient address on destination chain   | CCTPV2EscrowReceiver |
| `--fast`                | Use Fast Transfer (~30s)                 | `true`               |
| `--no-fast`             | Use Standard Transfer (~15min)           | -                    |
| `--wait`                | Wait for attestation                     | -                    |

**Examples:**

```bash
# Fast transfer with escrow ID
reineira-operator bridge --amount 10.00 --escrow-id 42 --wait

# Standard transfer (slower, no fee)
reineira-operator bridge --amount 100.00 --escrow-id 123 --no-fast --wait

# Custom recipient
reineira-operator bridge --amount 5.00 --escrow-id 1 --recipient 0x1234...
```

### relay

Relay a CCTP message to the destination chain.

```bash
reineira-operator relay --tx-hash <hash> [options]
```

**Options:**

| Option                | Description                             | Default  |
| --------------------- | --------------------------------------- | -------- |
| `--tx-hash <hash>`    | Source chain transaction hash           | Required |
| `--message <hex>`     | CCTP message (if already fetched)       | -        |
| `--attestation <hex>` | Circle attestation (if already fetched) | -        |

**Example:**

```bash
# Relay a transaction (fetches attestation automatically)
reineira-operator relay --tx-hash 0x907e4defd98dd9e202db20fa4242eda19b439856ccd40866be91f2ba5fce375c
```

**Output:**

```
ℹ Relayer address: 0xa2293acEC08A6fb0A622b976ed2cF4aF1edEA292
ℹ Fetching attestation for tx 0x907e4...
──────────────────────────────────────────────────
Event Nonce:     0xa808801770d3b62f...
Status:          complete
✓ Attestation received
ℹ Message hash: 0x1234...
ℹ Settling escrow...
  tx: 0xabc123...
ℹ Waiting for confirmation...
✓ Escrow settled successfully!

Settlement Details
──────────────────────────────────────────────────
Transaction:     0xabc123...
Block:           12345678
Gas Used:        250000
Escrow ID:       1
Settler:         0xa2293acEC08A6fb0A622b976ed2cF4aF1edEA292
USDC Received:   100 USDC
```

## Contract Addresses (Arbitrum Sepolia)

| Contract                         | Address                                      |
| -------------------------------- | -------------------------------------------- |
| CCTPV2ConfidentialEscrowReceiver | `0xe0E6CC9Ee62Fa36b96eC4F50CDc462Fd14aa0fD3` |
| ConfidentialEscrow               | `0xF50A9CF008a79CFCA39aa9a345aa06e8D12727E2` |

## CCTP V2 Addresses

### Ethereum Sepolia (Source - Domain 0)

| Contract             | Address                                      |
| -------------------- | -------------------------------------------- |
| USDC                 | `0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238` |
| TokenMessengerV2     | `0x9f3B8679c73C2Fef8b59B4f3444d4e156fb70AA5` |
| MessageTransmitterV2 | `0x7865fAfC2db2093669d92c0F33AeEF291086BEFD` |

### Arbitrum Sepolia (Destination - Domain 3)

| Contract                         | Address                                      |
| -------------------------------- | -------------------------------------------- |
| USDC                             | `0x75faf114eafb1BDbe2F0316DF893fd58CE46AA4d` |
| TokenMessengerV2                 | `0x9f3B8679c73C2Fef8b59B4f3444d4e156fb70AA5` |
| MessageTransmitterV2             | `0xE737e5cEBEEBa77EFE34D4aa090756590b1CE275` |
| CCTPV2ConfidentialEscrowReceiver | `0xe0E6CC9Ee62Fa36b96eC4F50CDc462Fd14aa0fD3` |

## Economics

There are none. Settlement is **permissionless** — no registration, no stake, no
exclusive window, no unbonding, and no fees. The only cost is destination-chain gas
to submit a `settle()` transaction.

## Example Session

```bash
# Bridge USDC with an escrow hook, then settle it on the destination chain
$ reineira bridge --amount 100 --escrow-id 1 --fast
✓ Burn submitted on source chain

$ reineira relay --tx-hash 0x907e4defd98dd9e202db20fa4242eda19b439856ccd40866be91f2ba5fce375c
ℹ Fetching attestation...
✓ Attestation received
ℹ Settling escrow...
✓ Escrow settled successfully!
```

## Development

```bash
# Build
npm run build

# Run locally
node dist/index.js status
```

## License

MIT
