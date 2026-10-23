"use client";
import { useEffect, useState } from "react";

type Version = { id: string; version: number; status: string; confirmedCount: number | null; supersedesSessionId: string | null; reason: string | null; confirmedAt: string | null };
type Page = { currentSessionId: string | null; evidenceSessionId: string; items: Version[]; nextBeforeVersion: number | null };
export function InventoryVersionPanel({ sessionId, api, openSession }: {
  sessionId: string; api: <T>(path: string) => Promise<T>; openSession: (id: string) => Promise<void>;
}) {
  const [page, setPage] = useState<Page | null>(null);
  const [error, setError] = useState(false);
  const [revision, setRevision] = useState(0);
  const [before, setBefore] = useState<number | null>(null);
  useEffect(() => {
    let active = true;
    api<Page>(`inventory-sessions/${sessionId}/versions?limit=20${before === null ? "" : `&beforeVersion=${before}`}`)
      .then((value) => { if (active) setPage(value); })
      .catch(() => { if (active) setError(true); });
    return () => { active = false; };
  }, [sessionId, api, before, revision]);
  return <section aria-label="更正版本链"><h3>不可变更正版本</h3>
    {error ? <p role="alert">版本记录暂不可读取。<button onClick={() => { setError(false); setPage(null); setRevision((n) => n + 1); }}>重试</button></p> : !page ? <p role="status">正在读取版本…</p> : <>
      <p>只显示本证据的更正链，原始证据保持不变。</p>
      {page.items.length === 0 && <p>尚无已确认版本。</p>}
      <ol>{page.items.map((item) => <li key={item.id}><button className="text-button" onClick={() => openSession(item.id)}>v{item.version} · {item.confirmedCount ?? "未知"} 头 · {item.status === "confirmed" ? "当前确认" : "历史版本"}</button><span>{item.confirmedAt ? new Date(item.confirmedAt).toLocaleString() : ""}</span><p>{item.reason ?? "首次人工确认"}</p></li>)}</ol>
      {page.nextBeforeVersion !== null && <button onClick={() => { setPage(null); setBefore(page.nextBeforeVersion); }}>更早版本</button>}
    </>}
  </section>;
}
