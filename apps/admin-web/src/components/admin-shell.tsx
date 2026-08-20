import type { ReactNode } from "react";
import Image from "next/image";

const navigation = [
  ["现场态势", "今日需处理"],
  ["盘点任务", "下发与进度"],
  ["媒体审核", "重复与质量"],
  ["组织栏舍", "主数据"],
  ["盘点报表", "日盘与综合"],
  ["模型与同步", "版本与 ERP"],
  ["审计日志", "更正与覆盖"],
] as const;

export function AdminShell({ children }: Readonly<{ children: ReactNode }>) {
  return (
    <div className="app-shell">
      <aside className="sidebar" aria-label="管理端主导航">
        <div className="brand">
          <Image
            className="brand-mark"
            src="/smart-pig-farm-owner-logo-v1.png"
            alt="智慧猪场场主初版标志"
            width={42}
            height={46}
            priority
          />
          <div>
            <strong>智慧猪场场主</strong>
            <span>现场作业台</span>
          </div>
        </div>
        <nav className="nav-list">
          {navigation.map(([label, hint], index) => (
            <a className={index === 0 ? "nav-item active" : "nav-item"} href="#" key={label}>
              <span>{label}</span>
              <small>{hint}</small>
            </a>
          ))}
        </nav>
        <div className="sidebar-foot">
          <span className="status-dot" aria-hidden="true" />
          <div><strong>开发环境</strong><small>推理未启用</small></div>
        </div>
      </aside>
      <main className="main-column">
        <header className="topbar">
          <div>
            <span className="eyebrow">F001 · 示范猪场</span>
            <h1>现场态势</h1>
          </div>
          <div className="top-actions">
            <span className="network-pill warning">3 个包待上传</span>
            <button type="button" className="quiet-button">管理员</button>
          </div>
        </header>
        {children}
      </main>
    </div>
  );
}
