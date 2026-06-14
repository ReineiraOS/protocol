import { describe, it, expect, beforeAll } from "vitest";
import { ReineiraSDK, type PlainEscrowInstance } from "@reineira-os/sdk";
import { loadConfig } from "../infra/load-config.js";

describe("Plain Escrow E2E (anvil)", () => {
  const config = loadConfig();
  let sdk: ReineiraSDK;

  beforeAll(async () => {
    sdk = ReineiraSDK.create({
      network: "testnet",
      privateKey: config.privateKey,
      rpcUrl: config.rpcUrl,
      addresses: {
        usdc: config.addresses.usdc,
        plainEscrow: config.addresses.plainEscrow,
        plainEscrowReceiver: config.addresses.plainEscrowReceiver,
        plainPolicyRegistry: config.addresses.plainPolicyRegistry,
        plainCoverageManager: config.addresses.plainCoverageManager,
        plainPoolFactory: config.addresses.plainPoolFactory,
      },
    });
  });

  it("create -> fund (autoApprove) -> isFunded -> redeem", async () => {
    const escrow: PlainEscrowInstance = await sdk.escrowPlain.create({
      amount: sdk.usdc(0.1),
      owner: config.deployer,
    });

    expect(escrow.id).toBeGreaterThanOrEqual(0n);
    expect(escrow.createTx?.hash).toBeTruthy();
    expect(await escrow.exists()).toBe(true);
    expect(await escrow.amount()).toBe(sdk.usdc(0.1));
    expect(await escrow.paidAmount()).toBe(0n);

    const fundResult = await escrow.fund(sdk.usdc(0.1), { autoApprove: true });
    expect(fundResult.hash).toBeTruthy();

    expect(await escrow.paidAmount()).toBe(sdk.usdc(0.1));
    expect(await escrow.isFunded()).toBe(true);
    expect(await escrow.isRedeemed()).toBe(false);

    const redeemResult = await escrow.redeem();
    expect(redeemResult.hash).toBeTruthy();
    expect(await escrow.isRedeemed()).toBe(true);
  });

  it("supports incremental funding across multiple fund() calls", async () => {
    const escrow = await sdk.escrowPlain.create({
      amount: sdk.usdc(0.1),
      owner: config.deployer,
    });

    // Fund half twice — autoApprove ensures allowance covers each call
    await escrow.fund(sdk.usdc(0.04), { autoApprove: true });
    expect(await escrow.isFunded()).toBe(false);

    await escrow.fund(sdk.usdc(0.06), { autoApprove: true });
    expect(await escrow.isFunded()).toBe(true);

    const tx = await escrow.redeem();
    expect(tx.hash).toBeTruthy();
  });

  it("redeemMultiple settles a batch", async () => {
    const ids: bigint[] = [];
    for (let i = 0; i < 3; i++) {
      const e = await sdk.escrowPlain.create({
        amount: sdk.usdc(0.01),
        owner: config.deployer,
      });
      await e.fund(sdk.usdc(0.01), { autoApprove: true });
      ids.push(e.id);
    }

    const tx = await sdk.escrowPlain.redeemMultiple(ids);
    expect(tx.hash).toBeTruthy();

    for (const id of ids) {
      const inst = sdk.escrowPlain.get(id);
      expect(await inst.isRedeemed()).toBe(true);
    }
  });

  it("get() returns a working instance for an existing escrow", async () => {
    const created = await sdk.escrowPlain.create({
      amount: sdk.usdc(0.01),
      owner: config.deployer,
    });

    const retrieved = sdk.escrowPlain.get(created.id);
    expect(retrieved.id).toBe(created.id);
    expect(await retrieved.exists()).toBe(true);
    expect(await retrieved.amount()).toBe(sdk.usdc(0.01));
  });

  it("exists() returns false for non-existent escrow", async () => {
    expect(await sdk.escrowPlain.exists(999_999n)).toBe(false);
  });

  it("total() reflects created escrows", async () => {
    const before = await sdk.escrowPlain.total();
    await sdk.escrowPlain.create({ amount: sdk.usdc(0.01), owner: config.deployer });
    const after = await sdk.escrowPlain.total();
    expect(after).toBeGreaterThan(before);
  });
});
