import { id as keccakId } from "ethers";
import type { Verdict } from "./verdict.js";

/** The delivery facts the deadline rule reads (from the decision records). */
export interface DeliveryFields {
  deadline: number;
  deliveredAt?: number | null;
}

export interface JudgeInput {
  coverageId: bigint;
  amount: bigint;
  nonce: bigint;
  issuedAt: number;
  fields: DeliveryFields;
  termsHash?: string;
  triggerSpecHash?: string;
}

export const DEADLINE_TRIGGER_SPEC = "reineira.trigger.deadline.v1";

/** SCOPE-DEMO-TECH §7: deliveredAt empty or later than deadline => breach. */
export function isDeadlineBreached(fields: DeliveryFields): boolean {
  if (fields.deliveredAt == null) return true;
  return fields.deliveredAt > fields.deadline;
}

/** The judge: reads delivery facts, decides breach, emits an (unsigned) verdict statement. */
export function judgeDeadline(input: JudgeInput): Verdict {
  return {
    coverageId: input.coverageId,
    breach: isDeadlineBreached(input.fields),
    amount: input.amount,
    nonce: input.nonce,
    issuedAt: BigInt(input.issuedAt),
    termsHash: input.termsHash ?? keccakId("skill-terms"),
    triggerSpecHash: input.triggerSpecHash ?? keccakId(DEADLINE_TRIGGER_SPEC),
  };
}
