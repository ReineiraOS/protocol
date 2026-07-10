import { Wallet } from "ethers";
import { beforeEach, describe, expect, it } from "vitest";
import { appendRecord, payloadHashOf, verifyLog, type DecisionRecord } from "../src/records.js";

const SIGNER_PK = "0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d";

async function seedLog(): Promise<DecisionRecord[]> {
  const signer = new Wallet(SIGNER_PK);
  const log: DecisionRecord[] = [];
  await appendRecord(signer, log, { agentId: "agent-1", skillId: "skill-1", kind: "assigned", ts: 100, fields: { deadline: 200 } });
  await appendRecord(signer, log, { agentId: "agent-1", skillId: "skill-1", kind: "progress", ts: 150, fields: { note: "in progress" } });
  await appendRecord(signer, log, { agentId: "agent-1", skillId: "skill-1", kind: "deadline", ts: 260, fields: { deadline: 200, deliveredAt: null } });
  return log;
}

describe("decision record pipeline (SCOPE-DEMO-TECH §5) + verifier (§4.2)", () => {
  let log: DecisionRecord[];
  beforeEach(async () => {
    log = await seedLog();
  });

  it("a well-formed signed chain verifies", () => {
    const r = verifyLog(log);
    expect(r.ok).toBe(true);
    expect(r.errors).toEqual([]);
  });

  it("tampering a field breaks verification", () => {
    log[2].fields.deliveredAt = 190;
    expect(verifyLog(log).ok).toBe(false);
  });

  it("re-hashing a tampered field without the key still fails (signature)", () => {
    log[2].fields.deliveredAt = 190;
    log[2].payloadHash = payloadHashOf(log[2].fields);
    expect(verifyLog(log).ok).toBe(false);
  });

  it("breaking the prevHash chain fails", () => {
    log[2].prevHash = "0x" + "00".repeat(32);
    expect(verifyLog(log).ok).toBe(false);
  });

  it("deleting a record (seq gap) fails", () => {
    log.splice(1, 1);
    expect(verifyLog(log).ok).toBe(false);
  });
});
