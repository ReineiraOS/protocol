import { AbiCoder, id as keccakId, Wallet } from "ethers";
import { describe, expect, it } from "vitest";
import { encodeDisputeProof, recoverVerdictSigner, signVerdict, verdictDomain, type Verdict } from "../src/verdict.js";

const SIGNER_PK = "0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d";
const POLICY = "0x2334B114E70A355698240B5A0467025103Be9fEf";

function sample(): Verdict {
  return {
    coverageId: 3n,
    breach: true,
    amount: 100_000n,
    nonce: 1n,
    issuedAt: 1_000_000n,
    termsHash: keccakId("skill-terms"),
    triggerSpecHash: keccakId("deadline-missed"),
  };
}

describe("verdict EIP-712 signing", () => {
  it("signature recovers to the signer", async () => {
    const wallet = new Wallet(SIGNER_PK);
    const domain = verdictDomain(421614, POLICY);
    const v = sample();
    const sig = await signVerdict(wallet, domain, v);
    expect(recoverVerdictSigner(domain, v, sig).toLowerCase()).toBe(wallet.address.toLowerCase());
  });

  it("tampered verdict does not recover to the signer", async () => {
    const wallet = new Wallet(SIGNER_PK);
    const domain = verdictDomain(421614, POLICY);
    const sig = await signVerdict(wallet, domain, sample());
    const tampered = { ...sample(), amount: 999_999n };
    expect(recoverVerdictSigner(domain, tampered, sig).toLowerCase()).not.toBe(wallet.address.toLowerCase());
  });

  it("encodeDisputeProof round-trips through the ABI coder in struct field order", () => {
    const v = sample();
    const proof = encodeDisputeProof(v, "0x1234");
    const [decoded] = AbiCoder.defaultAbiCoder().decode(
      [
        "tuple(uint256 coverageId,bool breach,uint256 amount,uint256 nonce,uint256 issuedAt,bytes32 termsHash,bytes32 triggerSpecHash)",
        "bytes",
      ],
      proof,
    );
    expect(decoded.coverageId).toBe(3n);
    expect(decoded.breach).toBe(true);
    expect(decoded.amount).toBe(100_000n);
    expect(decoded.nonce).toBe(1n);
  });
});
