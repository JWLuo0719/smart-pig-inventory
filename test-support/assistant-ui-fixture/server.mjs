// UI-only loopback fixture. This is not a business API, real JWT issuer, model or product fallback.
import http from "node:http";
const pen = "00000000-0000-4000-8000-000000000101";
const session = "00000000-0000-4000-8000-000000000102";
const ref = (date) => ({ kind: "session", id: session, businessDate: date });
const fact = (tool, date, data) => ({ schemaVersion: "1.0", tool, status: "ok", generatedAt: new Date().toISOString(), data, evidence: [ref(date)] });
const server = http.createServer(async (req, res) => {
  let input = ""; for await (const chunk of req) { input += chunk; if (input.length > 32768) { res.writeHead(413).end(); return; } }
  let body = {}; try { body = input ? JSON.parse(input) : {}; } catch { res.writeHead(422).end(); return; }
  const url = new URL(req.url, "http://127.0.0.1");
  const reply = (status, value) => { res.writeHead(status, { "Content-Type": "application/json", "Cache-Control": "no-store" }); res.end(JSON.stringify(value)); };
  if (url.pathname === "/api/v1/auth/login") {
    if (body.username !== "ui-fixture" || body.password !== "synthetic-ui-only-2026") return reply(401, { message: "合成测试账号输入不匹配。" });
    return reply(200, { accessToken: "synthetic-ui-access", refreshToken: "synthetic-ui-refresh", accessTokenExpiresAt: "2099-01-01T00:00:00Z", refreshTokenExpiresAt: "2099-01-01T00:00:00Z" });
  }
  if (req.headers.authorization !== "Bearer synthetic-ui-access") return reply(401, { message: "此服务只接受合成UI测试身份。" });
  if (url.pathname === "/api/v1/auth/logout") return reply(200, {});
  if (url.pathname === "/api/v1/assistant/status") return reply(200, { enabled: true, model: "synthetic-ui-fixture", promptVersion: "fixture-only" });
  if (url.pathname === "/api/v1/inventory-tasks") return reply(200, [{ penId: pen, penCode: "合成栏舍A", penName: "仅供界面检查", buildingCode: "合成栋舍", sessionId: session, status: "review_required" }]);
  if (url.pathname === "/api/v1/assistant/tools/inspect-session") return reply(200, fact("inspect_session", "2026-11-02", { sessionId: session, state: "review_required", candidateCount: 12, confirmedCount: null, issues: ["review_required"] }));
  if (url.pathname === "/api/v1/assistant/chat") {
    const date = body.businessDate; const message = String(body.message);
    const tool = message.includes("历史") || message.includes("最近") ? "get_pen_history" : message.includes("业务日") || message.includes("待办") ? "get_day_overview" : "inspect_session";
    const data = tool === "inspect_session" ? { sessionId: session, state: "review_required", candidateCount: 12, confirmedCount: null, issues: ["review_required"] }
      : tool === "get_day_overview" ? { scopePenCount: 1, confirmedPenCount: 0, confirmedHeads: null, rows: [{ penId: pen, sessionId: session, state: "review_required", confirmedCount: null, candidateCount: 12 }], hasMore: false }
      : { penId: pen, scopeBasis: "current_enabled_pens", points: [{ date, confirmedCount: null }] };
    return reply(200, { requestId: "00000000-0000-4000-8000-000000000103", status: "ok", answer: "这是合成界面测试输出。请结合事实卡核对原图，人工确认后再形成正式记录。", facts: [fact(tool, date, data)], evidence: [ref(date)], model: "synthetic-ui-fixture", promptVersion: "fixture-only", elapsedMs: 1, toolCalls: 1 });
  }
  return reply(404, { message: "合成测试服务没有该路由。" });
});
server.listen(18096, "127.0.0.1", () => process.stdout.write("Synthetic UI fixture listening on loopback 18096\n"));
