"use client";

import Image from "next/image";
import { ReviewCommandForm } from "./review-command-form";
import { InventoryVersionPanel } from "./inventory-version-panel";
import { containRect } from "@/lib/review-command";
import { directionLabel, evidenceStateLabel, inferenceSourceLabel, inventoryStatusLabel } from "@/lib/presentation-labels";
import { MasterDataPanel } from "./master-data-panel";
import { InventoryHistoryPanel } from "./inventory-history-panel";
import { MediaLibraryPanel } from "./media-library-panel";
import { FormEvent, useCallback, useEffect, useRef, useState } from "react";
import { canReadPanel, loadOptionalPanel, panelCount, type PanelState } from "@/lib/optional-panel";

import {
  AuthenticatedBackendClient,
  BackendApiError,
  fetchBackend,
  newIdempotencyKey,
  readResponseData,
  type TokenPair,
} from "@/lib/authenticated-backend-client";

type Task = { penId: string; buildingCode: string; buildingName: string; penCode: string; penName: string; sessionId: string | null; status: string; confirmedCount: number | null };
type NearDuplicate = { id: string; sessionId: string; sourceMediaId: string; candidateMediaId: string; hammingDistance: number; state: "open" | "resolved"; createdAt: string; resolvedAt: string | null };
type Evidence = { assetId: string; viewPosition: string; contentType: string; byteSize: number; state: string; locked: boolean; deleted: boolean };
type Detection = { assetId: string; bbox: [number, number, number, number]; confidence: number; classId: number };
type ModelIdentity = { modelKey: string; version: string; checksum: string; adapterVersion: string };
type Session = { id: string; penId: string; businessDate: string; status: string; version: number; supersedesSessionId: string | null; evidenceSessionId: string; count: number | null; rawModelCount: number | null; inferenceSource: string | null; model: ModelIdentity | null; detections: Detection[]; latencyMs: number | null; warnings: string[]; inferenceStatus: string | null; failureCode: string | null; failureMessage: string | null };
type DailyRecord = { sessionId: string; penId: string; buildingCode: string; penCode: string; businessDate: string; confirmedCount: number };
type Aggregate = { penId: string; from: string; to: string; rawMean: number | null; roundedCount: number | null; includedDates: string[] };
type AuditEvent = { id: string; actorId: string; action: string; targetType: string; targetId: string; reason: string | null; before: unknown; after: unknown; correlationId: string; createdAt: string };
type FailedInferenceJob = { jobId: string; rootJobId: string; retryOfJobId: string | null; retriedByJobId: string | null; sessionId: string; captureSetId: string; status: "failed"; retrySequence: number; failureCode: string | null; failureMessage: string | null; requestedModel: ModelIdentity; providerKey: string; retryable: boolean; retryBlockedReason: string | null; startedAt: string | null; finishedAt: string | null; createdAt: string };
type CurrentUser = { activeOrganizationId: string; memberships: { organizationId: string; roles: string[] }[] };

function idempotencyKey(): string {
  return newIdempotencyKey();
}
function today(): string { return new Date().toLocaleDateString("en-CA"); }
function safeMessage(cause: unknown): string { return cause instanceof Error ? cause.message : "无法完成请求；业务数据未被修改。"; }

function PanelFeedback({ state, emptyMessage, loading, retry }: { state: PanelState<unknown>; emptyMessage: string; loading: boolean; retry: () => void }) {
  if (state.status === "ready") return state.data.length === 0 ? <p role="status">{emptyMessage}</p> : null;
  if (state.status === "error") return <div role="alert" className="form-error"><p>{state.message}</p><button className="text-button" disabled={loading} onClick={retry}>刷新重试</button></div>;
  return <p role="status">{state.status === "forbidden" ? "当前账号无此面板的查看权限。" : "正在加载，请稍候…"}</p>;
}

