import { describe, it, expect, beforeAll } from "vitest";
import { Contract, JsonRpcProvider, Wallet } from "ethers";
import { ReineiraSDK, ValidationError, ApprovalRequiredError } from "@reineira-os/sdk";
import { loadConfig } from "../infra/load-config.js";

const USDC_ALLOWANCE_ABI = ["function approve(address spender, uint256 value) returns (bool)"];

describe("Plain SDK error semantics (anvil)", () => {
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

  it("escrowPlain.create rejects zero owner with VALIDATION_FAILED", async () => {
    try {
      await sdk.escrowPlain.create({
        amount: sdk.usdc(1),
        owner: "0x0000000000000000000000000000000000000000",
      });
      expect.fail("Should have thrown");
    } catch (err) {
      expect(err).toBeInstanceOf(ValidationError);
      expect((err as ValidationError).code).toBe("VALIDATION_FAILED");
    }
  });

  it("escrowPlain.create rejects zero amount with VALIDATION_FAILED", async () => {
    try {
      await sdk.escrowPlain.create({
        amount: 0n,
        owner: config.deployer,
      });
      expect.fail("Should have thrown");
    } catch (err) {
      expect(err).toBeInstanceOf(ValidationError);
    }
  });

  it("escrowPlain.redeemMultiple rejects empty array with VALIDATION_FAILED", async () => {
    try {
      await sdk.escrowPlain.redeemMultiple([]);
      expect.fail("Should have thrown");
    } catch (err) {
      expect(err).toBeInstanceOf(ValidationError);
    }
  });

  it("escrow.fund without autoApprove throws APPROVAL_REQUIRED", async () => {
    const provider = new JsonRpcProvider(config.rpcUrl);
    const wallet = new Wallet(config.privateKey, provider);
    const usdc = new Contract(config.addresses.usdc, USDC_ALLOWANCE_ABI, wallet);

    // Zero out any allowance leaked by prior tests so the deficit is deterministic.
    const resetTx = await usdc.approve(config.addresses.plainEscrow, 0n);
    await resetTx.wait();

    const escrow = await sdk.escrowPlain.create({
      amount: sdk.usdc(50),
      owner: config.deployer,
    });

    try {
      await escrow.fund(sdk.usdc(50), { autoApprove: false });
      expect.fail("Should have thrown ApprovalRequiredError");
    } catch (err) {
      expect(err).toBeInstanceOf(ApprovalRequiredError);
      expect((err as ApprovalRequiredError).code).toBe("APPROVAL_REQUIRED");
    }
  });
});
