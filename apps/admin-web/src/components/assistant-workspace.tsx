"use client";

import Link from "next/link";
import { useEffect, useRef, useState, type FormEvent } from "react";
import { AuthenticatedBackendClient, fetchBackend, newIdempotencyKey, readResponseData, type TokenPair } from "@/lib/authenticated-backend-client";
import { AssistantRequestScope, agentStateLabel, displayCount, evidencePath, parseReply, samplePrompts, type AgentReply, type ChatTurn, type EvidenceRef, type ToolFact } from "@/lib/assistant-chat";
import { inventoryStatusLabel } from "@/lib/presentation-labels";

type Task = { penId: string; penCode: string; penName: string; buildingCode: string; sessionId: string | null; status: string };
type Status = { enabled: boolean; model: string; promptVersion: string };
function localDate() { const now = new Date(); return `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, "0")}-${String(now.getDate()).padStart(2, "0")}`; }
function textError(value: unknown) { return value instanceof Error ? value.message : "无法完成查询，请稍后重试。"; }

function FactCard({ fact, tasks }: { fact: ToolFact; tasks: Task[] }) {
  const data = fact.data;
  const title = ({ inspect_session: "本次盘点", get_day_overview: "当日盘点概况", get_pen_history: "确认历史" } as Record<string, string>)[fact.tool] ?? "查询结果";
  if (!data || fact.status !== "ok") return <article className="assistant-fact"><h3>{title}</h3><p>尚未取得可用事实，请补充所选记录或稍后重试。</p></article>;
  const rows = Array.isArray(data.rows) ? data.rows as Record<string, unknown>[] : [];
  const points = Array.isArray(data.points) ? data.points as Record<string, unknown>[] : [];
  return <article className="assistant-fact"><h3>{title}</h3>
    {fact.tool === "inspect_session" && <><p>状态：{inventoryStatusLabel(String(data.state))}</p><dl><dt>AI 候选</dt><dd>{displayCount(data.candidateCount)}</dd><dt>人工确认</dt><dd>{displayCount(data.confirmedCount)}</dd></dl><p>候选需经人工核对，正式报表取确认记录。</p></>}
    {fact.tool === "get_day_overview" && <><p>查询时启用栏舍：{displayCount(data.scopePenCount)}；已有确认：{displayCount(data.confirmedPenCount)}；确认合计：{displayCount(data.confirmedHeads)}</p>{data.hasMore === true && <p className="assistant-notice">列表仅显示部分栏舍，汇总范围为全部启用栏舍。</p>}<div className="assistant-table"><table><thead><tr><th>栏舍引用</th><th>状态</th><th>候选</th><th>确认</th></tr></thead><tbody>{rows.map((row, i) => <tr key={i}><td>{tasks.find(task => task.penId === row.penId)?.penCode ?? "未载入栏舍名称"}</td><td>{inventoryStatusLabel(String(row.state))}</td><td>{displayCount(row.candidateCount)}</td><td>{displayCount(row.confirmedCount)}</td></tr>)}</tbody></table></div>{rows.length === 0 && <p>此查询范围没有启用栏舍。</p>}</>}
    {fact.tool === "get_pen_history" && <><p>仅显示确认记录；空缺为未知。查询时启用栏舍口径。</p><div className="assistant-table"><table><thead><tr><th>业务日</th><th>人工确认</th></tr></thead><tbody>{points.map((point, i) => <tr key={i}><td>{String(point.date)}</td><td>{displayCount(point.confirmedCount)}</td></tr>)}</tbody></table></div></>}
  </article>;
}

