import { describe, it, expect, vi } from "vitest";
import { pollUntil } from "../../src/utils/polling.js";
import { TimeoutError } from "../../src/errors/index.js";

describe("pollUntil", () => {
  it("should resolve immediately if condition is true", async () => {
    const fn = vi.fn().mockResolvedValue(true);
    await pollUntil(fn, { pollIntervalMs: 100, timeoutMs: 1000 });
    expect(fn).toHaveBeenCalledTimes(1);
  });

  it("should poll until condition becomes true", async () => {
    let calls = 0;
    const fn = vi.fn().mockImplementation(async () => {
      calls++;
      return calls >= 3;
    });

    await pollUntil(fn, { pollIntervalMs: 50, timeoutMs: 5000 });
    expect(fn).toHaveBeenCalledTimes(3);
  });

  it("should throw TimeoutError when timeout is exceeded", async () => {
    const fn = vi.fn().mockResolvedValue(false);

    await expect(pollUntil(fn, { pollIntervalMs: 50, timeoutMs: 150 })).rejects.toThrow(
      TimeoutError,
    );
  });
});
