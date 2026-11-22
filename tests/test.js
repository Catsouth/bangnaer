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
      window.HTMLElement.prototype.scrollTo = () => {}; /* jsdom 缺 Element.scrollTo，桩掉防 async handler 里抛错变未处理 rejection */
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
    ok("WebDAV 状态=未开启文案", doc.getElementById("setDavSub").textContent.includes("未开启"), doc.getElementById("setDavSub").textContent);
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
    // 搜索圆按钮 → 原地展开搜索层（v1.10.0：不跳页）
    doc.getElementById("btnTabSearch").click(); await sleep(30);
    ok("搜索圆按钮原地展开搜索层", doc.getElementById("searchOverlay").classList.contains("open"));
    ok("搜索不跳页（仍停在设置页）", doc.getElementById("pageSettings").style.display !== "none" && doc.getElementById("pageApps").style.display === "none");
    doc.getElementById("soCancel").click(); await sleep(10);
    ok("点取消关层且不跳页", !doc.getElementById("searchOverlay").classList.contains("open") && doc.getElementById("pageSettings").style.display !== "none");
    // 设置页「下载新版本」行：指向 GitHub Releases
    const rel = doc.getElementById("btnRelease");
    ok("设置页有下载新版本行指向 Releases", !!rel && (rel.getAttribute("href") || "").includes("github.com/Catsouth/bangnaer/releases"));
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
    /* 原地搜索：不跳页、拼音/子串出结果、点结果开服务详情并关层 */
    let svcOpened = false; doc.getElementById("dlgSvcEdit").showModal = () => { svcOpened = true; };
    doc.getElementById("btnTabSearch").click(); await sleep(30);
    ok("在关系图页点搜索只开层不跳页", doc.getElementById("searchOverlay").classList.contains("open") && doc.getElementById("pageGraph").style.display !== "none");
    const soIn = doc.getElementById("soInput");
    soIn.value = "git"; soIn.dispatchEvent(new dom.window.Event("input", { bubbles: true })); await sleep(20);
    const row = doc.querySelector("#soResults .svc");
    ok("搜 git 出 GitHub 结果行", !!row && row.textContent.includes("GitHub"), row && row.textContent.slice(0, 40));
    if (row) { row.click(); await sleep(20); }
    ok("点结果打开服务详情 Sheet 且搜索层关闭", svcOpened && !doc.getElementById("searchOverlay").classList.contains("open"));
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

  /* ---------- E. 清空全部数据：只清本机、不 PUT 云端 ---------- */
  {
    const dav = JSON.stringify({ url: "https://dav.example.com/dav/atlas.json", user: "u", pass: "p" });
    const data = { identities: [{ id: "a1", type: "email", value: "me@example.com", label: "" }], links: [{ id: "l1", identityId: "a1", domain: "github.com", name: "GitHub", username: "me" }], trash: [], updatedAt: 9000 };
    const { dom, fetchCalls } = makeDom({ ls: { "atlas-dav": dav, "atlas-db": JSON.stringify(data) } });
    const win = dom.window, doc = win.document;
    win.confirm = () => true;
    win.appConfirm = async () => true;
    await sleep(60);
    doc.querySelectorAll(".tabbtn")[3].click(); await sleep(20);
    doc.getElementById("btnWipe").click(); await sleep(30);
    const saved = JSON.parse(win.localStorage.getItem("atlas-db"));
    ok("清空后本机 identities/links 归零", saved.identities.length === 0 && saved.links.length === 0);
    await sleep(2400); // 等任何防抖上传窗口过去
    const puts = fetchCalls.filter(c => c.method === "PUT").length;
    ok("清空全部数据不 PUT（云端备份未动）", puts === 0, "PUT=" + puts);
    dom.window.close();
  }

  /* ---------- F. v1.10.3 服务行左滑 + ··· 菜单 + 长按菜单 + 拖拽残影 ---------- */
  {
    const data = { identities: [{ id: "a1", type: "email", value: "me@example.com", label: "" }], links: [{ id: "l1", identityId: "a1", domain: "github.com", name: "GitHub", username: "u1", method: "密码登录", status: "active", createdAt: Date.now() }], updatedAt: 9000 };
    const { dom } = makeDom({ ls: { "atlas-db": JSON.stringify(data) } });
    const win = dom.window, doc = win.document;
    await sleep(60);
    const pev = (type, id, x, y) => { const e = new win.MouseEvent(type, { bubbles: true, cancelable: true }); Object.defineProperties(e, { pointerId: { value: id }, clientX: { value: x }, clientY: { value: y } }); return e; };
    let svcOpened = false; doc.getElementById("dlgSvcEdit").showModal = () => { svcOpened = true; };
    const copied = []; win.copyText = async (t, w) => { copied.push([t, w]); };
    doc.querySelectorAll(".tabbtn")[1].click(); await sleep(40); /* 全部 App 页 */
    const wrap = doc.querySelector("#appList .svcwrap");
    ok("F 行已套左滑外壳 .svcwrap", !!wrap);
    const row = wrap && wrap.querySelector(".svc");
    ok("F 行内旧胶囊按钮排已撤（无 goto/copyacc/copyid/edit 按钮）", !!row && !row.querySelector("[data-goto],[data-copyacc],[data-copyid],[data-edit]"));
    ok("F 金色「密码登录」胶囊保留常显", !!row && !!row.querySelector(".tag.method") && row.querySelector(".tag.method").textContent === "密码登录");
    ok("F 露出层含 ··· 与删除两圆钮", !!wrap && !!wrap.querySelector(".svcreveal [data-more]") && !!wrap.querySelector(".svcreveal [data-del]"));
    const ico = row && row.querySelector(".svc-ico img");
    ok("F 服务图标 img draggable=false（无原生拖拽残影）", !!ico && ico.getAttribute("draggable") === "false");
    if (ico) { const de = new win.Event("dragstart", { bubbles: true, cancelable: true }); ico.dispatchEvent(de); ok("F dragstart 被全局拦截 preventDefault", de.defaultPrevented === true); }
    /* 左滑：横向位移过阈值 → 露出 */
    row.dispatchEvent(pev("pointerdown", 1, 300, 100));
    row.dispatchEvent(pev("pointermove", 1, 230, 102));
    row.dispatchEvent(pev("pointermove", 1, 170, 103));
    row.dispatchEvent(pev("pointerup", 1, 170, 103));
    ok("F 左滑后行露出（open + translateX(-148px)）", wrap.classList.contains("open") && row.style.transform.includes("translateX(-148px)"), row.style.transform);
    /* 露出态点行身：收起且不触发整行动作 */
    row.click(); await sleep(20);
    ok("F 露出态点行身收起", !wrap.classList.contains("open"));
    /* ··· 菜单：四项、无删除 */
    wrap.querySelector("[data-more]").click(); await sleep(20);
    const menu = doc.getElementById("svcMenu");
    const items = [...menu.querySelectorAll("[data-mact]")].map(b => b.textContent);
    ok("F ··· 菜单四项齐全（前往登录/复制账号/复制身份/编辑）", menu.classList.contains("open") && items.length === 4 && items[0].includes("前往登录") && items[1] === "复制账号" && items[2] === "复制身份" && items[3] === "编辑", items.join("/"));
    menu.querySelector('[data-mact="copyacc"]').click(); await sleep(20);
    ok("F 菜单「复制账号」行为与旧按钮一致", copied.length === 1 && copied[0][0] === "u1" && copied[0][1] === "账号", JSON.stringify(copied));
    ok("F 菜单点后自动关闭", !menu.classList.contains("open"));
    /* 露出层删除：走既有删除（快照撤销） */
    wrap.querySelector("[data-del]").click(); await sleep(30);
    ok("F 删除圆钮删掉该服务且可撤销（undo 条出现）", win.eval("DB.links.length") === 0 && doc.getElementById("undoBar").classList.contains("show"));
    dom.window.close();
  }
  {
    /* 长按：网格图标压住 480ms → 菜单（带删除）；移动取消；触发后点按被吞 */
    const data = { identities: [{ id: "a1", type: "email", value: "me@example.com", label: "" }], links: [{ id: "l1", identityId: "a1", domain: "github.com", name: "GitHub", username: "u1", method: "密码登录", status: "active", createdAt: Date.now() }], updatedAt: 9000 };
    const { dom } = makeDom({ ls: { "atlas-db": JSON.stringify(data) } });
    const win = dom.window, doc = win.document;
    await sleep(60);
    const pev = (type, id, x, y) => { const e = new win.MouseEvent(type, { bubbles: true, cancelable: true }); Object.defineProperties(e, { pointerId: { value: id }, clientX: { value: x }, clientY: { value: y } }); return e; };
    let svcOpened = false; doc.getElementById("dlgSvcEdit").showModal = () => { svcOpened = true; };
    const cell = doc.querySelector(".gcell[data-edit]");
    ok("F 长按前置：卡包网格有服务格", !!cell);
    cell.dispatchEvent(pev("pointerdown", 1, 100, 100));
    await sleep(580); /* 越过 480ms 长按计时 */
    const menu = doc.getElementById("svcMenu");
    const items = [...menu.querySelectorAll("[data-mact]")].map(b => b.textContent);
    ok("F 长按 480ms 弹出菜单（五项含红色删除）", menu.classList.contains("open") && items.length === 5 && items[4] === "删除", items.join("/"));
    cell.dispatchEvent(pev("pointerup", 1, 100, 100));
    cell.click(); await sleep(20);
    ok("F 长按后松手点按被吞（不打开详情）", svcOpened === false);
    win.eval("closeSvcMenu()");
    /* 移动超阈值取消长按 */
    const cell2 = doc.querySelector(".gcell[data-edit]");
    cell2.dispatchEvent(pev("pointerdown", 2, 100, 100));
    cell2.dispatchEvent(pev("pointermove", 2, 130, 100));
    cell2.dispatchEvent(pev("pointerup", 2, 130, 100));
    await sleep(580);
    ok("F 长按被移动取消（菜单不弹）", !menu.classList.contains("open"));
    /* 普通轻点仍打开详情 */
    cell2.click(); await sleep(20);
    ok("F 普通轻点仍打开服务详情", svcOpened === true);
    dom.window.close();
  }

  /* ---------- G. v1.10.3 清除示例 UI 全链路（页内确认框，壳里原生 confirm 恒 false 的回归） ---------- */
  {
    const dav = JSON.stringify({ url: "https://dav.example.com/dav/atlas.json", user: "u", pass: "p" });
    const { dom, fetchCalls } = makeDom({ ls: { "atlas-dav": dav } });
    const win = dom.window, doc = win.document;
    await sleep(60);
    win.eval("loadDemo()");
    await sleep(30);
    ok("G 示例横幅出现", (doc.getElementById("demoBanner").textContent || "").includes("示例数据"));
    ok("G 顶栏胶囊为示例模式", (doc.getElementById("syncStatus").textContent || "").includes("示例模式"));
    const dc = doc.getElementById("dlgConfirm");
    dc.showModal = () => { dc.dataset.opened = "1"; }; dc.close = () => { dc.dataset.opened = ""; };
    doc.getElementById("btnClearDemo").click(); await sleep(20);
    ok("G 点清除先弹页内确认框（横幅未清）", dc.dataset.opened === "1" && (doc.getElementById("demoBanner").textContent || "").includes("示例数据"));
    doc.getElementById("btnConfirmOk").click(); await sleep(30);
    ok("G 确认后横幅立即消失", doc.getElementById("demoBanner").innerHTML === "");
    ok("G 确认后胶囊不再是示例模式", !(doc.getElementById("syncStatus").textContent || "").includes("示例模式"));
    const db = JSON.parse(win.localStorage.getItem("atlas-db"));
    ok("G 数据清空且 demo 标记为假", !db.demo && db.identities.length === 0 && db.links.length === 0);
    win.render(); await sleep(20);
    ok("G 重渲染后横幅仍隐藏", doc.getElementById("demoBanner").innerHTML === "");
    await sleep(2400);
    ok("G 清除示例全程不 PUT", fetchCalls.filter(c => c.method === "PUT").length === 0);
    /* 刷新（新页面读同一份 localStorage）不复活 */
    const dbNow = win.localStorage.getItem("atlas-db");
    dom.window.close();
    const again = makeDom({ ls: { "atlas-dav": dav, "atlas-db": dbNow } });
    await sleep(60);
    ok("G 刷新后横幅不复活", again.dom.window.document.getElementById("demoBanner").innerHTML === "");
    again.dom.window.close();
  }

  console.log(fails === 0 ? "ALL_TESTS_OK" : ("FAILURES=" + fails));
  process.exit(fails ? 1 : 0);
})().catch(e => { console.error("HARNESS_ERROR", e); process.exit(2); });