function EvidencePreview({ evidence, detections, loadContent }: { evidence: Evidence; detections: Detection[]; loadContent: (assetId: string) => Promise<Blob> }) {
  const [url, setUrl] = useState<string | null>(null);
  const [dimensions, setDimensions] = useState({ width: 640, height: 480 });
  const [box, setBox] = useState({ width: 640, height: 480 });
  const container = useRef<HTMLDivElement>(null);
  useEffect(() => {
    const node = container.current;
    if (!node) return;
    const observer = new ResizeObserver(([entry]) => setBox({ width: entry.contentRect.width, height: entry.contentRect.height }));
    observer.observe(node); return () => observer.disconnect();
  }, []);
  const fitted = containRect(dimensions.width, dimensions.height, box.width, box.height);
  useEffect(() => {
    if (evidence.deleted) return;
    let current: string | null = null; let cancelled = false;
    loadContent(evidence.assetId)
      .then((blob) => { if (cancelled) return; current = URL.createObjectURL(blob); setUrl(current); })
      .catch(() => { if (!cancelled) setUrl(null); });
    return () => { cancelled = true; if (current) URL.revokeObjectURL(current); };
  }, [evidence.assetId, evidence.deleted, loadContent]);
  return <figure className="evidence-card"><div className="evidence-image" ref={container}>{evidence.deleted ? <span>已删除<br />保留审计</span> : url ? <>{evidence.contentType === "video/mp4" ? <video src={url} controls preload="metadata" aria-label="视频原始证据" style={{ width: "100%", maxHeight: 480 }} /> : <Image src={url} alt={`${directionLabel(evidence.viewPosition)} 原始证据预览，叠加 ${detections.length} 个 AI 候选框`} width={640} height={480} unoptimized onLoad={(event) => setDimensions({ width: event.currentTarget.naturalWidth, height: event.currentTarget.naturalHeight })} />}{detections.map((detection, index) => <span className="detection-box" aria-label={`候选 ${index + 1}，置信度 ${(detection.confidence * 100).toFixed(1)}%`} key={`${detection.assetId}-${index}`} style={{ left: fitted.left + detection.bbox[0] * fitted.width, top: fitted.top + detection.bbox[1] * fitted.height, width: (detection.bbox[2] - detection.bbox[0]) * fitted.width, height: (detection.bbox[3] - detection.bbox[1]) * fitted.height }}><small>{index + 1} · {(detection.confidence * 100).toFixed(0)}%</small></span>)}</> : <span>证据不可用</span>}</div><figcaption><strong>{directionLabel(evidence.viewPosition)} · {detections.length} 个候选</strong><span>{evidence.locked ? "证据已锁定" : evidenceStateLabel(evidence.state)}</span></figcaption></figure>;
}

