import { describe, it, expect, vi, beforeEach } from "vitest";
import { ZeroAddress } from "ethers";
import { PlainRecourseModule } from "../../src/modules/recourse-plain.js";
import { PlainPoolInstance } from "../../src/modules/pool-plain-instance.js";
import { PlainCoverageInstance } from "../../src/modules/coverage-plain-instance.js";
import { ValidationError } from "../../src/errors/index.js";
import { PlainCoverageStatus } from "../../src/types/index.js";
import type { NetworkAddresses } from "../../src/types/index.js";

const ADDRESSES: NetworkAddresses = {
  confidentialUSDC: ZeroAddress,
  escrow: ZeroAddress,
  escrowReceiver: ZeroAddress,
  policyRegistry: ZeroAddress,
  coverageManager: ZeroAddress,
  poolFactory: ZeroAddress,
  operatorRegistry: ZeroAddress,
  taskExecutor: ZeroAddress,
  feeManager: ZeroAddress,
  cctpHandler: ZeroAddress,
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

const SIGNER_ADDR = "0x1234567890123456789012345678901234567890";
const POOL_ADDR = "0x2345678901234567890123456789012345678901";
const POLICY_ADDR = "0x3456789012345678901234567890123456789012";

function makeMockSigner(address: string = SIGNER_ADDR): any {
  return {
    getAddress: vi.fn().mockResolvedValue(address),
    provider: { call: vi.fn(), getNetwork: vi.fn() },
  };
}

describe("PlainRecourseModule", () => {
  let mod: PlainRecourseModule;

  beforeEach(() => {
    mod = new PlainRecourseModule(makeMockSigner(), ADDRESSES);
  });

  describe("createPool() validation", () => {
    it("rejects empty paymentToken", async () => {
      await expect(mod.createPool({ paymentToken: "" })).rejects.toBeInstanceOf(ValidationError);
    });
  });

  describe("purchaseCoverage() validation", () => {
    const validParams = {
      holder: SIGNER_ADDR,
      pool: POOL_ADDR,
      policy: POLICY_ADDR,
      escrowId: 1n,
      coverageAmount: 1000n,
      expiry: Math.floor(Date.now() / 1000) + 86400,
    };

    it("rejects empty holder", async () => {
      await expect(mod.purchaseCoverage({ ...validParams, holder: "" })).rejects.toBeInstanceOf(
        ValidationError,
      );
    });

    it("rejects empty pool", async () => {
      await expect(mod.purchaseCoverage({ ...validParams, pool: "" })).rejects.toBeInstanceOf(
        ValidationError,
      );
    });

    it("rejects empty policy", async () => {
      await expect(mod.purchaseCoverage({ ...validParams, policy: "" })).rejects.toBeInstanceOf(
        ValidationError,
      );
    });

    it("rejects zero coverageAmount", async () => {
      await expect(
        mod.purchaseCoverage({ ...validParams, coverageAmount: 0n }),
      ).rejects.toBeInstanceOf(ValidationError);
    });
  });

  describe("getCoverage()", () => {
    it("returns a PlainCoverageInstance", () => {
      const cov = mod.getCoverage(11n);
      expect(cov).toBeInstanceOf(PlainCoverageInstance);
      expect(cov.id).toBe(11n);
    });
  });
});

describe("PlainPoolInstance", () => {
  it("exposes id and address", () => {
    const inst = new PlainPoolInstance(3n, POOL_ADDR, makeMockSigner(), ADDRESSES);
    expect(inst.id).toBe(3n);
    expect(inst.address).toBe(POOL_ADDR);
  });

  it("preserves createTx", () => {
    const tx = { hash: "0xfeed", blockNumber: 7, gasUsed: 5n };
    const inst = new PlainPoolInstance(3n, POOL_ADDR, makeMockSigner(), ADDRESSES, {
      createTx: tx,
    });
    expect(inst.createTx).toEqual(tx);
  });
});

describe("PlainCoverageStatus enum", () => {
  it("matches the on-chain enum values", () => {
    expect(PlainCoverageStatus.None).toBe(0);
    expect(PlainCoverageStatus.Active).toBe(1);
    expect(PlainCoverageStatus.Expired).toBe(2);
    expect(PlainCoverageStatus.Claimed).toBe(3);
  });
});

describe("PlainCoverageInstance", () => {
  it("exposes id", () => {
    const inst = new PlainCoverageInstance(99n, makeMockSigner(), ADDRESSES);
    expect(inst.id).toBe(99n);
  });
});
