import { Contract, type Wallet } from "ethers";
import { judgeDeadline, type DeliveryFields } from "./judge.js";
import { encodeDisputeProof, signVerdict, verdictDomain, type Verdict } from "./verdict.js";

const COVERAGE_MANAGER_ABI = [
  "function dispute(uint256 coverageId, bytes disputeProof)",
  "function coverageStatus(uint256 coverageId) view returns (uint8)",
];

export interface SettleWithVerdictParams {
  coverageManager: string;
  /** VerdictUnderwriterPolicy address — the EIP-712 verifyingContract. */
  policy: string;
  chainId: number | bigint;
  coverageId: bigint;
  amount: bigint;
  nonce: bigint;
  issuedAt: number;
  fields: DeliveryFields;
  /** Off-chain judge key that signs the verdict (== policy.trustedSigner). */
  verdictSigner: Wallet;
  /** Coverage holder — dispute() requires msg.sender == holder. */
  holder: Wallet;
}

export interface SettleResult {
  verdict: Verdict;
  signature: string;
  disputeProof: string;
  txHash: string;
}

/**
 * The recourse relayer + judge, end to end: run the deadline rule, sign the
 * verdict off-chain, and submit dispute() as the holder. This is what the
 * "Simulate problem" button ultimately drives.
 */
export async function settleWithVerdict(p: SettleWithVerdictParams): Promise<SettleResult> {
  const verdict = judgeDeadline({
    coverageId: p.coverageId,
    amount: p.amount,
    nonce: p.nonce,
    issuedAt: p.issuedAt,
    fields: p.fields,
  });
  if (!verdict.breach) throw new Error("judge did not find a breach — no payout authorized");

  const domain = verdictDomain(p.chainId, p.policy);
  const signature = await signVerdict(p.verdictSigner, domain, verdict);
  const disputeProof = encodeDisputeProof(verdict, signature);

  const cm = new Contract(p.coverageManager, COVERAGE_MANAGER_ABI, p.holder);
  const tx = await cm.dispute(verdict.coverageId, disputeProof);
  const receipt = await tx.wait();

  return { verdict, signature, disputeProof, txHash: receipt?.hash ?? tx.hash };
}
