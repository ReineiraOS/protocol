import { describe, it, expect } from "vitest";
import { usdc, formatUsdc } from "../../src/utils/amounts.js";

describe("usdc()", () => {
  it("converts whole numbers", () => {
    expect(usdc(1000)).toBe(1000_000000n);
    expect(usdc(1)).toBe(1_000000n);
    expect(usdc(0)).toBe(0n);
  });

  it("converts decimals", () => {
    expect(usdc(0.5)).toBe(500000n);
    expect(usdc(1.5)).toBe(1_500000n);
    expect(usdc(0.01)).toBe(10000n);
  });

  it("converts strings", () => {
    expect(usdc("1000")).toBe(1000_000000n);
    expect(usdc("0.5")).toBe(500000n);
  });

  it("throws on negative", () => {
    expect(() => usdc(-1)).toThrow("Invalid USDC amount");
  });

  it("throws on NaN", () => {
    expect(() => usdc("abc")).toThrow("Invalid USDC amount");
  });
});

describe("formatUsdc()", () => {
  it("formats whole amounts", () => {
    expect(formatUsdc(1000_000000n)).toBe("1,000.00");
    expect(formatUsdc(1_000000n)).toBe("1.00");
  });

  it("formats fractional amounts", () => {
    expect(formatUsdc(500000n)).toBe("0.50");
    expect(formatUsdc(1_500000n)).toBe("1.50");
  });

  it("formats zero", () => {
    expect(formatUsdc(0n)).toBe("0.00");
  });
});
