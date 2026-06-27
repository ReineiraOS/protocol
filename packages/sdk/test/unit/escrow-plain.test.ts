import { describe, it, expect, vi, beforeEach } from "vitest";
import { ZeroAddress } from "ethers";
import { PlainEscrowModule } from "../../src/modules/escrow-plain.js";
import { PlainEscrowInstance } from "../../src/modules/escrow-plain-instance.js";
import {
  ValidationError,
  TransactionFailedError,
  ApprovalRequiredError,
} from "../../src/errors/index.js";
import type { NetworkAddresses } from "../../src/types/index.js";

const ADDRESSES: NetworkAddresses = {
  confidentialUSDC: "0x0000000000000000000000000000000000000001",
  escrow: "0x0000000000000000000000000000000000000002",
  escrowReceiver: "0x0000000000000000000000000000000000000003",
  policyRegistry: "0x0000000000000000000000000000000000000004",
  coverageManager: "0x0000000000000000000000000000000000000005",
  poolFactory: "0x0000000000000000000000000000000000000006",
  usdc: "0x0000000000000000000000000000000000000007",
  cctpMessageTransmitter: ZeroAddress,
  trustedForwarder: ZeroAddress,
  governanceToken: ZeroAddress,
  plainEscrow: "0x000000000000000000000000000000000000000A",
  plainEscrowReceiver: "0x000000000000000000000000000000000000000B",
  plainRecoursePool: "0x000000000000000000000000000000000000000C",
  plainPoolFactory: "0x000000000000000000000000000000000000000D",
  plainPolicyRegistry: "0x000000000000000000000000000000000000000E",
  plainCoverageManager: "0x000000000000000000000000000000000000000F",
};

const VALID_OWNER = "0x1234567890123456789012345678901234567890";

function makeMockSigner(address: string = VALID_OWNER): any {
  return {
    getAddress: vi.fn().mockResolvedValue(address),
    provider: { call: vi.fn(), getNetwork: vi.fn() },
  };
}

describe("PlainEscrowModule", () => {
  let mod: PlainEscrowModule;

  beforeEach(() => {
    mod = new PlainEscrowModule(makeMockSigner(), ADDRESSES);
  });

  describe("create() validation", () => {
    it("rejects zero address owner", async () => {
      await expect(mod.create({ owner: ZeroAddress, amount: 100n })).rejects.toBeInstanceOf(
        ValidationError,
      );
    });

    it("rejects empty owner", async () => {
      await expect(mod.create({ owner: "", amount: 100n })).rejects.toBeInstanceOf(ValidationError);
    });

    it("rejects zero amount", async () => {
      await expect(mod.create({ owner: VALID_OWNER, amount: 0n })).rejects.toBeInstanceOf(
        ValidationError,
      );
    });

    it("rejects negative amount", async () => {
      await expect(mod.create({ owner: VALID_OWNER, amount: -1n })).rejects.toBeInstanceOf(
        ValidationError,
      );
    });
  });

  describe("redeemMultiple() validation", () => {
    it("rejects empty array", async () => {
      await expect(mod.redeemMultiple([])).rejects.toBeInstanceOf(ValidationError);
    });
  });

  describe("get()", () => {
    it("returns a PlainEscrowInstance for the given id", () => {
      const instance = mod.get(42n);
      expect(instance).toBeInstanceOf(PlainEscrowInstance);
      expect(instance.id).toBe(42n);
    });
  });
});

describe("PlainEscrowInstance", () => {
  it("exposes id and undefined createTx by default", () => {
    const signer = makeMockSigner();
    const inst = new PlainEscrowInstance(7n, signer, ADDRESSES);
    expect(inst.id).toBe(7n);
    expect(inst.createTx).toBeUndefined();
  });

  it("preserves createTx when provided", () => {
    const signer = makeMockSigner();
    const tx = { hash: "0xdead", blockNumber: 42, gasUsed: 1n };
    const inst = new PlainEscrowInstance(7n, signer, ADDRESSES, { createTx: tx });
    expect(inst.createTx).toEqual(tx);
  });

  it("error classes are properly distinguishable", () => {
    const a = new ApprovalRequiredError("0xspender", "0xholder");
    const b = new TransactionFailedError("test");
    const c = new ValidationError("test");
    expect(a).toBeInstanceOf(ApprovalRequiredError);
    expect(b).toBeInstanceOf(TransactionFailedError);
    expect(c).toBeInstanceOf(ValidationError);
    expect(a.code).toBe("APPROVAL_REQUIRED");
    expect(b.code).toBe("TX_FAILED");
    expect(c.code).toBe("VALIDATION_FAILED");
  });
});
