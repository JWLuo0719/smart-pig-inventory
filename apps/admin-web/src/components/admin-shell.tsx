import type { ReactNode } from "react";
import Image from "next/image";

const navigation = [
  ["现场态势", "今日需处理", "#top"],
  ["盘点任务", "下发与进度", "#tasks"],
  ["媒体审核", "会话与近重复", "#media-review"],
  ["盘点报表", "日盘与综合", "#reports"],
  ["审计日志", "确认与覆盖", "#audit"],
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
          {navigation.map(([label, hint, href], index) => (
            <a className={index === 0 ? "nav-item active" : "nav-item"} href={href} key={label}>
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
            <span className="eyebrow">组织范围由登录令牌确定</span>
            <h1>现场态势</h1>
          </div>
          <div className="top-actions">
            <span className="network-pill warning">当前组织实时数据</span>
            <button type="button" className="quiet-button">受认证访问</button>
          </div>
        </header>
        {children}
      </main>
    </div>
  );
}
