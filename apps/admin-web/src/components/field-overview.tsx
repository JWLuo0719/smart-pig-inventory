"use client";

import Image from "next/image";
import { FormEvent, useEffect, useState } from "react";

type Task = { penId: string; buildingCode: string; buildingName: string; penCode: string; penName: string; sessionId: string | null; status: string; confirmedCount: number | null };
type NearDuplicate = { id: string; sessionId: string; sourceMediaId: string; candidateMediaId: string; hammingDistance: number; state: "open" | "resolved"; createdAt: string; resolvedAt: string | null };
type Evidence = { assetId: string; viewPosition: string; contentType: string; byteSize: number; state: string; locked: boolean; deleted: boolean };
type Session = { id: string; penId: string; businessDate: string; status: string; count: number | null; rawModelCount: number | null; warnings: string[] };
type DailyRecord = { sessionId: string; penId: string; buildingCode: string; penCode: string; businessDate: string; confirmedCount: number };
type Aggregate = { penId: string; from: string; to: string; rawMean: number | null; roundedCount: number | null; includedDates: string[] };
type AuditEvent = { id: string; actorId: string; action: string; targetType: string; targetId: string; reason: string | null; before: unknown; after: unknown; correlationId: string; createdAt: string };
type TokenPair = { accessToken: string };

