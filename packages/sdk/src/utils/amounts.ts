const USDC_DECIMALS = 6;
const USDC_FACTOR = 10n ** BigInt(USDC_DECIMALS);

/**
 * Convert a human-readable USDC amount to base units (6 decimals).
 *
 * ```ts
 * usdc(1000)    // → 1000_000000n (1,000 USDC)
 * usdc(0.5)     // → 500000n (0.50 USDC)
 * usdc("1000")  // → 1000_000000n
 * ```
 */
export function usdc(amount: number | string): bigint {
  if (typeof amount === "string") amount = Number(amount);
  if (!Number.isFinite(amount) || amount < 0) {
    throw new Error(`Invalid USDC amount: ${amount}`);
  }
  // Multiply first to avoid floating-point loss, then truncate
  return BigInt(Math.round(amount * Number(USDC_FACTOR)));
}

/**
 * Format base-unit USDC bigint to a human-readable string.
 *
 * ```ts
 * formatUsdc(1000_000000n)  // → "1,000.00"
 * formatUsdc(500000n)       // → "0.50"
 * ```
 */
export function formatUsdc(baseUnits: bigint): string {
  const whole = baseUnits / USDC_FACTOR;
  const frac = baseUnits % USDC_FACTOR;
  const fracStr = frac.toString().padStart(USDC_DECIMALS, "0").slice(0, 2);
  const wholeStr = whole.toLocaleString("en-US");
  return `${wholeStr}.${fracStr}`;
}
