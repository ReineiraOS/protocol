import { describe, it, expect } from "vitest";
import { getAddresses, TESTNET_ADDRESSES } from "../../src/constants/addresses.js";
import { ethers } from "ethers";

describe("addresses", () => {
  it("should return testnet addresses for testnet network", () => {
    const addrs = getAddresses("testnet");
    expect(addrs).toBe(TESTNET_ADDRESSES);
  });

  it("should have valid addresses for all testnet entries", () => {
    for (const [key, value] of Object.entries(TESTNET_ADDRESSES)) {
      expect(ethers.isAddress(value), `${key} should be a valid address`).toBe(true);
    }
  });

  it("should include all required addresses", () => {
    const required = [
      "confidentialUSDC",
      "escrow",
      "escrowReceiver",
      "policyRegistry",
      "coverageManager",
      "poolFactory",
      "usdc",
    ];
    for (const key of required) {
      expect(TESTNET_ADDRESSES).toHaveProperty(key);
    }
  });
});
