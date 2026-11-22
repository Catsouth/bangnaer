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
const sleep = ms => new Promise(r => setTimeout(r, ms));

function makeDom(seed) {
  const fetchCalls = [];
  const dom = new JSDOM(html, {
    url: "http://localhost/", runScripts: "dangerously", pretendToBeVisual: true,
    beforeParse(window) {
      window.fetch = (url, opts = {}) => { fetchCalls.push({ url: String(url), method: opts.method || "GET" }); return Promise.resolve({ ok: true, status: 200, text: () => Promise.resolve(seed && seed.remote ? JSON.stringify(seed.remote) : "{}") }); };
      window.URL.createObjectURL = () => "blob:stub";
      if (seed && seed.ls) for (const k in seed.ls) window.localStorage.setItem(k, seed.ls[k]);
    }
  });
  return { dom, fetchCalls };
}
function stubOffsets(win) {
  win.document.querySelectorAll(".tabbtn").forEach((b, i) => {
    Object.defineProperty(b, "offsetLeft", { configurable: true, get: () => 7 + i * 70 });
    Object.defineProperty(b, "offsetWidth", { configurable: true, get: () => 66 });
  });
}

(async () => {
  /* ---------- A. 透镜 + 设置页（空 DB） ---------- */
  {
    const { dom } = makeDom();
    const win = dom.window, doc = win.document;
    await sleep(60);
    stubOffsets(win);
    win.dispatchEvent(new win.Event("resize")); // 触发 placeLens(false) 用实测值对齐
    await sleep(30);
    const lens = doc.getElementById("tabLens");
    ok("透镜初始对齐第1个标签", lens.style.transform.includes("translateX(7px)") && lens.style.width === "66px", lens.style.transform + " w=" + lens.style.width);
    ok("页眉只剩标题+同步胶囊（无图标按钮）", !doc.querySelector("header .iconbtn") && !!doc.getElementById("syncStatus"));
    ok("底栏 4 个标签", doc.querySelectorAll(".tabbtn").length === 4);
    ok("搜索圆按钮在底栏内", !!doc.getElementById("btnTabSearch"));
    // 点击第 4 个标签（设置）
    doc.querySelectorAll(".tabbtn")[3].click();
    await sleep(30);
    ok("切到设置页显示", doc.getElementById("pageSettings").style.display !== "none");
    ok("透镜滑向第4个标签(带拉伸)", lens.style.transform.includes("translateX(217px)") && /scaleX\(1\.\d+\)/.test(lens.style.transform), lens.style.transform);
    await sleep(420);
    ok("透镜落位回弹 scaleX(1)", lens.style.transform.includes("translateX(217px)") && lens.style.transform.includes("scaleX(1)"), lens.style.transform);
    // resize 不报错且位置保持
    let rerr = null; try { win.dispatchEvent(new win.Event("resize")); await sleep(20); } catch (e) { rerr = e; }
    ok("resize 后透镜重算不报错", !rerr && lens.style.transform.includes("translateX(217px)"));
    // 设置页行：自动录入 → 原弹窗
    const dlgI = doc.getElementById("dlgImport"); let importOpened = false; dlgI.showModal = () => { importOpened = true; };
    doc.getElementById("btnImport").click();
    ok("设置页「自动录入」打开原 dlgImport", importOpened);
    // WebDAV 行 → 原弹窗
    const dlgD = doc.getElementById("dlgDav"); let davOpened = false; dlgD.showModal = () => { davOpened = true; };
    doc.getElementById("btnDav").click();
    ok("设置页「WebDAV 备份」打开原 dlgDav", davOpened);
    ok("WebDAV 副标题=未设置文案", doc.getElementById("setDavSub").textContent.includes("未设置"), doc.getElementById("setDavSub").textContent);
    // 隐私开关翻转
    const sw = doc.getElementById("btnPrivacy");
    const before = sw.classList.contains("on"); sw.click(); await sleep(20);
    ok("隐私开关点击翻转", sw.classList.contains("on") === !before);
    sw.click(); await sleep(20);
    ok("隐私开关再点翻回", sw.classList.contains("on") === before);
    // 分享行可点击不报错
    let serr = null; try { doc.getElementById("btnShare").click(); await sleep(30); } catch (e) { serr = e; }
    ok("设置页「分享给朋友」点击不报错", !serr, serr && serr.message);
    // 导出行
    let eerr = null; try { doc.getElementById("btnExport").click(); await sleep(20); } catch (e) { eerr = e; }
    ok("设置页「导出 JSON」点击不报错", !eerr, eerr && eerr.message);
    // 搜索圆按钮 → 切全部 App 页
    doc.getElementById("btnTabSearch").click(); await sleep(30);
    ok("搜索圆按钮切到全部 App 页", doc.getElementById("pageApps").style.display !== "none");
    ok("透镜跟随到第2个标签", lens.style.transform.includes("translateX(77px)"), lens.style.transform);
    dom.window.close();
  }

  /* ---------- B. 旧 DB 兼容渲染 + 体检 ---------- */
  {
    const old = { identities: [{ id: "a1", type: "email", value: "me@example.com", label: "主力" }, { id: "a2", type: "phone", value: "13800138000", label: "" }], links: [{ id: "l1", identityId: "a1", domain: "github.com", name: "GitHub", username: "me" }, { id: "l2", identityId: "a2", domain: "cmbchina.com", name: "招商银行", username: "13800138000" }], updatedAt: 1000 };
    const { dom } = makeDom({ ls: { "atlas-db": JSON.stringify(old) } });
    const doc = dom.window.document;
    await sleep(60);
    ok("旧 DB 卡包渲染出 2 张卡", doc.querySelectorAll(".idcard").length === 2, "cards=" + doc.querySelectorAll(".idcard").length);
    doc.querySelectorAll(".tabbtn")[1].click(); await sleep(30);
    ok("旧 DB 全部 App 页有体检面板", (doc.getElementById("healthBox").textContent || "").length > 0);
    doc.querySelectorAll(".tabbtn")[2].click(); await sleep(60);
    ok("旧 DB 关系图渲染不报错", !!doc.getElementById("graphBox"));
    dom.window.close();
  }

  /* ---------- C. 示例模式零 PUT + 哈希跳过 ---------- */
  {
    const dav = JSON.stringify({ url: "https://dav.example.com/dav/atlas.json", user: "u", pass: "p" });
    const { dom, fetchCalls } = makeDom({ ls: { "atlas-dav": dav } });
    const win = dom.window, doc = win.document;
    await sleep(60);
    const demoBtn = doc.querySelector("#btnDemoStart");
    ok("空状态有示例入口", !!demoBtn);
    if (demoBtn) {
      demoBtn.click(); await sleep(40);
      const db = JSON.parse(win.localStorage.getItem("atlas-db"));
      ok("示例载入 4 身份", db.identities.length === 4, "n=" + db.identities.length);
      // 示例里乱改：直接走 save() 路径 + 等防抖
      win.eval("save()");
      await sleep(2400);
      const puts1 = fetchCalls.filter(c => c.method === "PUT").length;
      ok("示例模式 PUT=0", puts1 === 0, "PUT=" + puts1);
      // 清除示例不 PUT
      win.eval("clearDemoData()");
      await sleep(2400);
      const puts2 = fetchCalls.filter(c => c.method === "PUT").length;
      const db2 = JSON.parse(win.localStorage.getItem("atlas-db"));
      ok("清除示例后为空且不 PUT", db2.identities.length === 0 && !db2.demo && puts2 === 0, "PUT=" + puts2);
    }
    dom.window.close();
  }
  {
    const dav = JSON.stringify({ url: "https://dav.example.com/dav/atlas.json", user: "u", pass: "p" });
    const real = { identities: [{ id: "a1", type: "email", value: "me@example.com", label: "" }], links: [], updatedAt: 5000 };
    const { dom, fetchCalls } = makeDom({ ls: { "atlas-dav": dav, "atlas-db": JSON.stringify(real) } });
    const win = dom.window;
    await sleep(60);
    await win.eval("push()");
    const p1 = fetchCalls.filter(c => c.method === "PUT").length;
    await win.eval("push()");
    const p2 = fetchCalls.filter(c => c.method === "PUT").length;
    ok("哈希比对：同内容第二次 push 跳过", p1 === 1 && p2 === 1, "PUT " + p1 + "->" + p2);
    dom.window.close();
  }

  /* ---------- D. 换绑勾选 + 删身份连带删 ---------- */
  {
    const data = { identities: [{ id: "a1", type: "phone", value: "13800138000", label: "主力号" }, { id: "a2", type: "email", value: "x@y.com", label: "" }], links: [{ id: "l1", identityId: "a1", domain: "jd.com", name: "京东", username: "13800138000", method: "手机号验证码", status: "active", createdAt: Date.now() - 86400000 }, { id: "l2", identityId: "a2", domain: "github.com", name: "GitHub", username: "x", method: "密码登录", status: "active", createdAt: Date.now() }], updatedAt: 9000 };
    const { dom } = makeDom({ ls: { "atlas-db": JSON.stringify(data) } });
    const win = dom.window;
    await sleep(60);
    win.eval("DB.links.find(l=>l.id==='l1').rebindDone=true;save()");
    const saved = JSON.parse(win.localStorage.getItem("atlas-db"));
    ok("rebindDone 持久化", saved.links.find(l => l.id === "l1").rebindDone === true);
    win.eval("DB.identities=DB.identities.filter(i=>i.id!=='a1');DB.links=DB.links.filter(l=>l.identityId!=='a1');save()");
    const saved2 = JSON.parse(win.localStorage.getItem("atlas-db"));
    ok("删身份连带删 links（数据层）", saved2.links.length === 1 && saved2.links[0].id === "l2");
    dom.window.close();
  }

  console.log(fails === 0 ? "ALL_TESTS_OK" : ("FAILURES=" + fails));
  process.exit(fails ? 1 : 0);
})().catch(e => { console.error("HARNESS_ERROR", e); process.exit(2); });
