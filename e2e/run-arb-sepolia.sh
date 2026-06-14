#!/usr/bin/env bash
set -euo pipefail

# Real-network E2E orchestrator: Arbitrum Sepolia.
#
# Reads PRIVATE_KEY from e2e/.env.local, points the existing vitest flows at
# the already-deployed plain stack (addresses inlined below),
# uses real Circle testnet USDC.
#
# Steps:
#   1. Load PRIVATE_KEY from e2e/.env.local
#   2. Sanity-check ETH + USDC balance
#   3. Verify PoolFactory.isAllowedToken(USDC) — fail fast if not allowed
#   4. Build SDK
#   5. Write e2e/.addresses.local.json with Arbitrum Sepolia addresses
#   6. Run vitest

E2E_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$E2E_DIR/.." && pwd)"

RPC_URL="${RPC_URL:-https://sepolia-rollup.arbitrum.io/rpc}"
CHAIN_ID="421614"

# Plain-mode deployed addresses (Arbitrum Sepolia)
USDC="0x75faf114eafb1BDbe2F0316DF893fd58CE46AA4d"
PLAIN_ESCROW="0xa125db70c1f17E395AfFa30b32e1e4A94aF3A81c"
PLAIN_ESCROW_RECEIVER="0xD4cb6F1B679C3b16AE02aAdc66e172142EAAC5a2"
PLAIN_POLICY_REGISTRY="0xAf23b86086FC6DC74796865be3B3a8bBAd68AB95"
PLAIN_COVERAGE_MANAGER="0x3fcD1896745B2b91b4397e7E762910Fbf7eE9D22"
PLAIN_POOL_FACTORY="0xA2D78bfaB94B93106c8Da17E6967501D54DfE772"

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || { echo "Error: '$1' not found"; exit 1; }
}
require_cmd cast
require_cmd pnpm
require_cmd jq

ENV_FILE="$E2E_DIR/.env.local"
if [ ! -f "$ENV_FILE" ]; then
  echo "Error: $ENV_FILE not found. Copy .env.local.example and fill in PRIVATE_KEY."
  exit 1
fi
# shellcheck disable=SC1090
set -a; source "$ENV_FILE"; set +a

if [ -z "${PRIVATE_KEY:-}" ] || [[ "$PRIVATE_KEY" == *YOUR_*KEY* ]]; then
  echo "Error: PRIVATE_KEY is not set in $ENV_FILE"
  exit 1
fi

DEPLOYER=$(cast wallet address --private-key "$PRIVATE_KEY")
echo "[1/5] Wallet: $DEPLOYER"
echo "       RPC:    $RPC_URL"

echo "[2/5] Checking balances..."
ETH_WEI=$(cast balance "$DEPLOYER" --rpc-url "$RPC_URL")
ETH_FLOAT=$(cast from-wei "$ETH_WEI")
USDC_RAW=$(cast call "$USDC" "balanceOf(address)(uint256)" "$DEPLOYER" --rpc-url "$RPC_URL" | awk '{print $1}')
# USDC has 6 decimals
USDC_HUMAN=$(python3 -c "print(int('$USDC_RAW') / 1e6)")

echo "       ETH:  $ETH_FLOAT"
echo "       USDC: $USDC_HUMAN"

# Need ~0.005 ETH for gas (4-5 createPool proxies + ~10 escrow tx)
if python3 -c "import sys; sys.exit(0 if float('$ETH_FLOAT') < 0.003 else 1)"; then
  echo "Error: insufficient ETH (<0.003). Top up via Arbitrum Sepolia faucet."
  exit 1
fi
# Tests run sequentially (vitest singleFork) so peak USDC lock is 0.1 (stake-then-unstake).
# 1 USDC threshold is plenty.
if python3 -c "import sys; sys.exit(0 if float('$USDC_HUMAN') < 1 else 1)"; then
  echo "Error: insufficient USDC (<1). Get from https://faucet.circle.com (Arbitrum Sepolia)."
  exit 1
fi

echo "[3/5] Verifying PoolFactory allows USDC..."
ALLOWED=$(cast call "$PLAIN_POOL_FACTORY" "isAllowedToken(address)(bool)" "$USDC" --rpc-url "$RPC_URL")
if [ "$ALLOWED" != "true" ]; then
  echo "Error: PoolFactory $PLAIN_POOL_FACTORY does not allow USDC $USDC."
  echo "       Owner of PoolFactory must call addAllowedToken($USDC) first."
  exit 1
fi
echo "       OK"

echo "[4/5] Building SDK..."
pnpm --filter @reineira-os/sdk run build > /dev/null

echo "[5/5] Writing addresses + running flows..."
cat > "$E2E_DIR/.addresses.local.json" <<EOF
{
  "rpcUrl": "$RPC_URL",
  "chainId": $CHAIN_ID,
  "privateKey": "$PRIVATE_KEY",
  "deployer": "$DEPLOYER",
  "addresses": {
    "usdc": "$USDC",
    "plainEscrow": "$PLAIN_ESCROW",
    "plainEscrowReceiver": "$PLAIN_ESCROW_RECEIVER",
    "plainPolicyRegistry": "$PLAIN_POLICY_REGISTRY",
    "plainCoverageManager": "$PLAIN_COVERAGE_MANAGER",
    "plainPoolFactory": "$PLAIN_POOL_FACTORY"
  }
}
EOF

cd "$E2E_DIR" && pnpm run test

echo ""
echo "✓ Real-network E2E suite complete (Arbitrum Sepolia)"
