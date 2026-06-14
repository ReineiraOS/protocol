import { describe, it, expect } from "vitest";
import {
  ReineiraError,
  FHEInitError,
  EncryptionError,
  EscrowNotFoundError,
  TransactionFailedError,
  ValidationError,
  TimeoutError,
  CoverageNotActiveError,
} from "../../src/errors/index.js";

describe("errors", () => {
  it("should have correct codes and names", () => {
    expect(new FHEInitError("test").code).toBe("FHE_INIT_FAILED");
    expect(new EncryptionError("test").code).toBe("ENCRYPTION_FAILED");
    expect(new EscrowNotFoundError(1n).code).toBe("ESCROW_NOT_FOUND");
    expect(new TransactionFailedError("test").code).toBe("TX_FAILED");
    expect(new ValidationError("test").code).toBe("VALIDATION_FAILED");
    expect(new TimeoutError("test").code).toBe("TIMEOUT");
    expect(new CoverageNotActiveError(1n).code).toBe("COVERAGE_NOT_ACTIVE");
  });

  it("should be instanceof ReineiraError and Error", () => {
    expect(new FHEInitError("test")).toBeInstanceOf(ReineiraError);
    expect(new FHEInitError("test")).toBeInstanceOf(Error);
  });

  it("should include contextual info in messages", () => {
    expect(new EscrowNotFoundError(42n).message).toContain("42");
    expect(new CoverageNotActiveError(7n).message).toContain("7");
  });

  it("TransactionFailedError should carry txHash", () => {
    const err = new TransactionFailedError("reverted", { txHash: "0xabc" });
    expect(err.txHash).toBe("0xabc");
    expect(err.code).toBe("TX_FAILED");
  });

  it("should support cause chaining", () => {
    const cause = new Error("underlying RPC error");
    const err = new FHEInitError("init failed", cause);
    expect(err.cause).toBe(cause);
  });
});
