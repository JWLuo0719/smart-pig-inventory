import assert from "node:assert/strict";
import test from "node:test";
import { AssistantRequestScope, displayCount, evidencePath, parseReply, samplePrompts } from "./assistant-chat.ts";

test("zero stays zero and missing/negative/non-integer quantity stays unknown", () => {
  assert.equal(displayCount(0), "0");
  for (const v of [null, undefined, -1, 2.2, "12", NaN]) assert.equal(displayCount(v), "未知");
});
test("account/context reset cancels and invalidates an already resolved response", () => {
  const scope = new AssistantRequestScope(); const first = scope.start();
  assert.equal(first.current(), true); scope.reset();
  assert.equal(first.signal.aborted, true); assert.equal(first.current(), false);
  const next = scope.start(); assert.equal(next.current(), true); assert.equal(first.current(), false);
});
test("evidence paths never accept external URLs or object paths", () => {
  assert.equal(evidencePath({ kind: "daily_report", id: null, businessDate: "2026-11-02" }), "inventory-reports/daily?businessDate=2026-11-02");
  assert.equal(evidencePath({ kind: "session", id: "https://private", businessDate: "2026-11-02" }), null);
  assert.equal(evidencePath({ kind: "daily_report", id: "unexpected", businessDate: "2026-11-02" }), null);
});
test("malformed replies fail before displaying facts or model text", () => {
  assert.throws(() => parseReply(null)); assert.throws(() => parseReply({ status: "ok", facts: [] }));
  assert.equal(samplePrompts.length, 3);
});
