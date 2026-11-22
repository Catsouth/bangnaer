/* v1.8.0 精修回归：统计行 / 卡面计数与 favicon 叠 stack / 分页点 / 服务面板 /
   最近添加日期分组 / 身份色点一致性 / 全部 App 分类 / 加号菜单 / 详情 Sheet 结构 */
const fs = require("fs");
const path = require("path");
let JSDOM;
try { ({ JSDOM } = require("jsdom")); } catch (e) {
  for (const p of ["/tmp/atlastest/node_modules/jsdom", "/tmp/atlas-test/node_modules/jsdom"]) {
    try { ({ JSDOM } = require(p)); break; } catch (_) {}
  }
  if (!JSDOM) { console.error("需要 jsdom"); process.exit(2); }
}
const html = fs.readFileSync(path.join(__dirname, "..", "src", "index.html"), "utf8");
let fails = 0;
function ok(name, cond, extra) { console.log((cond ? "PASS " : "FAIL ") + name + (extra ? " | " + extra : "")); if (!cond) fails++; }
const sleep = ms => new Promise(r => setTimeout(r, ms));

function makeDom(seed = {}) {
  const dom = new JSDOM(html, {
    url: "http://localhost/", runScripts: "dangerously", pretendToBeVisual: true,
    beforeParse(window) {
      window.fetch = () => Promise.resolve({ ok: true, status: 200, text: () => Promise.resolve("{}") });
      window.URL.createObjectURL = () => "blob:stub";
      if (seed.ls) for (const k in seed.ls) window.localStorage.setItem(k, seed.ls[k]);
    }
  });
  const doc = dom.window.document;
  doc.querySelectorAll("dialog").forEach(d => { d.showModal = () => { d.dataset.opened = "1"; }; d.close = () => { d.dataset.opened = ""; }; });
  return { dom, win: dom.window, doc };
}
const DAY = 86400000, NOW = Date.now();
const DB = {
  identities: [
    { id: "e1", type: "email", value: "me@example.com", label: "主力邮箱", createdAt: NOW - 30 * DAY },
    { id: "p1", type: "phone", value: "13800138000", label: "", createdAt: NOW - 30 * DAY },
    { id: "g1", type: "google", value: "me@gmail.com", label: "谷歌号", createdAt: NOW - 30 * DAY }
  ],
  links: [
    { id: "l1", identityId: "e1", domain: "github.com", name: "GitHub", username: "me", method: "密码登录", status: "active", createdAt: NOW },
    { id: "l2", identityId: "e1", domain: "taobao.com", name: "淘宝", username: "", method: "密码登录", status: "active", createdAt: NOW },
    { id: "l3", identityId: "e1", domain: "jd.com", name: "京东", username: "", method: "密码登录", status: "active", createdAt: NOW },
    { id: "l4", identityId: "e1", domain: "pinduoduo.com", name: "拼多多", username: "", method: "密码登录", status: "active", createdAt: NOW },
    { id: "l5", identityId: "e1", domain: "meituan.com", name: "美团", username: "", method: "密码登录", status: "active", createdAt: NOW },
    { id: "l6", identityId: "e1", domain: "zhihu.com", name: "知乎", username: "", method: "密码登录", status: "active", createdAt: NOW },
    { id: "l7", identityId: "e1", domain: "openai.com", name: "ChatGPT", username: "", method: "Google 授权", status: "active", createdAt: NOW - 5 * DAY },
    { id: "l8", identityId: "p1", domain: "weixin.qq.com", name: "微信", username: "", method: "手机号验证码", status: "active", createdAt: NOW - DAY },
    { id: "l9", identityId: "p1", domain: "binance.com", name: "Binance", username: "", method: "密码登录", status: "active", createdAt: NOW },
    { id: "l10", identityId: "p1", domain: "alipay.com", name: "支付宝", username: "", method: "密码登录", status: "active", createdAt: NOW },
    { id: "l11", identityId: "g1", domain: "youtube.com", name: "YouTube", username: "", method: "Google 授权", status: "active", createdAt: NOW }
  ],
  updatedAt: 5
};

