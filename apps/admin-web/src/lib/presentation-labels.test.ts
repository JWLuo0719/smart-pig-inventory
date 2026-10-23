import assert from "node:assert/strict";
import test from "node:test";
import { directionLabel, evidenceStateLabel, inferenceSourceLabel, inventoryStatusLabel } from "./presentation-labels.ts";

test("core status and direction labels are Chinese and unknown protocol values stay unknown", () => {
  assert.equal(inventoryStatusLabel("review_required"), "待复核");
  assert.equal(inventoryStatusLabel("confirmed"), "已确认");
  assert.equal(inventoryStatusLabel("superseded"), "历史版本");
  assert.equal(inventoryStatusLabel("new_future_state"), "状态未知");
  assert.equal(evidenceStateLabel("submitted"), "已提交");
  assert.equal(evidenceStateLabel("new_future_state"), "状态未知");
  assert.deepEqual(["single", "left", "center", "right"].map(directionLabel), ["单图", "左图", "中图", "右图"]);
  assert.equal(directionLabel("new_future_direction"), "方向未知");
  assert.equal(inferenceSourceLabel("manual"), "人工");
  assert.equal(inferenceSourceLabel(null), "未知");
});