export function FieldOverview() {
  const [username, setUsername] = useState(""); const [password, setPassword] = useState(""); const [tokens, setTokens] = useState<TokenPair | null>(null);
  const [tasks, setTasks] = useState<Task[]>([]); const [duplicatePanel, setDuplicatePanel] = useState<PanelState<NearDuplicate>>({ status: "loading" }); const [failedJobPanel, setFailedJobPanel] = useState<PanelState<FailedInferenceJob>>({ status: "loading" }); const [daily, setDaily] = useState<DailyRecord[]>([]); const [aggregate, setAggregate] = useState<Aggregate | null>(null); const [auditPanel, setAuditPanel] = useState<PanelState<AuditEvent>>({ status: "loading" });
  const duplicates = duplicatePanel.status === "ready" ? duplicatePanel.data : [];
  const failedJobs = failedJobPanel.status === "ready" ? failedJobPanel.data : [];
  const audit = auditPanel.status === "ready" ? auditPanel.data : [];
  const [currentUser, setCurrentUser] = useState<CurrentUser | null>(null);
  const [selected, setSelected] = useState<Session | null>(null); const [evidence, setEvidence] = useState<Evidence[]>([]); const [error, setError] = useState<string | null>(null); const [loading, setLoading] = useState(false);
  const [reportFrom, setReportFrom] = useState(today()); const [reportTo, setReportTo] = useState(today());

  const refreshGeneration = useRef(0);
  const sessionGeneration = useRef(0);
  const [reviewMode, setReviewMode] = useState<"confirm" | "correction" | null>(null);
  const onTokensChanged = useCallback((pair: TokenPair | null) => {
    setTokens(pair);
    if (pair === null) {
      setTasks([]); setDaily([]); setAggregate(null); setCurrentUser(null); setSelected(null); setEvidence([]); setLoading(false); setReviewMode(null);
      setDuplicatePanel({ status: "loading" }); setFailedJobPanel({ status: "loading" }); setAuditPanel({ status: "loading" });
    }
  }, []);
  const [authenticatedClient] = useState(() => new AuthenticatedBackendClient(onTokensChanged));
  const mediaCommands = useRef(new Map<string, string>());

  const authorizedResponse = useCallback(async (path: string, init?: RequestInit): Promise<Response> => {
    return authenticatedClient.authorizedResponse(path, init);
  }, [authenticatedClient]);

  const authorizedApi = useCallback(async <T,>(path: string, init?: RequestInit): Promise<T> => {
    return authenticatedClient.authorizedData<T>(path, init);
  }, [authenticatedClient]);

  const loadMediaContent = useCallback(async (assetId: string): Promise<Blob> => {
    const response = await authorizedResponse(`media-assets/${assetId}/content`);
    if (!response.ok) throw new BackendApiError(response.status, "媒体证据不可用。");
    return response.blob();
  }, [authorizedResponse]);

  const loadThumbnail = useCallback((assetId: string, signal: AbortSignal) => authenticatedClient.authorizedBlob(`media-assets/${assetId}/thumbnail`, { signal }), [authenticatedClient]);
  const sessionRevision = useCallback(() => authenticatedClient.sessionRevision, [authenticatedClient]);
  async function loadReports(rows: Task[]) {
    const date = today();
    const penId = rows[0]?.penId;
    const [reports, summary] = await Promise.all([
      authorizedApi<DailyRecord[]>(`inventory-reports/daily?businessDate=${date}`),
      penId ? authorizedApi<Aggregate>(`inventory-reports/aggregate?penId=${encodeURIComponent(penId)}&from=${date}&to=${date}`) : Promise.resolve(null),
    ]);
    return { reports, summary };
  }
  async function refresh() {
    const identity = authenticatedClient.sessionRevision;
    const generation = ++refreshGeneration.current;
    const isCurrent = () => identity === authenticatedClient.sessionRevision && generation === refreshGeneration.current;
    setLoading(true); setError(null);
    setDuplicatePanel({ status: "loading" }); setFailedJobPanel({ status: "loading" }); setAuditPanel({ status: "loading" });
    let identityLoaded = false;
    try {
      const [taskRows, user] = await Promise.all([
        authorizedApi<Task[]>(`inventory-tasks?businessDate=${today()}`),
        authorizedApi<CurrentUser>("me"),
      ]);
      if (!isCurrent()) return;
      setTasks(taskRows);
      setCurrentUser(user);
      identityLoaded = true;
      await Promise.all([
        loadOptionalPanel(canReadPanel(user, "duplicates"), () => authorizedApi<NearDuplicate[]>("review/near-duplicates")).then((value) => { if (isCurrent()) setDuplicatePanel(value); }),
        loadOptionalPanel(canReadPanel(user, "failedJobs"), () => authorizedApi<FailedInferenceJob[]>("inference-jobs/failed?limit=50")).then((value) => { if (isCurrent()) setFailedJobPanel(value); }),
        loadOptionalPanel(canReadPanel(user, "audit"), () => authorizedApi<AuditEvent[]>("audit-events?limit=30")).then((value) => { if (isCurrent()) setAuditPanel(value); }),
      ]);
      if (!isCurrent()) return;
      const { reports, summary } = await loadReports(taskRows);
      if (!isCurrent()) return;
      setDaily(reports); setAggregate(summary);
    } catch (cause) {
      if (!isCurrent()) return;
      if (!identityLoaded) {
        const unavailable = { status: "error", message: "加载失败，无法确认当前组织权限，请刷新重试。" } as const;
        setDuplicatePanel(unavailable); setFailedJobPanel(unavailable); setAuditPanel(unavailable); setCurrentUser(null);
      }
      setError(safeMessage(cause));
    } finally { if (isCurrent()) setLoading(false); }
  }
  async function login(event: FormEvent<HTMLFormElement>) {
    authenticatedClient.installTokens(null);
    const identity = authenticatedClient.sessionRevision;
    sessionGeneration.current++; refreshGeneration.current++;
    event.preventDefault(); setLoading(true); setError(null);
    setTasks([]); setDaily([]); setAggregate(null); setSelected(null); setEvidence([]); setCurrentUser(null);
    try { const response = await fetchBackend("auth/login", null, { method: "POST", headers: { "Content-Type": "application/json", "X-Idempotency-Key": idempotencyKey() }, body: JSON.stringify({ username, password }) }); if (!response.ok) throw new Error("登录失败；请检查账号、口令和管理端 API 配置。"); const pair = await readResponseData<TokenPair>(response); if (identity !== authenticatedClient.sessionRevision) return; authenticatedClient.installTokens(pair); await refresh(); } catch (cause) { if (identity === authenticatedClient.sessionRevision) { setError(safeMessage(cause)); setLoading(false); } }
  }
  async function openSession(sessionId: string) {
    if (!tokens) return; const identity = authenticatedClient.sessionRevision; const generation = ++sessionGeneration.current; const isCurrent = () => generation === sessionGeneration.current && identity === authenticatedClient.sessionRevision; setLoading(true); setError(null); setSelected(null); setEvidence([]); setReviewMode(null);
    try { const [session, media] = await Promise.all([authorizedApi<Session>(`inventory-sessions/${sessionId}`), authorizedApi<Evidence[]>(`inventory-sessions/${sessionId}/media`)]); if (!isCurrent()) return; setSelected(session); setEvidence(media); document.getElementById("media-review")?.scrollIntoView({ behavior: "smooth" }); } catch (cause) { if (isCurrent()) setError(safeMessage(cause)); } finally { if (isCurrent()) setLoading(false); }
  }
  function confirmSelected() { setReviewMode("confirm"); }
  async function resolveDuplicate(item: NearDuplicate) {
    if (!tokens) return; const reason = window.prompt("解决近重复告警的依据（至少 8 个字符）；不会删除媒体", ""); if (reason === null || reason.trim().length < 8) { setError("解决告警必须填写至少 8 个字符的依据。"); return; }
    const identity = authenticatedClient.sessionRevision;
    setLoading(true); try { await authorizedApi<NearDuplicate>(`review/near-duplicates/${item.id}/resolve`, { method: "POST", headers: { "Content-Type": "application/json", "X-Idempotency-Key": idempotencyKey() }, body: JSON.stringify({ reason: reason.trim() }) }); if (identity === authenticatedClient.sessionRevision) await refresh(); } catch (cause) { if (identity === authenticatedClient.sessionRevision) setError(safeMessage(cause)); } finally { if (identity === authenticatedClient.sessionRevision) setLoading(false); }
  }
  async function retryInference(job: FailedInferenceJob) {
    if (!tokens || !job.retryable) return; const reason = window.prompt("重试原因（至少 8 个字符）；原失败任务和媒体证据不会被覆盖", ""); if (reason === null || reason.trim().length < 8) { setError("管理员重试必须填写至少 8 个字符的原因。"); return; }
    const identity = authenticatedClient.sessionRevision;
    setLoading(true); setError(null); try { await authorizedApi(`inference-jobs/${job.jobId}/retries`, { method: "POST", headers: { "Content-Type": "application/json", "X-Idempotency-Key": idempotencyKey() }, body: JSON.stringify({ reason: reason.trim() }) }); if (identity !== authenticatedClient.sessionRevision) return; await refresh(); if (identity === authenticatedClient.sessionRevision && selected?.id === job.sessionId) await openSession(job.sessionId); } catch (cause) { if (identity === authenticatedClient.sessionRevision) setError(safeMessage(cause)); } finally { if (identity === authenticatedClient.sessionRevision) setLoading(false); }
  }
  function correctSelected() { setReviewMode("correction"); }
  async function deleteEvidence(item: Evidence) {
    if (!selected || item.deleted) return;
    const identity = authenticatedClient.sessionRevision;
    const reason = item.locked ? window.prompt("管理员覆盖删除依据（至少 8 个字符）；历史盘点数量和审计记录继续保留", "") : null;
    if (item.locked && reason === null) return;
    if (item.locked && reason!.trim().length < 8) { setError("覆盖删除必须填写至少 8 个字符的依据。"); return; }
    if (!item.locked && !window.confirm("删除这份错误证据？删除后该会话不能再确认，需要重新采集。")) return;
    const path = `media-assets/${item.assetId}${item.locked ? "/override-delete" : ""}`;
    const body = item.locked ? JSON.stringify({ reason: reason!.trim() }) : undefined;
    const intent = `${currentUser?.activeOrganizationId}:${path}:${body ?? ""}`;
    const key = mediaCommands.current.get(intent) ?? idempotencyKey();
    mediaCommands.current.set(intent, key);
    setLoading(true); setError(null);
    try {
      const response = await authorizedResponse(path, { method: item.locked ? "POST" : "DELETE", headers: { "Content-Type": "application/json", "X-Idempotency-Key": key }, body });
      if (!response.ok) await readResponseData(response);
      if (identity !== authenticatedClient.sessionRevision) return;
      await openSession(selected.id);
      if (identity === authenticatedClient.sessionRevision) await refresh();
    } catch (cause) { if (identity === authenticatedClient.sessionRevision) setError(safeMessage(cause)); } finally { if (identity === authenticatedClient.sessionRevision) setLoading(false); }
  }
  async function downloadReport(format: "pdf" | "xlsx") {
    if (!tokens) return;
    const identity = authenticatedClient.sessionRevision;
    if (!reportFrom || !reportTo || reportFrom > reportTo) { setError("导出开始日期不能晚于结束日期。"); return; }
    setLoading(true); setError(null);
    try {
      const response = await authorizedResponse(`inventory-reports/exports/${format}?from=${encodeURIComponent(reportFrom)}&to=${encodeURIComponent(reportTo)}`);
      if (!response.ok) { const body = await response.json().catch(() => null) as { detail?: string; message?: string } | null; throw new Error(body?.detail ?? body?.message ?? `导出失败（HTTP ${response.status}）`); }
      const blob = await response.blob(); if (identity !== authenticatedClient.sessionRevision) return; const disposition = response.headers.get("content-disposition") ?? "";
      const encoded = disposition.match(/filename\*=UTF-8''([^;]+)/i)?.[1]; const plain = disposition.match(/filename="?([^";]+)"?/i)?.[1];
      const filename = encoded ? decodeURIComponent(encoded) : plain ?? `pig-inventory-${reportFrom.replaceAll("-", "")}-${reportTo.replaceAll("-", "")}.${format}`;
      const url = URL.createObjectURL(blob); const anchor = document.createElement("a"); anchor.href = url; anchor.download = filename; document.body.appendChild(anchor); anchor.click(); anchor.remove(); URL.revokeObjectURL(url);
    } catch (cause) { if (identity === authenticatedClient.sessionRevision) setError(safeMessage(cause)); } finally { if (identity === authenticatedClient.sessionRevision) setLoading(false); }
  }

  if (!tokens) return <section className="panel" aria-labelledby="admin-login-title"><div className="section-heading"><div><span className="eyebrow">受认证访问</span><h2 id="admin-login-title">登录现场作业台</h2></div></div><p>登录后仅在当前浏览器内存中使用访问令牌和轮换令牌，不会写入本地存储。</p><form onSubmit={login} className="login-form"><label>账号<input value={username} onChange={(event) => setUsername(event.target.value)} autoComplete="username" required /></label><label>口令<input value={password} onChange={(event) => setPassword(event.target.value)} type="password" autoComplete="current-password" required /></label><button className="primary-button" disabled={loading} type="submit">{loading ? "登录中…" : "登录并加载数据"}</button></form>{error && <p role="alert" className="form-error">{error}</p>}</section>;
  const activeRoles = currentUser?.memberships.find((membership) => membership.organizationId === currentUser.activeOrganizationId)?.roles ?? [];
  const canConfirm = activeRoles.some((role) => ["REVIEWER", "FARM_ADMIN", "SYSTEM_ADMIN"].includes(role));
  const canCorrect = activeRoles.some((role) => role === "FARM_ADMIN" || role === "SYSTEM_ADMIN");

  const evidenceGrid = selected ? <div className="evidence-grid">{evidence.map((item) => <div key={item.assetId}><EvidencePreview evidence={item} loadContent={loadMediaContent} detections={selected.detections.filter((detection) => detection.assetId === item.assetId)} />{!reviewMode && !item.deleted && (!item.locked || canCorrect) ? <button className="text-button" disabled={loading} onClick={() => deleteEvidence(item)}>{item.locked ? "管理员覆盖删除" : "删除错误证据"}</button> : null}</div>)}</div> : null;
  const confirmed = tasks.filter((task) => task.status === "confirmed").length; const review = tasks.filter((task) => task.status === "review_required").length;
  return <div className="workspace" id="top"><section className="attention-strip" aria-labelledby="attention-title"><div><span className="eyebrow">{today()} · 实时业务数据</span><h2 id="attention-title">现场盘点态势</h2></div><div className="attention-counts"><strong>{confirmed}<span>已确认</span></strong><strong>{review}<span>待复核</span></strong><strong>{panelCount(duplicatePanel) ?? "—"}<span>近重复告警</span></strong></div></section>{error && <p role="alert" className="form-error">{error}</p>}
    <section id="tasks" className="panel"><div className="section-heading"><div><span className="eyebrow">栏舍任务</span><h2>今日盘点</h2></div><button className="text-button" onClick={() => refresh()} disabled={loading}>刷新</button></div><div className="pen-grid">{tasks.map((task) => <article className={`pen-plate ${task.status === "confirmed" ? "confirmed" : task.status === "review_required" ? "review" : "uploading"}`} key={task.penId}><div className="pen-rail" /><div className="pen-head"><span>{task.buildingCode} {task.buildingName}</span><strong>{task.penCode}栏</strong></div><div className="pen-body"><span className="state-label">{inventoryStatusLabel(task.status)}</span><div className="count"><strong>{task.confirmedCount ?? "—"}</strong><span>头</span></div><p>{task.penName}</p></div>{task.sessionId && <button onClick={() => openSession(task.sessionId!)}>查看会话证据 <span>→</span></button>}</article>)}{!loading && tasks.length === 0 && <p>今日暂无可见栏舍任务。</p>}</div></section>
    <section id="media-review" className="panel"><div className="section-heading"><div><span className="eyebrow">会话媒体审核</span><h2>{selected ? `${selected.businessDate} · ${inventoryStatusLabel(selected.status)} · v${selected.version}` : "选择一个盘点会话"}</h2></div>{selected?.status === "review_required" && canConfirm ? <button className="primary-inline" onClick={confirmSelected} disabled={loading}>人工确认并锁定证据</button> : selected?.status === "confirmed" && canCorrect ? <button className="primary-inline" onClick={correctSelected} disabled={loading}>创建审计更正版本</button> : null}</div>{selected ? <>
      {reviewMode && <div className="review-workspace">{evidenceGrid}<ReviewCommandForm key={`${currentUser?.activeOrganizationId}/${selected.id}/${reviewMode}`} session={selected} mode={reviewMode} api={authorizedApi} onCancel={() => setReviewMode(null)} onReadback={async (result) => { const identity = authenticatedClient.sessionRevision; setReviewMode(null); await refresh(); if (identity === authenticatedClient.sessionRevision) await openSession(result.id); }} /></div>}
      {canCorrect && <InventoryVersionPanel key={`${currentUser?.activeOrganizationId}/${selected.id}`} sessionId={selected.id} api={authorizedApi} openSession={openSession} />}
      <p className="candidate-count">{selected.status === "confirmed" ? "人工确认数量" : selected.status === "superseded" ? "历史人工确认数量" : "AI 待复核候选"}：<strong>{(["confirmed", "superseded"].includes(selected.status) ? selected.count : selected.rawModelCount) ?? "—"}</strong> 头</p><p className="muted-copy">候选结果不会进入日报或综合报表；只有人工确认后才成为业务数量。更正会创建新版本并继续引用证据会话 {selected.evidenceSessionId.slice(0, 8)}，不会覆盖历史。</p>{selected.inferenceStatus === "failed" && <div className="inference-failure" role="status"><strong>自动计数失败，已安全转人工复核</strong><span>{selected.failureCode ?? "PROVIDER_ERROR"}</span><p>{selected.failureMessage ?? "推理服务未返回可用结果。"}</p></div>}{selected.model && <dl className="model-evidence"><div><dt>模型</dt><dd>{selected.model.modelKey} / {selected.model.version}</dd></div><div><dt>权重校验</dt><dd title={selected.model.checksum}>{selected.model.checksum}</dd></div><div><dt>适配器 / 来源</dt><dd>{selected.model.adapterVersion} / {inferenceSourceLabel(selected.inferenceSource)}</dd></div><div><dt>推理耗时</dt><dd>{selected.latencyMs === null ? "未记录" : `${selected.latencyMs} ms`}</dd></div></dl>}{selected.warnings.length > 0 && <ul className="inference-warnings">{selected.warnings.map((warning) => <li key={warning}>{warning}</li>)}</ul>}{!reviewMode && evidenceGrid}{evidence.length === 0 && <p>该会话没有可见的媒体证据。</p>}</> : <p>从任务卡片打开会话后，才会按当前组织权限加载原始证据；对象存储 URL 不会暴露给浏览器。</p>}</section>
    <section id="inference-failures" className="panel"><div className="section-heading"><div><span className="eyebrow">系统管理员 · 不可变尝试链</span><h2>失败推理任务</h2></div><strong>{panelCount(failedJobPanel) ?? "—"}</strong></div><div className="failed-job-list">{failedJobs.map((job) => <article key={job.jobId}><div><strong>{job.failureCode ?? "PROVIDER_ERROR"}</strong><span>第 {job.retrySequence + 1} 次尝试 · {new Date(job.createdAt).toLocaleString()}</span></div><p>{job.failureMessage ?? "推理服务未返回可用结果。"}</p><dl><div><dt>任务</dt><dd title={job.jobId}>{job.jobId.slice(0, 8)}</dd></div><div><dt>模型</dt><dd>{job.requestedModel.modelKey} / {job.requestedModel.version}</dd></div><div><dt>校验</dt><dd title={job.requestedModel.checksum}>{job.requestedModel.checksum.slice(0, 12)}…</dd></div></dl><button className="primary-inline" disabled={loading || !job.retryable} onClick={() => retryInference(job)}>{job.retryable ? "保留证据并重试" : job.retryBlockedReason === "ALREADY_RETRIED" ? "已创建后继任务" : "当前不可重试"}</button></article>)}<PanelFeedback state={failedJobPanel} emptyMessage="当前组织暂无失败推理任务。" loading={loading} retry={() => refresh()} /></div></section>
    <div className="content-grid"><section id="duplicate-review" className="panel"><div className="section-heading"><div><span className="eyebrow">证据复核</span><h2>近重复告警</h2></div></div><ol className="queue-list">{duplicates.map((item) => <li key={item.id}><span className="queue-icon review">!</span><div><strong>汉明距离 {item.hammingDistance}</strong><p>媒体 {item.sourceMediaId.slice(0, 8)} 与 {item.candidateMediaId.slice(0, 8)}；仅提示，原图未删除。</p></div><button className="text-button" onClick={() => resolveDuplicate(item)} disabled={loading}>解决并审计</button></li>)}</ol><PanelFeedback state={duplicatePanel} emptyMessage="暂无待处理告警；无告警不代表已审核。" loading={loading} retry={() => refresh()} /></section>
      <section id="reports" className="panel"><div className="section-heading"><div><span className="eyebrow">已确认数据</span><h2>日报与综合</h2></div></div><p className="summary-number">日盘：{daily.length} 条已确认记录</p><p className="muted-copy">综合均值（首个可见栏舍、当日）：{aggregate?.rawMean ?? "—"}；展示数量：{aggregate?.roundedCount ?? "—"}</p><ul className="report-list">{daily.map((row) => <li key={row.sessionId}>{row.buildingCode} / {row.penCode}<strong>{row.confirmedCount} 头</strong></li>)}{daily.length === 0 && <li>无已确认记录；待复核结果绝不计入报表。</li>}</ul><div className="report-export-controls" aria-label="导出已确认盘点报表"><label>开始日期<input type="date" value={reportFrom} onChange={(event) => setReportFrom(event.target.value)} /></label><label>结束日期<input type="date" value={reportTo} onChange={(event) => setReportTo(event.target.value)} /></label><button className="primary-inline" disabled={loading} onClick={() => downloadReport("pdf")}>下载 PDF</button><button className="primary-inline" disabled={loading} onClick={() => downloadReport("xlsx")}>下载 Excel</button></div><p className="muted-copy">导出最多 366 天，仅包含已确认记录；候选、失败、模型和媒体内部信息不会写入文件。</p></section></div>
    <section id="audit" className="panel"><div className="section-heading"><div><span className="eyebrow">不可变记录</span><h2>审计日志</h2></div></div><div className="audit-list">{audit.map((event) => <article key={event.id}><strong>{event.action}</strong><span>{new Date(event.createdAt).toLocaleString()}</span><p>{event.targetType} · {event.targetId}{event.reason ? ` · ${event.reason}` : ""}</p></article>)}<PanelFeedback state={auditPanel} emptyMessage="当前组织暂无审计记录。" loading={loading} retry={() => refresh()} /></div></section>
    {currentUser ? <MasterDataPanel key={currentUser.activeOrganizationId} api={authorizedApi} organizationId={currentUser.activeOrganizationId} canManage={canCorrect} /> : null}
    {currentUser ? <MediaLibraryPanel key={`library-${currentUser.activeOrganizationId}`} api={authorizedApi} loadThumbnail={loadThumbnail} sessionRevision={sessionRevision} pens={tasks} openSession={openSession} /> : null}
    {currentUser ? <InventoryHistoryPanel key={`history-${currentUser.activeOrganizationId}`} api={authorizedApi} openSession={openSession} /> : null}
  </div>;
}
