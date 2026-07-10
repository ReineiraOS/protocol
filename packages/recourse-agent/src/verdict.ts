import { AbiCoder, TypedDataEncoder, verifyTypedData, type TypedDataDomain, type Wallet } from "ethers";

export interface Verdict {
  coverageId: bigint;
  breach: boolean;
  amount: bigint;
  nonce: bigint;
  issuedAt: bigint;
  termsHash: string;
  triggerSpecHash: string;
}

export const VERDICT_DOMAIN_NAME = "ReineiraVerdict";
export const VERDICT_DOMAIN_VERSION = "1";

export const VERDICT_TYPES = {
  Verdict: [
    { name: "coverageId", type: "uint256" },
    { name: "breach", type: "bool" },
    { name: "amount", type: "uint256" },
    { name: "nonce", type: "uint256" },
    { name: "issuedAt", type: "uint256" },
    { name: "termsHash", type: "bytes32" },
    { name: "triggerSpecHash", type: "bytes32" },
  ],
};

const PROOF_TUPLE =
  "tuple(uint256 coverageId,bool breach,uint256 amount,uint256 nonce,uint256 issuedAt,bytes32 termsHash,bytes32 triggerSpecHash)";

export function verdictDomain(chainId: number | bigint, verifyingContract: string): TypedDataDomain {
  return { name: VERDICT_DOMAIN_NAME, version: VERDICT_DOMAIN_VERSION, chainId, verifyingContract };
}

/** EIP-712 digest — must equal VerdictUnderwriterPolicy.hashVerdict(v) on-chain. */
export function verdictDigest(domain: TypedDataDomain, verdict: Verdict): string {
  return TypedDataEncoder.hash(domain, VERDICT_TYPES, verdict);
}

export function signVerdict(signer: Wallet, domain: TypedDataDomain, verdict: Verdict): Promise<string> {
  return signer.signTypedData(domain, VERDICT_TYPES, verdict);
}

export function recoverVerdictSigner(domain: TypedDataDomain, verdict: Verdict, signature: string): string {
  return verifyTypedData(domain, VERDICT_TYPES, verdict, signature);
}

/** ABI-encode (Verdict, signature) into the bytes `disputeProof` that CoverageManager.dispute forwards. */
export function encodeDisputeProof(verdict: Verdict, signature: string): string {
  return AbiCoder.defaultAbiCoder().encode(
    [PROOF_TUPLE, "bytes"],
    [
      [
        verdict.coverageId,
        verdict.breach,
        verdict.amount,
        verdict.nonce,
        verdict.issuedAt,
        verdict.termsHash,
        verdict.triggerSpecHash,
      ],
      signature,
    ],
  );
}
