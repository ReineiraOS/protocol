import { getBytes, sha256, toUtf8Bytes, verifyMessage, ZeroHash, type Wallet } from "ethers";

/** SCOPE-DEMO-TECH §5 decision record. seqNo + prevHash chain detects gaps/deletions/tampering. */
export interface DecisionRecord {
  recordVersion: number;
  agentId: string;
  skillId: string;
  seqNo: number;
  ts: number;
  kind: string;
  fields: Record<string, unknown>;
  payloadHash: string;
  prevHash: string;
  signerKeyId: string;
  sig: string;
}

export interface AppendInput {
  agentId: string;
  skillId: string;
  kind: string;
  ts: number;
  fields: Record<string, unknown>;
}

const RECORD_VERSION = 1;

function canonical(v: unknown): string {
  if (v === null || typeof v !== "object") return JSON.stringify(v) ?? "null";
  if (Array.isArray(v)) return `[${v.map(canonical).join(",")}]`;
  const obj = v as Record<string, unknown>;
  const keys = Object.keys(obj).sort();
  return `{${keys.map((k) => `${JSON.stringify(k)}:${canonical(obj[k])}`).join(",")}}`;
}

export function payloadHashOf(fields: Record<string, unknown>): string {
  return sha256(toUtf8Bytes(canonical(fields)));
}

/** Hash over every field except `sig` — this is what the signer signs and the verifier re-checks. */
export function recordCoreHash(r: Omit<DecisionRecord, "sig">): string {
  return sha256(
    toUtf8Bytes(
      canonical({
        recordVersion: r.recordVersion,
        agentId: r.agentId,
        skillId: r.skillId,
        seqNo: r.seqNo,
        ts: r.ts,
        kind: r.kind,
        payloadHash: r.payloadHash,
        prevHash: r.prevHash,
        signerKeyId: r.signerKeyId,
      }),
    ),
  );
}

export async function appendRecord(
  signer: Wallet,
  log: DecisionRecord[],
  input: AppendInput,
): Promise<DecisionRecord> {
  const seqNo = log.length;
  const prevHash = log.length ? recordCoreHash(log[log.length - 1]) : ZeroHash;
  const core: Omit<DecisionRecord, "sig"> = {
    recordVersion: RECORD_VERSION,
    agentId: input.agentId,
    skillId: input.skillId,
    seqNo,
    ts: input.ts,
    kind: input.kind,
    fields: input.fields,
    payloadHash: payloadHashOf(input.fields),
    prevHash,
    signerKeyId: signer.address,
  };
  const sig = await signer.signMessage(getBytes(recordCoreHash(core)));
  const record: DecisionRecord = { ...core, sig };
  log.push(record);
  return record;
}

export interface VerifyResult {
  ok: boolean;
  errors: string[];
}

/** SCOPE-DEMO-TECH §4.2 verifier — re-checks signature + inclusion (chain continuity). */
export function verifyLog(log: DecisionRecord[]): VerifyResult {
  const errors: string[] = [];
  for (let i = 0; i < log.length; i++) {
    const r = log[i];
    if (r.seqNo !== i) errors.push(`seqNo mismatch at index ${i}: got ${r.seqNo}`);
    if (payloadHashOf(r.fields) !== r.payloadHash) errors.push(`payloadHash mismatch at index ${i}`);
    const expectedPrev = i === 0 ? ZeroHash : recordCoreHash(log[i - 1]);
    if (r.prevHash !== expectedPrev) errors.push(`prevHash chain break at index ${i}`);
    let recovered: string;
    try {
      recovered = verifyMessage(getBytes(recordCoreHash(r)), r.sig);
    } catch {
      errors.push(`unrecoverable signature at index ${i}`);
      continue;
    }
    if (recovered.toLowerCase() !== r.signerKeyId.toLowerCase()) errors.push(`bad signature at index ${i}`);
  }
  return { ok: errors.length === 0, errors };
}
