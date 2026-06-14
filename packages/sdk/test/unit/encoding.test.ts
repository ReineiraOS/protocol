import { describe, it, expect } from "vitest";
import { encodeHookData, padAddress, encodeResolverData } from "../../src/utils/encoding.js";
import { AbiCoder } from "ethers";

describe("encoding utils", () => {
  describe("encodeHookData", () => {
    it("should encode escrowId as uint256", () => {
      const encoded = encodeHookData(42n);
      const decoded = AbiCoder.defaultAbiCoder().decode(["uint256"], encoded);
      expect(decoded[0]).toBe(42n);
    });

    it("should encode zero", () => {
      const encoded = encodeHookData(0n);
      const decoded = AbiCoder.defaultAbiCoder().decode(["uint256"], encoded);
      expect(decoded[0]).toBe(0n);
    });
  });

  describe("padAddress", () => {
    it("should pad address to 32 bytes", () => {
      const addr = "0x1234567890123456789012345678901234567890";
      const padded = padAddress(addr);
      expect(padded.length).toBe(66); // 0x + 64 hex chars
      expect(padded.endsWith(addr.slice(2).toLowerCase())).toBe(true);
    });
  });

  describe("encodeResolverData", () => {
    it("should encode typed data", () => {
      const encoded = encodeResolverData(
        ["uint256", "address"],
        [100n, "0x1234567890123456789012345678901234567890"],
      );
      const decoded = AbiCoder.defaultAbiCoder().decode(["uint256", "address"], encoded);
      expect(decoded[0]).toBe(100n);
      expect(decoded[1].toLowerCase()).toBe("0x1234567890123456789012345678901234567890");
    });
  });
});
