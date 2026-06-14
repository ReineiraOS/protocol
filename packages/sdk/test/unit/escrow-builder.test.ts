import { describe, it, expect, vi } from "vitest";
import { EscrowBuilder } from "../../src/modules/escrow-builder.js";
import { ValidationError } from "../../src/errors/index.js";

const mockInstance = { id: 0n, exists: vi.fn(), fund: vi.fn(), redeem: vi.fn() };

describe("EscrowBuilder", () => {
  function builder() {
    return new EscrowBuilder(vi.fn().mockResolvedValue(mockInstance) as any);
  }

  it("should build a valid escrow config", () => {
    const b = builder().amount(1000_000000n).owner("0x1234567890123456789012345678901234567890");
    const config = b.getConfig();
    expect(config.amount).toBe(1000_000000n);
    expect(config.owner).toBe("0x1234567890123456789012345678901234567890");
  });

  it("should support fluent chaining", () => {
    const b = builder();
    const result = b
      .amount(500n)
      .owner("0x1234567890123456789012345678901234567890")
      .condition("0xabcdefabcdefabcdefabcdefabcdefabcdefabcd", "0x1234");
    expect(result).toBe(b);
  });

  it("should throw on zero amount", () => {
    expect(() => builder().amount(0n)).toThrow(ValidationError);
  });

  it("should throw on negative amount", () => {
    expect(() => builder().amount(-1n)).toThrow(ValidationError);
  });

  it("should throw on invalid owner address", () => {
    expect(() => builder().owner("not-an-address")).toThrow(ValidationError);
  });

  it("should throw on invalid resolver address", () => {
    expect(() => builder().condition("bad-address")).toThrow(ValidationError);
  });

  it("should throw on create() without amount", async () => {
    const b = builder().owner("0x1234567890123456789012345678901234567890");
    await expect(b.create()).rejects.toThrow("Amount is required");
  });

  it("should throw on create() without owner", async () => {
    const b = builder().amount(100n);
    await expect(b.create()).rejects.toThrow("Owner is required");
  });

  it("should call createFn and return EscrowInstance", async () => {
    const createFn = vi.fn().mockResolvedValue(mockInstance);
    const b = new EscrowBuilder(createFn as any);

    const result = await b
      .amount(1000n)
      .owner("0x1234567890123456789012345678901234567890")
      .condition("0xabcdefabcdefabcdefabcdefabcdefabcdefabcd", "0xdeadbeef")
      .create();

    expect(createFn).toHaveBeenCalledWith({
      amount: 1000n,
      owner: "0x1234567890123456789012345678901234567890",
      resolver: "0xabcdefabcdefabcdefabcdefabcdefabcdefabcd",
      resolverData: "0xdeadbeef",
    });
    expect(result).toBe(mockInstance);
  });

  it("should reset config after create()", async () => {
    const b = new EscrowBuilder(vi.fn().mockResolvedValue(mockInstance) as any);
    await b.amount(1000n).owner("0x1234567890123456789012345678901234567890").create();
    const config = b.getConfig();
    expect(config.amount).toBeUndefined();
    expect(config.owner).toBeUndefined();
  });

  it("should default resolverData to 0x", () => {
    const config = builder()
      .amount(100n)
      .owner("0x1234567890123456789012345678901234567890")
      .condition("0xabcdefabcdefabcdefabcdefabcdefabcdefabcd")
      .getConfig();
    expect(config.resolverData).toBe("0x");
  });

  it("should validate recourse params", () => {
    expect(() =>
      builder().recourse({
        pool: "bad",
        policy: "0xabcdefabcdefabcdefabcdefabcdefabcdefabcd",
        coverageAmount: 100n,
        expiry: 9999999999,
      }),
    ).toThrow(ValidationError);

    expect(() =>
      builder().recourse({
        pool: "0xabcdefabcdefabcdefabcdefabcdefabcdefabcd",
        policy: "bad",
        coverageAmount: 100n,
        expiry: 9999999999,
      }),
    ).toThrow(ValidationError);

    expect(() =>
      builder().recourse({
        pool: "0xabcdefabcdefabcdefabcdefabcdefabcdefabcd",
        policy: "0xabcdefabcdefabcdefabcdefabcdefabcdefabcd",
        coverageAmount: 0n,
        expiry: 9999999999,
      }),
    ).toThrow(ValidationError);
  });

  it("should store valid recourse config", () => {
    const config = builder()
      .recourse({
        pool: "0xabcdefabcdefabcdefabcdefabcdefabcdefabcd",
        policy: "0x1234567890123456789012345678901234567890",
        coverageAmount: 100n,
        expiry: 9999999999,
      })
      .getConfig();
    expect(config.recourse).toBeDefined();
    expect(config.recourse!.pool).toBe("0xabcdefabcdefabcdefabcdefabcdefabcdefabcd");
  });

  it("concurrent builders should not interfere", () => {
    const createFn = vi.fn().mockResolvedValue(mockInstance) as any;
    const b1 = new EscrowBuilder(createFn);
    const b2 = new EscrowBuilder(createFn);

    b1.amount(100n).owner("0x1234567890123456789012345678901234567890");
    b2.amount(200n).owner("0xabcdefabcdefabcdefabcdefabcdefabcdefabcd");

    expect(b1.getConfig().amount).toBe(100n);
    expect(b2.getConfig().amount).toBe(200n);
    expect(b1.getConfig().owner).toBe("0x1234567890123456789012345678901234567890");
    expect(b2.getConfig().owner).toBe("0xabcdefabcdefabcdefabcdefabcdefabcdefabcd");
  });
});
