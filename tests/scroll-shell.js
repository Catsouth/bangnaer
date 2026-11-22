/* 应用壳高度链桩测（v1.10.1）：壳 App 里页面滑不动 + 页眉顶进灵动岛的回归防线。
   jsdom 测不了真实布局，这里钉住的是结构与规则链（真机手感需人工验）：
   - viewport 带 viewport-fit=cover（全屏壳的前提）
   - html/body 高度走 100% 百分比链，body 不再靠 min-height:100dvh 撑高
   - body 是 flex 纵列 + overflow:hidden；main 是 flex:1 + min-height:0 + overflow-y:auto 的内层滚动容器
   - header 顶部内边距吃 env(safe-area-inset-top)，不再顶进灵动岛
   - switchView 切页滚的是 main，不是 window
   - jsdom 计算样式冒烟：main/body 的关键计算值真的生效（不是只写在源码里） */
const fs = require("fs");
const path = require("path");
let JSDOM;
try { ({ JSDOM } = require("jsdom")); } catch (e) {
  for (const p of ["/tmp/atlastest/node_modules/jsdom", "/tmp/atlas-test/node_modules/jsdom"]) {
    try { ({ JSDOM } = require(p)); break; } catch (_) {}
  }
  if (!JSDOM) { console.error("需要 jsdom：先 npm install jsdom（或把 jsdom 放进 NODE_PATH）"); process.exit(2); }
}
const html = fs.readFileSync(path.join(__dirname, "..", "src", "index.html"), "utf8");
let fails = 0;
function ok(name, cond, extra) { console.log((cond ? "PASS " : "FAIL ") + name + (extra ? " | " + extra : "")); if (!cond) fails++; }
const rule = sel => { const m = html.match(new RegExp("(?:^|\\n)" + sel + "\\{([^}]*)\\}")); return m ? m[1] : ""; };

/* ---------- 源码规则链 ---------- */
ok("viewport 带 viewport-fit=cover", /<meta name="viewport"[^>]*viewport-fit=cover/.test(html));
ok("html 高度 100%（百分比链起点）", /height:\s*100%/.test(rule("html")));
const bodyCss = rule("body");
ok("body 高度 100% + flex 纵列 + overflow:hidden",
  /height:\s*100%/.test(bodyCss) && /display:\s*flex/.test(bodyCss) && /flex-direction:\s*column/.test(bodyCss) && /overflow:\s*hidden/.test(bodyCss), bodyCss.slice(0, 80));
ok("body 不再靠 min-height:100vh/100dvh 撑高（壳内文档滚动失效的旧口径）",
  !/min-height:\s*100d?vh/.test(bodyCss));
const mainCss = rule("main");
ok("main 是内层滚动容器（flex:1 + min-height:0 + overflow-y:auto）",
  /flex:\s*1/.test(mainCss) && /min-height:\s*0/.test(mainCss) && /overflow-y:\s*auto/.test(mainCss), mainCss.slice(0, 80));
ok("header 顶部内边距吃 safe-area-inset-top（不顶灵动岛）",
  /padding:\s*calc\(10px \+ env\(safe-area-inset-top/.test(rule("header")));
const sv = (html.match(/function switchView\(v\)\{[^}]*\}/) || [""])[0];
ok("switchView 切页滚动 main 内层容器（不是 window）",
  sv.includes('querySelector("main")') && sv.includes("scrollTo"), sv.slice(0, 60));

/* ---------- jsdom 计算样式冒烟 ---------- */
{
  const dom = new JSDOM(html, {
    url: "http://localhost/", runScripts: "dangerously", pretendToBeVisual: true,
    beforeParse(window) {
      window.fetch = () => Promise.resolve({ ok: true, status: 200, text: () => Promise.resolve("{}") });
      window.URL.createObjectURL = () => "blob:stub";
    }
  });
  const win = dom.window, doc = win.document;
  const mcs = win.getComputedStyle(doc.querySelector("main"));
  ok("计算样式：main overflowY=auto 且 flexGrow=1、minHeight=0",
    mcs.overflowY === "auto" && mcs.flexGrow === "1" && mcs.minHeight === "0px",
    `overflowY=${mcs.overflowY} flexGrow=${mcs.flexGrow} minHeight=${mcs.minHeight}`);
  const bcs = win.getComputedStyle(doc.body);
  ok("计算样式：body display=flex、overflow=hidden、height=100%",
    bcs.display === "flex" && bcs.overflow === "hidden" && bcs.height === "100%",
    `display=${bcs.display} overflow=${bcs.overflow} height=${bcs.height}`);
  const hdr = doc.querySelector("header"), mn = doc.querySelector("main");
  ok("骨架顺序：header 与 main 是 body 的同级子元素（页眉在滚动容器外）",
    hdr && mn && hdr.parentElement === doc.body && mn.parentElement === doc.body && (hdr.compareDocumentPosition(mn) & 4) !== 0);
  dom.window.close();
}

console.log(fails ? `\n${fails} FAIL` : "\nALL_SCROLL_SHELL_TESTS_OK");
process.exit(fails ? 1 : 0);
