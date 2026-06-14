#!/usr/bin/env bash
set -euo pipefail

# Validate forge coverage lcov.info against project thresholds.
# Usage:
#   ./scripts/check-coverage.sh <lcov-file> [<package-label>]
# Env:
#   LINE_THRESHOLD   default 85
#   FUNC_THRESHOLD   default 80

LCOV="${1:-}"
LABEL="${2:-package}"
LINE_THRESHOLD="${LINE_THRESHOLD:-85}"
FUNC_THRESHOLD="${FUNC_THRESHOLD:-80}"

if [[ -z "$LCOV" || ! -f "$LCOV" ]]; then
  echo "error: lcov file not found: $LCOV" >&2
  exit 2
fi

total_lf=0
total_lh=0
total_fnf=0
total_fnh=0

while IFS=: read -r prefix value; do
  value="${value%%[!0-9]*}"
  [[ -z "$value" ]] && continue
  case "$prefix" in
    LF)  total_lf=$((total_lf + value)) ;;
    LH)  total_lh=$((total_lh + value)) ;;
    FNF) total_fnf=$((total_fnf + value)) ;;
    FNH) total_fnh=$((total_fnh + value)) ;;
  esac
done < "$LCOV"

if [[ "$total_lf" -eq 0 ]]; then
  echo "error: no lines found in $LCOV" >&2
  exit 2
fi

line_pct=$((100 * total_lh / total_lf))
fn_pct=0
if [[ "$total_fnf" -gt 0 ]]; then
  fn_pct=$((100 * total_fnh / total_fnf))
fi

echo ""
echo "=== Coverage [$LABEL] ==="
echo "  lines:     $total_lh / $total_lf  ($line_pct%)  threshold: $LINE_THRESHOLD%"
echo "  functions: $total_fnh / $total_fnf  ($fn_pct%)  threshold: $FUNC_THRESHOLD%"

EXIT=0
if [[ "$line_pct" -lt "$LINE_THRESHOLD" ]]; then
  echo "  FAIL: line coverage below threshold"
  EXIT=1
fi
if [[ "$total_fnf" -gt 0 && "$fn_pct" -lt "$FUNC_THRESHOLD" ]]; then
  echo "  FAIL: function coverage below threshold"
  EXIT=1
fi

if [[ "$EXIT" -eq 0 ]]; then
  echo "  PASS"
fi

exit "$EXIT"
