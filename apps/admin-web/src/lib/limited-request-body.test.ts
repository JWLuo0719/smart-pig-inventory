import test from "node:test";
import assert from "node:assert/strict";
import { readLimitedRequestBody } from "./limited-request-body.ts";

test("request body cap covers declared and undeclared sizes", async () => {
  await assert.rejects(readLimitedRequestBody(new Request("https://fixture", { method: "POST", body: "too long" }), 3), RangeError);
  const accepted = await readLimitedRequestBody(new Request("https://fixture", { method: "POST", body: "abc" }), 3);
  assert.equal(new TextDecoder().decode(accepted), "abc");
});
test("valid Chinese question and six history turns fit the default UTF-8 byte budget", async () => {
  const text = "盘点".repeat(1000);
  const value = JSON.stringify({ message: text, businessDate: "2026-11-02", history: Array.from({ length: 6 }, () => ({ role: "user", content: text })) });
  const accepted = await readLimitedRequestBody(new Request("https://fixture", { method: "POST", body: value }));
  assert.equal(new TextDecoder().decode(accepted), value);
});
