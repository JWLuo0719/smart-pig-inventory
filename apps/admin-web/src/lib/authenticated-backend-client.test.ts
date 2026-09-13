import assert from "node:assert/strict";
import test from "node:test";

import {
  AuthenticatedBackendClient,
  BackendApiError,
  type BackendFetcher,
  type TokenPair,
  fetchBackend,
} from "./authenticated-backend-client.ts";

const oldTokens: TokenPair = {
  accessToken: "expired-access",
  refreshToken: "refresh-1",
  accessTokenExpiresAt: "2026-09-04T00:00:00Z",
  refreshTokenExpiresAt: "2026-09-11T00:00:00Z",
};

const newTokens: TokenPair = {
  accessToken: "fresh-access",
  refreshToken: "refresh-2",
  accessTokenExpiresAt: "2026-09-04T00:15:00Z",
  refreshTokenExpiresAt: "2026-09-11T00:15:00Z",
};

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json" } });
}

test("coalesces concurrent 401 refreshes and replays the unchanged write request", async () => {
  let refreshCalls = 0;
  const replayedKeys: string[] = [];
  const fetcher: BackendFetcher = async (path, token, init) => {
    if (path === "auth/refresh") {
      refreshCalls += 1;
      await new Promise((resolve) => setTimeout(resolve, 10));
      return jsonResponse(newTokens);
    }
    if (token === oldTokens.accessToken) return jsonResponse({ message: "expired" }, 401);
    replayedKeys.push(new Headers(init?.headers).get("X-Idempotency-Key") ?? "");
    return jsonResponse({ ok: true });
  };
  const client = new AuthenticatedBackendClient(() => undefined, fetcher);
  client.installTokens(oldTokens);
  const write = {
    method: "POST",
    headers: { "Content-Type": "application/json", "X-Idempotency-Key": "stable-write-key" },
    body: JSON.stringify({ correctedCount: 18, reason: "verified correction reason" }),
  };

  const [first, second] = await Promise.all([
    client.authorizedResponse("inventory-sessions/a/corrections", write),
    client.authorizedResponse("inventory-sessions/b/corrections", write),
  ]);

  assert.equal(first.status, 200);
  assert.equal(second.status, 200);
  assert.equal(refreshCalls, 1);
  assert.deepEqual(replayedKeys, ["stable-write-key", "stable-write-key"]);
});

test("a late old-token 401 reuses the completed rotation", async () => {
  let releaseLate!: () => void;
  const late = new Promise<void>((resolve) => { releaseLate = resolve; });
  let rotations = 0;
  const client = new AuthenticatedBackendClient(() => undefined, async (path, token) => {
    if (path === "auth/refresh") { rotations++; return jsonResponse(newTokens); }
    if (token === oldTokens.accessToken) {
      if (path === "late") await late;
      return jsonResponse({}, 401);
    }
    return jsonResponse({});
  });
  client.installTokens(oldTokens);
  const pending = client.authorizedResponse("late");
  await client.authorizedResponse("first");
  releaseLate();
  assert.equal((await pending).status, 200);
  assert.equal(rotations, 1);
});

test("network failure during refresh clears the session", async () => {
  const changes: Array<TokenPair | null> = [];
  const client = new AuthenticatedBackendClient((pair) => changes.push(pair), async (path) => {
    if (path === "auth/refresh") throw new TypeError("network disconnected");
    return jsonResponse({}, 401);
  });
  client.installTokens(oldTokens);
  await assert.rejects(client.authorizedResponse("inventory-tasks"), /network disconnected/);
  assert.equal(changes.at(-1), null);
});

test("an old refresh cannot replace a newly logged-in session", async () => {
  let finishRefresh!: (response: Response) => void;
  let refreshStarted!: () => void;
  const started = new Promise<void>((resolve) => { refreshStarted = resolve; });
  const pendingRefresh = new Promise<Response>((resolve) => { finishRefresh = resolve; });
  const changes: Array<TokenPair | null> = [];
  const replacement = { ...newTokens, accessToken: "another-user" };
  const client = new AuthenticatedBackendClient((pair) => changes.push(pair), async (path, token) => {
    if (path === "auth/refresh") { refreshStarted(); return pendingRefresh; }
    return jsonResponse({}, token === replacement.accessToken ? 200 : 401);
  });
  client.installTokens(oldTokens);
  const pending = client.authorizedResponse("inventory-tasks");
  await started;
  client.installTokens(replacement);
  finishRefresh(jsonResponse(newTokens));
  await assert.rejects(pending, /登录会话已更换/);
  assert.equal(changes.at(-1), replacement);
  assert.equal((await client.authorizedResponse("inventory-tasks")).status, 200);
});

test("fetchBackend preserves Headers and tuple input and uses the current bearer token", async (context) => {
  const observed: Headers[] = [];
  context.mock.method(globalThis, "fetch", async (_url: unknown, init: RequestInit) => {
    observed.push(new Headers(init.headers));
    return jsonResponse({});
  });
  for (const headers of [new Headers({ "X-Idempotency-Key": "stable-key" }), [["X-Idempotency-Key", "stable-key"]] as [string, string][]]) {
    await fetchBackend("inventory-sessions/a/corrections", "current-token", { method: "POST", headers });
  }
  for (const headers of observed) {
    assert.equal(headers.get("X-Idempotency-Key"), "stable-key");
    assert.equal(headers.get("Authorization"), "Bearer current-token");
  }
});

test("clears the in-memory session when refresh rotation fails", async () => {
  const changes: Array<TokenPair | null> = [];
  const fetcher: BackendFetcher = async (path) => path === "auth/refresh"
    ? jsonResponse({ detail: "refresh expired" }, 401)
    : jsonResponse({ detail: "access expired" }, 401);
  const client = new AuthenticatedBackendClient((tokens) => changes.push(tokens), fetcher);
  client.installTokens(oldTokens);

  await assert.rejects(
    client.authorizedResponse("inventory-tasks"),
    (cause: unknown) => cause instanceof BackendApiError && cause.status === 401,
  );
  assert.equal(changes.at(-1), null);
  await assert.rejects(client.authorizedResponse("inventory-tasks"), /请先登录/);
});

test("clears the in-memory session when the retried request is still unauthorized", async () => {
  const changes: Array<TokenPair | null> = [];
  const fetcher: BackendFetcher = async (path) => path === "auth/refresh"
    ? jsonResponse(newTokens)
    : jsonResponse({ detail: "still unauthorized" }, 401);
  const client = new AuthenticatedBackendClient((tokens) => changes.push(tokens), fetcher);
  client.installTokens(oldTokens);

  const response = await client.authorizedResponse("inventory-tasks");

  assert.equal(response.status, 401);
  assert.equal(changes.at(-1), null);
});
