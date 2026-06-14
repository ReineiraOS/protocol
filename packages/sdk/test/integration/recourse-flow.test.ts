import { describe, it, expect, beforeAll } from "vitest";
import { ReineiraSDK, PoolInstance, CoverageStatus } from "../../src/index.js";

const PRIVATE_KEY = process.env.PRIVATE_KEY;
const RPC_URL = process.env.ARBITRUM_SEPOLIA_RPC_URL;

describe.skipIf(!PRIVATE_KEY || !RPC_URL)("Recourse Flows (integration)", () => {
  let sdk: ReineiraSDK;
  let signerAddress: string;

  beforeAll(async () => {
    sdk = ReineiraSDK.create({
      network: "testnet",
      privateKey: PRIVATE_KEY!,
      rpcUrl: RPC_URL!,
    });
    await sdk.initialize();
    signerAddress = await sdk.signer.getAddress();
  });

  describe("Pool Lifecycle", () => {
    let pool: PoolInstance;

    it("should create a pool", async () => {
      pool = await sdk.recourse.createPool({
        paymentToken: sdk.addresses.confidentialUSDC,
      });
      expect(pool.id).toBeGreaterThanOrEqual(0n);
      expect(pool.createTx!.hash).toBeTruthy();
    }, 120_000);

    it("should stake with autoApprove", async () => {
      const { stakeId, tx } = await pool.stake(sdk.usdc(10), { autoApprove: true });
      expect(stakeId).toBeGreaterThanOrEqual(0n);
      expect(tx.hash).toBeTruthy();
    }, 120_000);
  });

  describe("Pool Queries", () => {
    it("should return pool count", async () => {
      expect(await sdk.recourse.poolCount()).toBeGreaterThan(0n);
    }, 30_000);
  });

  const POLICY_ADDRESS = process.env.POLICY_ADDRESS;

  describe.skipIf(!POLICY_ADDRESS)("Coverage + Dispute", () => {
    let pool: PoolInstance;

    it("should set up pool, create escrow, purchase coverage", async () => {
      pool = await sdk.recourse.createPool({
        paymentToken: sdk.addresses.confidentialUSDC,
      });
      await pool.stake(sdk.usdc(100), { autoApprove: true });
      await pool.addPolicy(POLICY_ADDRESS!);

      const escrow = await sdk.escrow.create({ amount: sdk.usdc(10), owner: signerAddress });

      const coverage = await sdk.recourse.purchaseCoverage({
        pool: pool.address,
        policy: POLICY_ADDRESS!,
        escrowId: escrow.id,
        coverageAmount: sdk.usdc(10),
        expiry: Math.floor(Date.now() / 1000) + 86400 * 30,
      });
      expect(coverage.id).toBeGreaterThanOrEqual(0n);
      expect(await coverage.status()).toBe(CoverageStatus.Active);
    }, 240_000);
  });
});
