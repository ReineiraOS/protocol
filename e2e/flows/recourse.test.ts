import { describe, it, expect, beforeAll } from "vitest";
import {
  Contract,
  JsonRpcProvider,
  Wallet,
  ZeroAddress,
  TypedDataDomain,
  type TypedDataField,
} from "ethers";
import { ReineiraSDK, PlainCoverageStatus, type CoverageInvite } from "@reineira-os/sdk";
import { loadConfig } from "../infra/load-config.js";

const INVITE_TYPES: Record<string, TypedDataField[]> = {
  CoverageInvite: [
    { name: "pool", type: "address" },
    { name: "invitee", type: "address" },
    { name: "maxUses", type: "uint256" },
    { name: "deadline", type: "uint256" },
    { name: "inviteId", type: "uint256" },
  ],
};

const POOL_ABI = [
  "function domainSeparator() view returns (bytes32)",
  "function eip712Domain() view returns (bytes1 fields, string name, string version, uint256 chainId, address verifyingContract, bytes32 salt, uint256[] extensions)",
];

const ESCROW_FEE_ABI = [
  "function getFee(uint256 escrowId, uint8 kind) view returns (uint16 bps, address recipient, bool set)",
];

const UNDERWRITER_FEE_KIND = 2;

describe("Plain Recourse E2E (anvil)", () => {
  const config = loadConfig();
  let sdk: ReineiraSDK;
  let provider: JsonRpcProvider;

  beforeAll(async () => {
    provider = new JsonRpcProvider(config.rpcUrl);
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

  async function readDomain(poolAddress: string): Promise<TypedDataDomain> {
    const poolContract = new Contract(poolAddress, POOL_ABI, provider);
    const eip712 = await poolContract.eip712Domain();
    return {
      name: eip712.name,
      version: eip712.version,
      chainId: Number(eip712.chainId),
      verifyingContract: eip712.verifyingContract,
    };
  }

  it("createPool returns a usable PlainPoolInstance", async () => {
    const pool = await sdk.recoursePlain.createPool({
      paymentToken: config.addresses.usdc,
    });
    expect(pool.id).toBeGreaterThanOrEqual(0n);
    expect(pool.address).toMatch(/^0x[a-fA-F0-9]{40}$/);
    expect(pool.createTx?.hash).toBeTruthy();
    expect(await pool.creator()).toBe(config.deployer);
    expect(await pool.manager()).toBe(config.deployer);
    expect(await pool.guardian()).toBe(ZeroAddress);
    expect(await pool.isOpen()).toBe(true);
    expect(await pool.paymentToken()).toBe(config.addresses.usdc);
  });

  it("createPool with explicit manager + guardian + closed flag", async () => {
    const manager = "0x1111111111111111111111111111111111111111";
    const guardian = "0x2222222222222222222222222222222222222222";
    const pool = await sdk.recoursePlain.createPool({
      paymentToken: config.addresses.usdc,
      initialManager: manager,
      guardian,
      isOpen: false,
    });
    expect(await pool.creator()).toBe(config.deployer);
    expect((await pool.manager()).toLowerCase()).toBe(manager);
    expect((await pool.guardian()).toLowerCase()).toBe(guardian);
    expect(await pool.isOpen()).toBe(false);
  });

  it("domainSeparator is non-zero and bound to pool address", async () => {
    const a = await sdk.recoursePlain.createPool({ paymentToken: config.addresses.usdc });
    const b = await sdk.recoursePlain.createPool({ paymentToken: config.addresses.usdc });
    const dsA = await a.domainSeparator();
    const dsB = await b.domainSeparator();
    expect(dsA).not.toBe("0x0000000000000000000000000000000000000000000000000000000000000000");
    expect(dsA).not.toBe(dsB);
  });

  it("transferManager round-trip emits and persists", async () => {
    const pool = await sdk.recoursePlain.createPool({
      paymentToken: config.addresses.usdc,
    });
    const newManager = "0x3333333333333333333333333333333333333333";
    const tx = await pool.transferManager(newManager);
    expect(tx.hash).toBeTruthy();
    expect((await pool.manager()).toLowerCase()).toBe(newManager);
    expect(await pool.creator()).toBe(config.deployer);
  });

  it("getPool returns the same instance by id", async () => {
    const created = await sdk.recoursePlain.createPool({
      paymentToken: config.addresses.usdc,
    });
    const fetched = await sdk.recoursePlain.getPool(created.id);
    expect(fetched.id).toBe(created.id);
    expect(fetched.address).toBe(created.address);
  });

  it("poolCount increments after createPool", async () => {
    const before = await sdk.recoursePlain.poolCount();
    await sdk.recoursePlain.createPool({ paymentToken: config.addresses.usdc });
    const after = await sdk.recoursePlain.poolCount();
    expect(after).toBe(before + 1n);
  });

  it("stake -> unstake round trip preserves totalLiquidity", async () => {
    const pool = await sdk.recoursePlain.createPool({
      paymentToken: config.addresses.usdc,
    });
    const before = await pool.totalLiquidity();
    const stakeAmount = sdk.usdc(0.1);
    const result = await pool.stake(stakeAmount, { autoApprove: true });
    expect(result.stakeId).toBeGreaterThanOrEqual(0n);
    expect(result.tx.hash).toBeTruthy();
    expect(await pool.totalLiquidity()).toBe(before + stakeAmount);
    expect(await pool.stakedAmount(result.stakeId)).toBe(stakeAmount);

    const unstakeTx = await pool.unstake(result.stakeId);
    expect(unstakeTx.hash).toBeTruthy();
    expect(await pool.totalLiquidity()).toBe(before);
  });

  it("closed pool: signed voucher admits the invitee through purchaseCoverage", async () => {
    const managerWallet = Wallet.createRandom();
    const policy = config.addresses.plainUnderwriterPolicy;

    const pool = await sdk.recoursePlain.createPool({
      paymentToken: config.addresses.usdc,
      initialManager: managerWallet.address,
      isOpen: false,
    });
    expect(await pool.isOpen()).toBe(false);
    expect((await pool.manager()).toLowerCase()).toBe(managerWallet.address.toLowerCase());

    await pool.addPolicy(policy);
    expect(await pool.isPolicy(policy)).toBe(true);
    await pool.stake(sdk.usdc(0.2), { autoApprove: true });

    const escrow = await sdk.escrowPlain.create({
      amount: sdk.usdc(0.1),
      owner: config.deployer,
    });

    const domain = await readDomain(pool.address);
    const now = Math.floor(Date.now() / 1000);
    const invite: CoverageInvite = {
      pool: pool.address,
      invitee: config.deployer,
      maxUses: 1n,
      deadline: BigInt(now + 3600),
      inviteId: 1n,
    };
    const inviteSig = await managerWallet.signTypedData(domain, INVITE_TYPES, invite);

    const coverage = await sdk.recoursePlain.purchaseCoverage({
      holder: config.deployer,
      pool: pool.address,
      policy,
      escrowId: escrow.id,
      coverageAmount: sdk.usdc(0.05),
      expiry: now + 3600,
      invite,
      inviteSig,
    });

    expect(await coverage.status()).toBe(PlainCoverageStatus.Active);

    const escrowContract = new Contract(config.addresses.plainEscrow, ESCROW_FEE_ABI, provider);
    const [, recipient, set] = await escrowContract.getFee(escrow.id, UNDERWRITER_FEE_KIND);
    expect(set).toBe(true);
    expect(recipient.toLowerCase()).toBe(pool.address.toLowerCase());
  });

  it("closed pool: purchaseCoverage without a voucher reverts", async () => {
    const managerWallet = Wallet.createRandom();
    const policy = config.addresses.plainUnderwriterPolicy;

    const pool = await sdk.recoursePlain.createPool({
      paymentToken: config.addresses.usdc,
      initialManager: managerWallet.address,
      isOpen: false,
    });
    await pool.addPolicy(policy);
    await pool.stake(sdk.usdc(0.2), { autoApprove: true });
    const escrow = await sdk.escrowPlain.create({
      amount: sdk.usdc(0.1),
      owner: config.deployer,
    });

    const now = Math.floor(Date.now() / 1000);
    await expect(
      sdk.recoursePlain.purchaseCoverage({
        holder: config.deployer,
        pool: pool.address,
        policy,
        escrowId: escrow.id,
        coverageAmount: sdk.usdc(0.05),
        expiry: now + 3600,
      }),
    ).rejects.toThrow();
  });

  it("closed pool: voucher issued for a different invitee reverts", async () => {
    const managerWallet = Wallet.createRandom();
    const policy = config.addresses.plainUnderwriterPolicy;

    const pool = await sdk.recoursePlain.createPool({
      paymentToken: config.addresses.usdc,
      initialManager: managerWallet.address,
      isOpen: false,
    });
    await pool.addPolicy(policy);
    await pool.stake(sdk.usdc(0.2), { autoApprove: true });
    const escrow = await sdk.escrowPlain.create({
      amount: sdk.usdc(0.1),
      owner: config.deployer,
    });

    const domain = await readDomain(pool.address);
    const now = Math.floor(Date.now() / 1000);
    const invite: CoverageInvite = {
      pool: pool.address,
      invitee: "0x0000000000000000000000000000000000009999",
      maxUses: 1n,
      deadline: BigInt(now + 3600),
      inviteId: 7n,
    };
    const inviteSig = await managerWallet.signTypedData(domain, INVITE_TYPES, invite);

    await expect(
      sdk.recoursePlain.purchaseCoverage({
        holder: config.deployer,
        pool: pool.address,
        policy,
        escrowId: escrow.id,
        coverageAmount: sdk.usdc(0.05),
        expiry: now + 3600,
        invite,
        inviteSig,
      }),
    ).rejects.toThrow();
  });
});
