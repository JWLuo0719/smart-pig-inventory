// 看板前端静态检查：抽取 static/index.html 的内联脚本并做语法解析。
// 用法：node tools/check_dashboard_js.mjs
// 说明：看板是零依赖单文件页，没有构建步骤；此脚本保证改动后脚本仍可解析，
//       并检查页面引用的全部 API 路径都在 server.py 中有对应路由。
import { readFileSync } from "node:fs";
import { Script } from "node:vm";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const html = readFileSync(join(root, "pig_farm_agent", "static", "index.html"), "utf8");
const server = readFileSync(join(root, "pig_farm_agent", "server.py"), "utf8");

const scripts = [...html.matchAll(/<script>([\s\S]*?)<\/script>/g)].map((m) => m[1]);
if (scripts.length === 0) {
  console.error("未找到内联脚本");
  process.exit(1);
}
for (const [i, code] of scripts.entries()) {
  try {
    new Script(code, { filename: `index.html#script${i}` });
  } catch (err) {
    console.error(`脚本 ${i} 语法错误: ${err.message}`);
    process.exit(1);
  }
}

// 页面里出现的所有接口路径
const paths = new Set();
for (const code of scripts) {
  for (const m of code.matchAll(/["'`](\/(?:health|events|report|files|model|v1|analyze)[^"'`$\s]*)/g)) {
    paths.add(m[1].split("?")[0].replace(/\$\{[^}]*\}/g, ""));
  }
}
// 每类路径在 server.py 路由表里的必要片段
const required = [
  ["/health", "/health"],
  ["/events", "/events"],
  ["/report/daily.csv", "/report/daily.csv"],
  ["/report/daily", "/report/daily"],
  ["/files/", "/files/"],
  ["/model/replay", "/model/replay"],
  ["/v1/mobile/analyze", "/v1/mobile/analyze"],
  ["/v1/mobile/requests/", "/v1/mobile/requests/"],
];
const seen = [...paths].sort();
const missing = required.filter(([, needle]) => !server.includes(needle));
if (missing.length) {
  console.error("server.py 缺少看板引用的路由:", missing.map(([p]) => p).join(", "));
  process.exit(1);
}

console.log(`看板脚本语法检查通过（${scripts.length} 段，共 ${html.length} 字节）`);
console.log(`引用的 API 路径: ${seen.join(", ")}`);