export function AssistantWorkspace() {
  const [tokens, setTokens] = useState<TokenPair | null>(null);
  const [client] = useState(() => new AuthenticatedBackendClient(setTokens));
  const [scope] = useState(() => new AssistantRequestScope());
  const [username, setUsername] = useState(""); const [password, setPassword] = useState("");
  const [date, setDate] = useState(localDate); const [tasks, setTasks] = useState<Task[]>([]);
  const [penId, setPenId] = useState(""); const [question, setQuestion] = useState("");
  const [status, setStatus] = useState<Status | null>(null); const [history, setHistory] = useState<ChatTurn[]>([]);
  const [reply, setReply] = useState<AgentReply | null>(null); const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false); const [evidence, setEvidence] = useState<string | null>(null);
  const loginGeneration = useRef(0); const contextGeneration = useRef(0);
  const selected = tasks.find(task => task.penId === penId);

  useEffect(() => () => { scope.reset(); client.installTokens(null); loginGeneration.current++; }, [scope, client]);
  useEffect(() => {
    if (!tokens) { scope.reset(); }
  }, [tokens, scope]);

  function clearContext() { contextGeneration.current++; scope.reset(); setReply(null); setHistory([]); setEvidence(null); setError(null); setBusy(false); }

  async function loadContext(nextDate: string) {
    const identity = client.sessionRevision; const generation = contextGeneration.current;
    setTasks([]); setPenId(""); setStatus(null); setBusy(true);
    try {
      const [rows, info] = await Promise.all([client.authorizedData<Task[]>(`inventory-tasks?businessDate=${encodeURIComponent(nextDate)}`), client.authorizedData<Status>("assistant/status")]);
      if (identity !== client.sessionRevision || generation !== contextGeneration.current) return;
      setTasks(rows); setStatus(info);
    } catch (cause) { if (identity === client.sessionRevision && generation === contextGeneration.current) setError(textError(cause)); }
    finally { if (identity === client.sessionRevision && generation === contextGeneration.current) setBusy(false); }
  }

  async function login(event: FormEvent) {
    event.preventDefault(); clearContext(); client.installTokens(null); const generation = ++loginGeneration.current;
    setTasks([]); setStatus(null); setBusy(true);
    try {
      const response = await fetchBackend("auth/login", null, { method: "POST", headers: { "Content-Type": "application/json", "X-Idempotency-Key": newIdempotencyKey() }, body: JSON.stringify({ username, password }) });
      const pair = await readResponseData<TokenPair>(response);
      if (generation !== loginGeneration.current) return;
      setPassword(""); client.installTokens(pair); await loadContext(date);
    } catch (cause) { if (generation === loginGeneration.current) setError(textError(cause)); }
    finally { if (generation === loginGeneration.current) setBusy(false); }
  }

  function logout() {
    const previous = tokens; loginGeneration.current++; clearContext();
    if (previous) void client.authorizedResponse("auth/logout", { method: "POST", headers: { "Content-Type": "application/json", "X-Idempotency-Key": newIdempotencyKey() }, body: JSON.stringify({ refreshToken: previous.refreshToken }) }).catch(() => {});
    client.installTokens(null); setPassword(""); setTasks([]); setStatus(null); setPenId("");
  }

  async function ask(event: FormEvent) {
    event.preventDefault(); if (busy || !question.trim()) return;
    const request = scope.start(); const identity = client.sessionRevision; const message = question.trim();
    setBusy(true); setError(null); setReply(null); setEvidence(null);
    // Client cancellation discards the reply; the server independently limits remaining work to 60s.
    const timer = window.setTimeout(() => { if (request.current()) { scope.reset(); setBusy(false); setError("等待较久，请稍后重新查询；业务记录未被修改。"); } }, 65000);
    try {
      const value = await client.authorizedData<unknown>("assistant/chat", { method: "POST", signal: request.signal, headers: { "Content-Type": "application/json" }, body: JSON.stringify({ message, businessDate: date, penId: penId || null, sessionId: selected?.sessionId ?? null, history: history.slice(-6) }) });
      if (!request.current() || identity !== client.sessionRevision) return;
      const result = parseReply(value); setReply(result);
      if (result.answer) setHistory(previous => [...previous, { role: "user", content: message } as ChatTurn, { role: "assistant", content: result.answer!.slice(0, 2000) } as ChatTurn].slice(-6));
    } catch (cause) { if (request.current() && identity === client.sessionRevision) setError(textError(cause)); }
    finally { window.clearTimeout(timer); if (request.current() && identity === client.sessionRevision) setBusy(false); }
  }

  async function openEvidence(ref: EvidenceRef) {
    const path = evidencePath(ref); if (!path) return;
    const request = scope.start(); const identity = client.sessionRevision; setBusy(true); setError(null); setEvidence(null);
    try {
      const value = await client.authorizedData<unknown>(ref.kind === "session" ? "assistant/tools/inspect-session" : path,
        ref.kind === "session" ? { method: "POST", signal: request.signal, headers: { "Content-Type": "application/json" }, body: JSON.stringify({ tool: "inspect_session", arguments: { sessionId: ref.id } }) } : { signal: request.signal });
      if (!request.current() || identity !== client.sessionRevision) return;
      // Evidence readback displays only counts/status and date, never model identity, errors or storage metadata.
      if (ref.kind === "session") {
        const result = value as ToolFact;
        if (result.status !== "ok" || !result.data) throw new Error("该证据暂不可读，请重新查询。");
        setEvidence(`业务日 ${ref.businessDate}；${inventoryStatusLabel(String(result.data.state))}；AI候选 ${displayCount(result.data.candidateCount)}；人工确认 ${displayCount(result.data.confirmedCount)}`);
      } else {
        const rows = value as { confirmedCount: number }[];
        setEvidence(`业务日 ${ref.businessDate}；日报当前确认记录 ${rows.length} 条。日报范围可能包含后停用栏舍，概况汇总按查询时启用范围展示。`);
      }
    } catch (cause) { if (request.current() && identity === client.sessionRevision) setError(textError(cause)); }
    finally { if (request.current() && identity === client.sessionRevision) setBusy(false); }
  }

  return <main className="assistant-page"><header className="assistant-header"><div><span className="eyebrow">牧数智核 · 可信盘点</span><h1>盘点助手</h1><p>查依据、看确认、明确下一步。</p></div><Link href="/">作业台</Link></header>
    {!tokens ? <form className="assistant-login" onSubmit={login}><h2>登录体验</h2><p>使用获授权的体验账号，查看该账号所属范围内的盘点证据。</p><label>账号<input autoComplete="username" required maxLength={128} value={username} onChange={event => setUsername(event.target.value)} /></label><label>密码<input type="password" autoComplete="current-password" required minLength={8} maxLength={256} value={password} onChange={event => setPassword(event.target.value)} /></label><button disabled={busy} type="submit">{busy ? "正在登录…" : "登录"}</button></form>
      : <><section className="assistant-context"><div><h2>查询范围</h2><p>人工确认形成正式记录，助手提供只读解释。</p></div><label>业务日期<input type="date" required value={date} onChange={event => { const next = event.target.value; setDate(next); clearContext(); if (next) void loadContext(next); }} /></label><label>栏舍<select value={penId} disabled={busy} onChange={event => { setPenId(event.target.value); clearContext(); }}>{<option value="">当日全部启用栏舍</option>}{tasks.map(task => <option key={task.penId} value={task.penId}>{task.buildingCode} / {task.penCode} {task.penName}</option>)}</select></label><button type="button" onClick={() => { clearContext(); void loadContext(date); }} disabled={busy}>刷新范围</button><button type="button" onClick={logout}>退出</button></section>
        {status && !status.enabled && <p className="assistant-notice" role="status">智能问答尚未启用，请联系服务负责人完成模型配置。盘点记录不会因问答配置改变。</p>}
        <section className="assistant-chat"><div className="assistant-samples" aria-label="示例问题">{samplePrompts.map((prompt, index) => <button type="button" key={prompt} disabled={busy} onClick={() => setQuestion(prompt)}><strong>{["核对本次盘点", "查看当日待办", "解释确认历史"][index]}</strong><span>{prompt}</span></button>)}</div>
          <form onSubmit={ask}><label htmlFor="assistant-question">你想了解什么？</label><textarea id="assistant-question" value={question} maxLength={2000} required rows={3} disabled={busy} onChange={event => setQuestion(event.target.value)} /><div className="assistant-actions"><button type="submit" disabled={busy || !status?.enabled || !date}>{busy ? "正在查证据…" : "查询"}</button><button type="button" onClick={clearContext}>清空对话{busy ? "并停止等待" : ""}</button></div></form>
          {reply && <section className="assistant-answer" aria-live="polite"><h2>{agentStateLabel(reply.status)}</h2>{reply.answer && <p className="assistant-explanation">{reply.answer}</p>}<p className="assistant-caption">事实卡来自本次查询；模型解释仍需结合现场核对。</p><div className="assistant-facts">{reply.facts.map((fact, index) => <FactCard fact={fact} tasks={tasks} key={index} />)}</div>{reply.evidence.length > 0 && <div className="assistant-evidence"><h3>核对来源</h3><p>最多展示五十条来源。点击后重新检查权限并读取当前记录。</p>{reply.evidence.map((ref, index) => <button type="button" key={index} disabled={busy || !evidencePath(ref)} onClick={() => void openEvidence(ref)}>来源 {index + 1} · {ref.businessDate} · {ref.kind === "session" ? "盘点记录" : "确认日报"}</button>)}</div>}<details><summary>本次查询记录</summary><p>请求编号 {reply.requestId}；模型 {reply.model}；提示词版本 {reply.promptVersion}；耗时 {reply.elapsedMs} 毫秒。</p></details></section>}
          {evidence && <p className="assistant-readback" role="status">{evidence}</p>}
        </section></>}
    {error && <p className="assistant-error" role="alert">{error}</p>}<footer className="assistant-footer">仅提供证据查询和复核建议。疾病、经营归因和未验证功能不在本次能力范围内。</footer></main>;
}