(async () => {
  const { win, doc } = makeDom({ ls: { "atlas-db": JSON.stringify(DB) } });
  await sleep(80);

  /* ---------- 1. 页眉统计行 ---------- */
  const ps = doc.getElementById("pageStats").textContent;
  ok("统计行分类型计数", ps.includes("1 个邮箱") && ps.includes("1 个手机号") && ps.includes("1 个登录账号"), ps);
  ok("统计行结尾关联总数（去重服务数）", ps.includes("关联着 11 个网站与 App"), ps);

  /* ---------- 2. 卡面：特大计数 + favicon 叠 stack + 分页点 ---------- */
  const card1 = doc.querySelector('.idcard[data-id="e1"]');
  ok("卡面特大计数=7", !!card1 && card1.querySelector(".bigcnt b").textContent === "7", card1 && card1.querySelector(".bigcnt b").textContent);
  const avs = card1.querySelectorAll(".avatarstack .av");
  ok("卡面 favicon stack 最多 4 个 + more", avs.length === 5, "avs=" + avs.length);
  ok("stack 超出收成 +3", card1.querySelector(".avatarstack .av.more").textContent === "+3", card1.querySelector(".avatarstack .av.more").textContent);
  ok("卡面底行左是类型小字", card1.querySelector(".typetag").textContent.includes("邮箱"));
  ok("分页点数量=卡数", doc.querySelectorAll("#cardDots i").length === 3, "dots=" + doc.querySelectorAll("#cardDots i").length);

  /* ---------- 3. 卡下服务面板 ---------- */
  ok("未选卡时面板标题=全部服务", doc.getElementById("svcTitle").textContent === "全部服务");
  ok("未选卡副标题带总数", doc.getElementById("svcSub").textContent.includes("全部 11 个网站与 App"), doc.getElementById("svcSub").textContent);
  win.eval("selId='e1'; render()");
  await sleep(30);
  ok("选卡后面板标题=身份备注名", doc.getElementById("svcTitle").textContent === "主力邮箱", doc.getElementById("svcTitle").textContent);
  ok("选卡副标题文案", doc.getElementById("svcSub").textContent.includes("用它注册或绑定的 7 个网站与 App"), doc.getElementById("svcSub").textContent);
  ok("面板是玻璃面板+大图标网格", !!doc.querySelector(".glasspanel .gridpanel"));
  ok("网格格子数=该身份服务数", doc.querySelectorAll(".gcell[data-edit]").length === 7, "cells=" + doc.querySelectorAll(".gcell[data-edit]").length);
  ok("网格最后一格是虚线添加格", !!doc.querySelector(".gcell.add#tileAdd"));
  ok("面板绿色添加胶囊在位", !!doc.getElementById("btnPanelAdd"));

  /* ---------- 4. 最近添加按日期分组 + 身份胶囊 ---------- */
  const gt = [...doc.querySelectorAll(".rgroup-t")].map(e => e.textContent);
  ok("最近添加有今天/昨天分组", gt.includes("今天") && gt.includes("昨天"), gt.join("/"));
  ok("最近添加有 M月d日 分组", gt.some(t => /^\d+月\d+日$/.test(t)), gt.join("/"));
  const rrow = doc.querySelector('.rcard.rrow[data-edit="l1"]');
  ok("最近行可点（data-edit 在位）", !!rrow);
  ok("最近行带身份胶囊（圆点+备注名）", !!rrow && !!rrow.querySelector(".idcap .cdot") && rrow.querySelector(".idcap").textContent.includes("主力邮箱"));
  ok("最近行右侧是分类小字", !!rrow && rrow.querySelector(".rcat").textContent === "开发", rrow && rrow.querySelector(".rcat").textContent);
  const recentDot = rrow.querySelector(".idcap .cdot").style.background;

  /* ---------- 5. 身份色点一致性：全部 App 行 vs 最近行 vs 关系图 chip ---------- */
  doc.querySelectorAll(".tabbtn")[1].click(); await sleep(40);
  const svcRow = [...doc.querySelectorAll(".svc")].find(r => r.textContent.includes("GitHub"));
  ok("全部App行带身份胶囊", !!svcRow && !!svcRow.querySelector(".idcap .cdot"));
  const appDot = svcRow.querySelector(".idcap .cdot").style.background;
  ok("同身份在全部App行与最近行同色", appDot === recentDot, appDot + " vs " + recentDot);
  doc.querySelectorAll(".tabbtn")[2].click(); await sleep(60);
  const chip = doc.querySelector('[data-gchip="e1"]');
  ok("关系图 chip 圆点与胶囊同色", !!chip && chip.querySelector(".dot").style.background === recentDot, chip && chip.querySelector(".dot").style.background);

  /* ---------- 6. 全部 App 分类化 ---------- */
  doc.querySelectorAll(".tabbtn")[1].click(); await sleep(40);
  const pillCats = [...doc.querySelectorAll("#appCats [data-cat]")].map(b => b.dataset.cat);
  ok("分类胶囊含新分类（开发/购物/支付金融/加密金融/AI）", ["开发", "购物", "支付金融", "加密金融", "AI"].every(c => pillCats.includes(c)), pillCats.join("/"));
  const heads = [...doc.querySelectorAll(".cathead")].map(e => e.textContent);
  ok("列表按分类分组带小节标题", heads.some(t => t.includes("开发")) && heads.some(t => t.includes("购物")), heads.join("/"));
  doc.querySelector('[data-cat="购物"]').click(); await sleep(40);
  ok("点购物胶囊只剩购物类 4 条", doc.querySelectorAll("#appList .svc").length === 4, "rows=" + doc.querySelectorAll("#appList .svc").length);
  doc.querySelector('[data-cat="all"]').click(); await sleep(40);

  /* ---------- 7. 加号菜单五项 ---------- */
  doc.querySelectorAll(".tabbtn")[0].click(); await sleep(40);
  const menuIds = ["addMenuSvc", "addMenuEmail", "addMenuPhone", "addMenuAcct", "addMenuImport"];
  ok("加号菜单五项都在", menuIds.every(id => !!doc.getElementById(id)));
  doc.getElementById("btnAddId").click(); await sleep(20);
  ok("点＋添加弹出菜单", doc.getElementById("addMenu").classList.contains("open"));
  doc.getElementById("addMenuEmail").click(); await sleep(20);
  ok("菜单「添加邮箱」打开身份弹窗且预设邮箱", doc.getElementById("dlgId").dataset.opened === "1" && doc.getElementById("idType").value === "email");
  doc.getElementById("dlgId").close();
  doc.getElementById("btnAddId").click(); await sleep(20);
  doc.getElementById("addMenuPhone").click(); await sleep(20);
  ok("菜单「添加手机号」预设手机号", doc.getElementById("idType").value === "phone");
  doc.getElementById("dlgId").close();
  doc.getElementById("btnAddId").click(); await sleep(20);
  doc.getElementById("addMenuImport").click(); await sleep(20);
  ok("菜单「自动录入」打开原导入弹窗", doc.getElementById("dlgImport").dataset.opened === "1");
  doc.getElementById("dlgImport").close();

  /* ---------- 8. 服务详情 Sheet 结构 ---------- */
  win.eval("openSvcEdit('l1')");
  await sleep(30);
  ok("服务详情标题=服务名", doc.getElementById("svcEditTitle").textContent === "GitHub");
  const caps = doc.getElementById("svcEditCaps").textContent;
  ok("服务详情头有分类胶囊+域名胶囊", caps.includes("开发") && caps.includes("github.com"), caps);
  ok("服务详情有身份行+同色胶囊", !!doc.querySelector("#svcEditIdRow .idcap .cdot") && doc.querySelector("#svcEditIdRow .idcap .cdot").style.background === recentDot);
  ok("服务详情底部元信息带添加于", doc.getElementById("svcEditMeta").textContent.includes("添加于"), doc.getElementById("svcEditMeta").textContent);
  ok("服务详情有虚线添加行", !!doc.getElementById("btnSvcAddAnother"));
  ok("服务详情动作排三钮在位", ["btnSvcEditGoto", "btnSvcEditCopy", "btnSvcEditDel"].every(id => !!doc.getElementById(id)));
  doc.getElementById("dlgSvcEdit").close();

  /* ---------- 9. 身份详情 Sheet 结构 ---------- */
  win.eval("openIdDetail('g1')");
  await sleep(30);
  ok("身份详情有小卡头", !!doc.querySelector("#idDetailHead .idmini"));
  ok("身份详情标题含身份值", doc.getElementById("idDetailTitle").textContent.includes("me@gmail.com"), doc.getElementById("idDetailTitle").textContent);
  ok("身份详情服务分组有 YouTube 行", doc.getElementById("idDetailSvcs").textContent.includes("YouTube"));
  const authSec = doc.getElementById("idDetailAuthSec");
  ok("Google 身份有「绑定的登录账户」分组（ChatGPT 用 Google 授权）", authSec.style.display !== "none" && doc.getElementById("idDetailAuth").textContent.includes("ChatGPT"), doc.getElementById("idDetailAuth").textContent);
  ok("登录账户行带身份胶囊", !!doc.querySelector("#idDetailAuth .idcap .cdot"));
  ok("身份详情底部元信息带添加于", doc.getElementById("idDetailMeta").textContent.includes("添加于"), doc.getElementById("idDetailMeta").textContent);
  ok("身份详情有虚线添加行+复制钮", !!doc.getElementById("btnIdAddSvc") && !!doc.getElementById("btnIdCopy"));
  doc.getElementById("dlgIdDetail").close();

  win.close();
  console.log(fails ? ("V180_FAIL fails=" + fails) : "V180_OK");
  process.exit(fails ? 1 : 0);
})().catch(e => { console.error("V180_ERROR", e); process.exit(1); });
