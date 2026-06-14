#!/usr/bin/env bash
set -euo pipefail

# Run Slither against each contracts package and aggregate results.
# Usage:
#   ./scripts/run-slither.sh                          run all 4 packages, fail on any high
#   ./scripts/run-slither.sh escrow                   run a single package
#   FAIL_ON=high ./scripts/run-slither.sh             control fail level (high|medium|low|none)
#   OUT_DIR=reports ./scripts/run-slither.sh             write per-package markdown

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

FAIL_ON="${FAIL_ON:-high}"
OUT_DIR="${OUT_DIR:-}"
PACKAGES=("${@:-escrow orchestration recourse}")

if [[ "${#PACKAGES[@]}" -eq 1 && "${PACKAGES[0]}" == *" "* ]]; then
  read -ra PACKAGES <<< "${PACKAGES[0]}"
fi

if [[ -n "$OUT_DIR" ]]; then
  mkdir -p "$OUT_DIR"
fi

OVERALL_EXIT=0

for PKG in "${PACKAGES[@]}"; do
  PKG_DIR="$ROOT/packages/$PKG"
  if [[ ! -d "$PKG_DIR/contracts" ]]; then
    echo "skip: packages/$PKG (no contracts dir)"
    continue
  fi

  echo ""
  echo "=== slither: packages/$PKG ==="

  cd "$PKG_DIR"

  SLITHER_ARGS=(. --config-file "$ROOT/slither.config.json" --compile-force-framework foundry)

  if [[ "$FAIL_ON" == "none" ]]; then
    SLITHER_ARGS+=(--no-fail-pedantic)
  else
    SLITHER_ARGS+=(--fail-"$FAIL_ON")
  fi

  if [[ -n "$OUT_DIR" ]]; then
    REPORT="$ROOT/$OUT_DIR/slither-$PKG-$(date -u +%Y-%m-%d).md"
    SLITHER_ARGS+=(--checklist --markdown-root "https://github.com/ReineiraOS/protocol/blob/main/")
    if slither "${SLITHER_ARGS[@]}" > "$REPORT" 2>&1; then
      echo "ok: $REPORT"
    else
      EC=$?
      OVERALL_EXIT=$EC
      echo "findings (exit=$EC): $REPORT"
    fi
    # Redact absolute working-dir paths Slither prints, so committed baselines don't leak a contributor's home directory
    sed -i.bak "s#$ROOT#<repo>#g" "$REPORT" && rm -f "$REPORT.bak"
  else
    if ! slither "${SLITHER_ARGS[@]}"; then
      OVERALL_EXIT=$?
    fi
  fi

  cd "$ROOT"
done

exit "$OVERALL_EXIT"
