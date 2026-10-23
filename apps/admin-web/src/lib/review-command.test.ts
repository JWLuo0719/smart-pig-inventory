import assert from "node:assert/strict";
import test from "node:test";
import { candidateDifference, containRect, reviewCommand } from "./review-command.ts";

test("confirmation keeps a valid zero and requires evidence for an unknown or changed candidate", () => {
  assert.deepEqual(reviewCommand("confirm", "0", "", 0).body, { confirmedCount: 0, reason: null });
  assert.throws(() => reviewCommand("confirm", "", "", null));
  assert.throws(() => reviewCommand("confirm", "1", "", null));
  assert.throws(() => reviewCommand("confirm", "1", "", 2));
  assert.throws(() => reviewCommand("correction", "1", "", 1));
  assert.throws(() => reviewCommand("confirm", "2147483648", "valid evidence reason", null));
  assert.equal(reviewCommand("correction", "19", "  checked original evidence  ", 17).intent,
    reviewCommand("correction", "19", "checked original evidence", 17).intent);
});

test("portrait and landscape evidence retain correct letterbox coordinates", () => {
  assert.deepEqual(containRect(1600, 900, 640, 480), { left: 0, top: 60, width: 640, height: 360 });
  assert.deepEqual(containRect(900, 1600, 640, 480), { left: 185, top: 0, width: 270, height: 480 });
});

test("candidate difference distinguishes an unknown candidate from a valid zero", () => {
  assert.equal(candidateDifference("3", null), "未知（服务端未提供候选）");
  assert.equal(candidateDifference("3", undefined), "未知（服务端未提供候选）");
  assert.equal(candidateDifference("3", 0), "+3 头");
  assert.equal(candidateDifference("0", 3), "-3 头");
  assert.equal(candidateDifference("0", 0), "0 头");
  assert.equal(candidateDifference("", 0), "待输入有效人工数量");
  assert.equal(candidateDifference("2147483648", 0), "待输入有效人工数量");
});
