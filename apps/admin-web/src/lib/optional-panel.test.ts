import assert from "node:assert/strict";
import test from "node:test";
import { BackendApiError } from "./authenticated-backend-client.ts";
import { canReadPanel, loadOptionalPanel, panelCount, type PanelName, type PanelUser } from "./optional-panel.ts";

const panels: PanelName[] = ["duplicates", "failedJobs", "audit"];
for (const [role, expected] of [["OPERATOR", [false, false, false]], ["REVIEWER", [true, false, false]], ["FARM_ADMIN", [true, true, true]], ["SYSTEM_ADMIN", [true, true, true]]] as const) {
  test(`${role} panel permissions match backend roles`, () => {
    const user: PanelUser = { activeOrganizationId: "active", memberships: [{ organizationId: "active", roles: [role] }] };
    assert.deepEqual(panels.map((panel) => canReadPanel(user, panel)), expected);
  });
}
test("other organization and unknown roles never grant panel access", () => {
  const user = { activeOrganizationId: "active", memberships: [{ organizationId: "other", roles: ["SYSTEM_ADMIN"] }, { organizationId: "active", roles: ["UNKNOWN"] }] };
  assert.deepEqual(panels.map((panel) => canReadPanel(user, panel)), [false, false, false]);
});
test("denied panel does not issue a request or report zero", async () => {
  const state = await loadOptionalPanel(false, async () => { throw new Error("must not run"); });
  assert.equal(state.status, "forbidden");
  assert.equal(panelCount(state), null);
});
test("only successful empty response reports zero; populated data remains intact", async () => {
  assert.equal(panelCount({ status: "loading" }), null);
  assert.equal(panelCount(await loadOptionalPanel(true, async () => [])), 0);
  assert.deepEqual(await loadOptionalPanel(true, async () => [{ id: "one" }]), { status: "ready", data: [{ id: "one" }] });
});
for (const status of [401, 404, 429, 500, 503]) {
  test(`HTTP ${status} is a visible error without stale rows or zero count`, async () => {
    const state = await loadOptionalPanel(true, async () => { throw new BackendApiError(status, "private backend detail"); });
    assert.equal(state.status, "error");
    assert.equal(panelCount(state), null);
    assert.ok(!JSON.stringify(state).includes("private backend detail"));
  });
}
test("explicit 403 is forbidden", async () => {
  assert.deepEqual(await loadOptionalPanel(true, async () => { throw new BackendApiError(403, "denied"); }), { status: "forbidden" });
});
test("network, malformed JSON, and non-array success are errors", async () => {
  for (const fetchRows of [async () => { throw new TypeError("Failed to fetch"); }, async () => JSON.parse("invalid"), async () => ({}) as unknown[]]) {
    assert.equal((await loadOptionalPanel(true, fetchRows)).status, "error");
  }
});
test("one failed panel does not discard successful siblings and reload recovers", async () => {
  const states = await Promise.all([loadOptionalPanel(true, async () => [1]), loadOptionalPanel(true, async () => { throw new Error("offline"); }), loadOptionalPanel(true, async () => [])]);
  assert.deepEqual(states.map((state) => panelCount<unknown>(state)), [1, null, 0]);
  assert.equal(panelCount(await loadOptionalPanel(true, async () => [2, 3])), 2);
});
