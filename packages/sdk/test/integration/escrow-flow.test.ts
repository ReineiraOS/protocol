import { describe, it, expect, beforeAll } from "vitest";
import { ReineiraSDK, EscrowInstance } from "../../src/index.js";

const PRIVATE_KEY = process.env.PRIVATE_KEY;
const RPC_URL = process.env.ARBITRUM_SEPOLIA_RPC_URL;

describe.skipIf(!PRIVATE_KEY || !RPC_URL)("Escrow Flows (integration)", () => {
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

  describe("Basic Lifecycle", () => {
    let escrow: EscrowInstance;

    it("should create an escrow", async () => {
      escrow = await sdk.escrow.create({ amount: sdk.usdc(1), owner: signerAddress });
      expect(escrow.id).toBeGreaterThanOrEqual(0n);
      expect(await escrow.exists()).toBe(true);
      expect(escrow.createTx!.hash).toBeTruthy();
    }, 120_000);

    it("should fund with autoApprove", async () => {
      const result = await escrow.fund(sdk.usdc(1), { autoApprove: true });
      expect(result.tx.hash).toBeTruthy();
    }, 120_000);

    it("should redeem", async () => {
      const tx = await escrow.redeem();
      expect(tx.hash).toBeTruthy();
    }, 120_000);
  });

  describe("Redeem and Unwrap", () => {
    it("should redeem with unwrapTo", async () => {
      const escrow = await sdk.escrow.create({ amount: sdk.usdc(1), owner: signerAddress });
      await escrow.fund(sdk.usdc(1), { autoApprove: true });
      const tx = await escrow.redeem({ unwrapTo: signerAddress });
      expect(tx.hash).toBeTruthy();
    }, 240_000);
  });

  describe("Batch Redeem", () => {
    it("should create, fund, and batch redeem", async () => {
      const ids: bigint[] = [];
      for (let i = 0; i < 3; i++) {
        const e = await sdk.escrow.create({ amount: sdk.usdc(1), owner: signerAddress });
        await e.fund(sdk.usdc(1), { autoApprove: true });
        ids.push(e.id);
      }
      const tx = await sdk.escrow.redeemMultiple(ids);
      expect(tx.hash).toBeTruthy();
    }, 360_000);
  });

  describe("State Queries", () => {
    it("should return total > 0", async () => {
      expect(await sdk.escrow.total()).toBeGreaterThan(0n);
    }, 30_000);

    it("should get existing escrow", async () => {
      const escrow = sdk.escrow.get(0n);
      expect(await escrow.exists()).toBe(true);
    }, 30_000);
  });
});
