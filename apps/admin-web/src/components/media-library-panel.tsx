"use client";

import Image from "next/image";
import { useEffect, useRef, useState, type FormEvent } from "react";
import { directionLabel } from "@/lib/presentation-labels";
import { ThumbnailQueue } from "@/lib/thumbnail-queue";

type Media = { assetId: string; sessionId: string; buildingCode: string; penCode: string; businessDate: string; viewPosition: string; contentType: string; locked: boolean; deleted: boolean };
type PenOption = { penId: string; buildingCode: string; penCode: string };
type Query = { businessDate: string; penId: string; offset: number };

function Thumbnail({ item, queue }: { item: Media; queue: ThumbnailQueue }) {
  const [url, setUrl] = useState<string | null>(null);
  const [failed, setFailed] = useState(false);
  const supported = !item.deleted && ["image/jpeg", "image/png"].includes(item.contentType);
  useEffect(() => {
    if (!supported) return;
    let active = true;
    let current: string | null = null;
    const cancellation = new AbortController();
    queue.enqueue(item.assetId, cancellation.signal).then((blob) => {
      if (!active) return;
      current = URL.createObjectURL(blob); setUrl(current);
    }).catch(() => { if (active) setFailed(true); });
    return () => { active = false; cancellation.abort(); if (current) URL.revokeObjectURL(current); };
  }, [item.assetId, supported, queue]);
  const label = item.deleted ? "已删除，保留审计" : item.contentType === "video/mp4" ? "视频证据" : !supported ? "此格式暂无缩略图" : failed ? "缩略图暂不可用" : "缩略图加载中…";
  return <div className="library-thumbnail">{url && !failed ? <Image src={url} width={160} height={120} unoptimized alt={`${item.buildingCode} / ${item.penCode} ${directionLabel(item.viewPosition)}缩略图`} onError={() => setFailed(true)} /> : <span role="status">{label}</span>}</div>;
}

export function MediaLibraryPanel({ api, loadThumbnail, sessionRevision, pens, openSession }: {
  api: <T>(path: string) => Promise<T>; loadThumbnail: (assetId: string, signal: AbortSignal) => Promise<Blob>;
  sessionRevision: () => number;
  pens: PenOption[]; openSession: (id: string) => Promise<void>;
}) {
  const [date, setDate] = useState(() => new Date().toLocaleDateString("en-CA"));
  const [penId, setPenId] = useState("");
  const [query, setQuery] = useState<Query | null>(null);
  const [page, setPage] = useState<{ rows: Media[]; queue: ThumbnailQueue } | null>(null);
  const rows = page?.rows ?? null;
  const [error, setError] = useState(false);
  const [loading, setLoading] = useState(false);
  const cancelQuery = useRef<() => void>(() => undefined);
  useEffect(() => {
    if (!query) return;
    let active = true;
    const identity = sessionRevision();
    const isCurrent = () => active && identity === sessionRevision();
    const queue = new ThumbnailQueue(loadThumbnail, isCurrent);
    const cancel = () => { active = false; queue.dispose(); };
    cancelQuery.current = cancel;
    const params = new URLSearchParams({ businessDate: query.businessDate, limit: "50", offset: query.offset.toString() });
    if (query.penId) params.set("penId", query.penId);
    api<Media[]>(`media-assets?${params}`).then((items) => {
      if (!Array.isArray(items)) throw new Error("Invalid media list");
      if (isCurrent()) setPage({ rows: items, queue });
    }).catch(() => { if (isCurrent()) setError(true); }).finally(() => { if (isCurrent()) setLoading(false); });
    return cancel;
  }, [query, api, loadThumbnail, sessionRevision]);
  function begin(next: Query) { cancelQuery.current(); setPage(null); setError(false); setLoading(true); setQuery(next); }
  function submit(event: FormEvent) { event.preventDefault(); if (!loading) begin({ businessDate: date, penId, offset: 0 }); }
  return <section id="media-library" className="panel" aria-labelledby="media-library-title">
    <h2 id="media-library-title">按栏日期媒体库</h2>
    <p>缩略图用于查找证据；核验数量与检测位置请打开原图。视频及不支持的图片格式显示占位。</p>
    <form className="report-export-controls" onSubmit={submit}>
      <label>媒体业务日期<input type="date" required value={date} disabled={loading} onChange={(event) => setDate(event.target.value)} /></label>
      <label>媒体栏舍<select value={penId} disabled={loading} onChange={(event) => setPenId(event.target.value)}><option value="">全部栏舍</option>{pens.map((pen) => <option key={pen.penId} value={pen.penId}>{pen.buildingCode} / {pen.penCode}</option>)}</select></label>
      <button className="primary-inline" disabled={loading} type="submit">{loading ? "正在查询…" : "查询媒体库"}</button>
    </form>
    {loading && <p role="status">正在读取媒体列表…</p>}
    {error && <p role="alert">媒体库暂不可读取，请重新查询。</p>}
    {rows && page && <><p>查询范围：{query?.businessDate}；本页 {rows.length} 份证据。</p><ul className="library-grid">{rows.map((item) => <li key={item.assetId}>
      <Thumbnail key={`${item.assetId}/${item.deleted}`} item={item} queue={page.queue} />
      <strong>{item.buildingCode} / {item.penCode} · {directionLabel(item.viewPosition)}</strong>
      <span>{item.deleted ? "已删除" : item.locked ? "证据已锁定" : "尚未锁定"}</span>
      <button className="text-button" onClick={() => void openSession(item.sessionId)}>{item.deleted ? "查看历史证据记录" : "打开原图与会话证据"}</button>
    </li>)}</ul>{rows.length === 0 && <p>该查询范围暂无媒体证据。</p>}
      {query && <div className="library-pagination"><button disabled={loading || query.offset === 0} onClick={() => begin({ ...query, offset: Math.max(0, query.offset - 50) })}>上一页</button><button disabled={loading || rows.length < 50 || query.offset >= 10000} onClick={() => begin({ ...query, offset: query.offset + 50 })}>下一页</button></div>}
    </>}
  </section>;
}
