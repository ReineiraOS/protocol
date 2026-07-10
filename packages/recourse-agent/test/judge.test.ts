import { describe, expect, it } from "vitest";
import { isDeadlineBreached, judgeDeadline } from "../src/judge.js";

describe("deadline rule (SCOPE-DEMO-TECH §7)", () => {
  it("no delivery => breach", () => {
    expect(isDeadlineBreached({ deadline: 100, deliveredAt: null })).toBe(true);
    expect(isDeadlineBreached({ deadline: 100 })).toBe(true);
  });

  it("delivered after deadline => breach", () => {
    expect(isDeadlineBreached({ deadline: 100, deliveredAt: 101 })).toBe(true);
  });

  it("delivered on/before deadline => no breach", () => {
    expect(isDeadlineBreached({ deadline: 100, deliveredAt: 100 })).toBe(false);
    expect(isDeadlineBreached({ deadline: 100, deliveredAt: 50 })).toBe(false);
  });

  it("judgeDeadline emits a verdict carrying the decision", () => {
    const v = judgeDeadline({
      coverageId: 7n,
      amount: 100_000n,
      nonce: 1n,
      issuedAt: 1_000_000,
      fields: { deadline: 100, deliveredAt: null },
    });
    expect(v.breach).toBe(true);
    expect(v.coverageId).toBe(7n);
    expect(v.amount).toBe(100_000n);
    expect(v.issuedAt).toBe(1_000_000n);
    expect(v.termsHash).toMatch(/^0x[0-9a-f]{64}$/);
  });
});