function idempotencyKey(): string {
  if (typeof globalThis.crypto?.randomUUID === "function") return globalThis.crypto.randomUUID();
  const bytes = new Uint8Array(16);
  if (typeof globalThis.crypto?.getRandomValues === "function") globalThis.crypto.getRandomValues(bytes);
  else for (let index = 0; index < bytes.length; index++) bytes[index] = Math.floor(Math.random() * 256);
  bytes[6] = (bytes[6] & 0x0f) | 0x40; bytes[8] = (bytes[8] & 0x3f) | 0x80;
  const hex = [...bytes].map((byte) => byte.toString(16).padStart(2, "0")).join("");
  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20)}`;
}
function today(): string { return new Date().toLocaleDateString("en-CA"); }
function safeMessage(cause: unknown): string { return cause instanceof Error ? cause.message : "无法完成请求；业务数据未被修改。"; }

async function api<T>(path: string, token: string, init?: RequestInit): Promise<T> {
  const response = await fetch(`/api/backend/${path}`, { ...init, headers: { Authorization: `Bearer ${token}`, ...(init?.headers ?? {}) }, cache: "no-store" });
  if (!response.ok) {
    const body = await response.json().catch(() => null) as { detail?: string; message?: string } | null;
    throw new Error(body?.detail ?? body?.message ?? `请求失败（HTTP ${response.status}）`);
  }
  return response.json() as Promise<T>;
}

function EvidencePreview({ evidence, token }: { evidence: Evidence; token: string }) {
  const [url, setUrl] = useState<string | null>(null);
  useEffect(() => {
    if (evidence.deleted) return;
    let current: string | null = null; let cancelled = false;
    fetch(`/api/backend/media-assets/${evidence.assetId}/content`, { headers: { Authorization: `Bearer ${token}` }, cache: "no-store" })
      .then(async (response) => { if (!response.ok) throw new Error(); return response.blob(); })
      .then((blob) => { current = URL.createObjectURL(blob); if (!cancelled) setUrl(current); })
      .catch(() => { if (!cancelled) setUrl(null); });
    return () => { cancelled = true; if (current) URL.revokeObjectURL(current); };
  }, [evidence.assetId, evidence.deleted, token]);
  return <figure className="evidence-card"><div className="evidence-image">{evidence.deleted ? <span>已删除<br />保留审计</span> : url ? <Image src={url} alt={`${evidence.viewPosition} 原始证据预览`} width={640} height={480} unoptimized /> : <span>证据不可用</span>}</div><figcaption><strong>{evidence.viewPosition}</strong><span>{evidence.locked ? "证据已锁定" : evidence.state}</span></figcaption></figure>;
}

export function FieldOverview() {
  const [username, setUsername] = useState(""); const [password, setPassword] = useState(""); const [token, setToken] = useState<string | null>(null);
  const [tasks, setTasks] = useState<Task[]>([]); const [duplicates, setDuplicates] = useState<NearDuplicate[]>([]); const [daily, setDaily] = useState<DailyRecord[]>([]); const [aggregate, setAggregate] = useState<Aggregate | null>(null); const [audit, setAudit] = useState<AuditEvent[]>([]);
  const [selected, setSelected] = useState<Session | null>(null); const [evidence, setEvidence] = useState<Evidence[]>([]); const [error, setError] = useState<string | null>(null); const [loading, setLoading] = useState(false);

  async function loadReports(accessToken: string, rows: Task[]) {
    const date = today(); const reports = await api<DailyRecord[]>(`inventory-reports/daily?businessDate=${date}`, accessToken); setDaily(reports);
    const penId = rows[0]?.penId;
    setAggregate(penId ? await api<Aggregate>(`inventory-reports/aggregate?penId=${encodeURIComponent(penId)}&from=${date}&to=${date}`, accessToken) : null);
  }
  async function refresh(accessToken: string) {
    setLoading(true); setError(null);
    try {
      const taskRows = await api<Task[]>(`inventory-tasks?businessDate=${today()}`, accessToken);
      const [duplicateResult, auditResult] = await Promise.allSettled([
        api<NearDuplicate[]>("review/near-duplicates", accessToken),
        api<AuditEvent[]>("audit-events?limit=30", accessToken),
      ]);
      setTasks(taskRows);
      setDuplicates(duplicateResult.status === "fulfilled" ? duplicateResult.value : []);
      setAudit(auditResult.status === "fulfilled" ? auditResult.value : []);
      await loadReports(accessToken, taskRows);
    } catch (cause) { setError(safeMessage(cause)); } finally { setLoading(false); }
  }
  async function login(event: FormEvent<HTMLFormElement>) {
    event.preventDefault(); setLoading(true); setError(null);
    try { const response = await fetch("/api/backend/auth/login", { method: "POST", headers: { "Content-Type": "application/json", "X-Idempotency-Key": idempotencyKey() }, body: JSON.stringify({ username, password }) }); if (!response.ok) throw new Error("登录失败；请检查账号、口令和管理端 API 配置。"); const pair = await response.json() as TokenPair; setToken(pair.accessToken); await refresh(pair.accessToken); } catch (cause) { setError(safeMessage(cause)); setLoading(false); }
  }
  async function openSession(sessionId: string) {
    if (!token) return; setLoading(true); setError(null);
    try { const [session, media] = await Promise.all([api<Session>(`inventory-sessions/${sessionId}`, token), api<Evidence[]>(`inventory-sessions/${sessionId}/media`, token)]); setSelected(session); setEvidence(media); document.getElementById("media-review")?.scrollIntoView({ behavior: "smooth" }); } catch (cause) { setError(safeMessage(cause)); } finally { setLoading(false); }
  }
  async function confirmSelected() {
    if (!token || !selected) return; const value = window.prompt("确认数量（非负整数）", selected.count?.toString() ?? ""); if (value === null) return; const count = Number(value); if (!Number.isInteger(count) || count < 0) { setError("确认数量必须是非负整数。"); return; }
    const reason = window.prompt("人工确认/修正原因（至少 8 个字符）", ""); if (reason === null || reason.trim().length < 8) { setError("确认、修改或候选数量为空时必须填写至少 8 个字符的原因。"); return; }
    setLoading(true); try { const result = await api<Session>(`inventory-sessions/${selected.id}/confirm`, token, { method: "POST", headers: { "Content-Type": "application/json", "X-Idempotency-Key": idempotencyKey() }, body: JSON.stringify({ confirmedCount: count, reason: reason.trim() }) }); setSelected(result); await refresh(token); } catch (cause) { setError(safeMessage(cause)); } finally { setLoading(false); }
  }
  async function resolveDuplicate(item: NearDuplicate) {
    if (!token) return; const reason = window.prompt("解决近重复告警的依据（至少 8 个字符）；不会删除媒体", ""); if (reason === null || reason.trim().length < 8) { setError("解决告警必须填写至少 8 个字符的依据。"); return; }
    setLoading(true); try { await api<NearDuplicate>(`review/near-duplicates/${item.id}/resolve`, token, { method: "POST", headers: { "Content-Type": "application/json", "X-Idempotency-Key": idempotencyKey() }, body: JSON.stringify({ reason: reason.trim() }) }); await refresh(token); } catch (cause) { setError(safeMessage(cause)); } finally { setLoading(false); }
  }

  if (!token) return <section className="panel" aria-labelledby="admin-login-title"><div className="section-heading"><div><span className="eyebrow">受认证访问</span><h2 id="admin-login-title">登录现场作业台</h2></div></div><p>登录后仅在当前浏览器内存中使用访问令牌，不会写入本地存储。</p><form onSubmit={login} className="login-form"><label>账号<input value={username} onChange={(event) => setUsername(event.target.value)} autoComplete="username" required /></label><label>口令<input value={password} onChange={(event) => setPassword(event.target.value)} type="password" autoComplete="current-password" required /></label><button className="primary-button" disabled={loading} type="submit">{loading ? "登录中…" : "登录并加载数据"}</button></form>{error && <p role="alert" className="form-error">{error}</p>}</section>;

  const confirmed = tasks.filter((task) => task.status === "confirmed").length; const review = tasks.filter((task) => task.status === "review_required").length;
  return <div className="workspace" id="top"><section className="attention-strip" aria-labelledby="attention-title"><div><span className="eyebrow">{today()} · 实时业务数据</span><h2 id="attention-title">现场盘点态势</h2></div><div className="attention-counts"><strong>{confirmed}<span>已确认</span></strong><strong>{review}<span>待复核</span></strong><strong>{duplicates.length}<span>近重复告警</span></strong></div></section>{error && <p role="alert" className="form-error">{error}</p>}
    <section id="tasks" className="panel"><div className="section-heading"><div><span className="eyebrow">栏舍任务</span><h2>今日盘点</h2></div><button className="text-button" onClick={() => refresh(token)} disabled={loading}>刷新</button></div><div className="pen-grid">{tasks.map((task) => <article className={`pen-plate ${task.status === "confirmed" ? "confirmed" : task.status === "review_required" ? "review" : "uploading"}`} key={task.penId}><div className="pen-rail" /><div className="pen-head"><span>{task.buildingCode} {task.buildingName}</span><strong>{task.penCode}栏</strong></div><div className="pen-body"><span className="state-label">{task.status}</span><div className="count"><strong>{task.confirmedCount ?? "—"}</strong><span>头</span></div><p>{task.penName}</p></div>{task.sessionId && <button onClick={() => openSession(task.sessionId!)}>查看会话证据 <span>→</span></button>}</article>)}{!loading && tasks.length === 0 && <p>今日暂无可见栏舍任务。</p>}</div></section>
    <section id="media-review" className="panel"><div className="section-heading"><div><span className="eyebrow">会话媒体审核</span><h2>{selected ? `${selected.businessDate} · ${selected.status}` : "选择一个盘点会话"}</h2></div>{selected?.status === "review_required" && <button className="primary-inline" onClick={confirmSelected} disabled={loading}>人工确认并锁定证据</button>}</div>{selected ? <><p className="muted-copy">数量：{selected.count ?? "服务器未返回可用数量"}。确认、删除和覆盖均受后端角色、组织与审计规则强制约束。</p><div className="evidence-grid">{evidence.map((item) => <EvidencePreview key={item.assetId} evidence={item} token={token} />)}</div>{evidence.length === 0 && <p>该会话没有可见的媒体证据。</p>}</> : <p>从任务卡片打开会话后，才会按当前组织权限加载原始证据；对象存储 URL 不会暴露给浏览器。</p>}</section>
    <div className="content-grid"><section id="duplicate-review" className="panel"><div className="section-heading"><div><span className="eyebrow">证据复核</span><h2>近重复告警</h2></div></div><ol className="queue-list">{duplicates.map((item) => <li key={item.id}><span className="queue-icon review">!</span><div><strong>汉明距离 {item.hammingDistance}</strong><p>媒体 {item.sourceMediaId.slice(0, 8)} 与 {item.candidateMediaId.slice(0, 8)}；仅提示，原图未删除。</p></div><button className="text-button" onClick={() => resolveDuplicate(item)} disabled={loading}>解决并审计</button></li>)}{!loading && duplicates.length === 0 && <li><span className="queue-icon">✓</span><div><strong>暂无待处理告警</strong><p>系统不会将无告警误作已审核。</p></div></li>}</ol></section>
      <section id="reports" className="panel"><div className="section-heading"><div><span className="eyebrow">已确认数据</span><h2>日报与综合</h2></div></div><p className="summary-number">日盘：{daily.length} 条已确认记录</p><p className="muted-copy">综合均值（首个可见栏舍、当日）：{aggregate?.rawMean ?? "—"}；展示数量：{aggregate?.roundedCount ?? "—"}</p><ul className="report-list">{daily.map((row) => <li key={row.sessionId}>{row.buildingCode} / {row.penCode}<strong>{row.confirmedCount} 头</strong></li>)}{daily.length === 0 && <li>无已确认记录；待复核结果绝不计入报表。</li>}</ul></section></div>
    <section id="audit" className="panel"><div className="section-heading"><div><span className="eyebrow">不可变记录</span><h2>审计日志</h2></div></div><div className="audit-list">{audit.map((event) => <article key={event.id}><strong>{event.action}</strong><span>{new Date(event.createdAt).toLocaleString()}</span><p>{event.targetType} · {event.targetId}{event.reason ? ` · ${event.reason}` : ""}</p></article>)}{audit.length === 0 && <p>当前组织没有可见审计记录，或当前账号没有审计查看权限。</p>}</div></section>
  </div>;
}
