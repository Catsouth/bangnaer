/* v1.7.0 PM 走查修复回归：撤销/回收站/打码持久/屏幕锁/安装提示/搜索拼音排序/渲染上限/
   一键补标/空卡轮询/最近可点/候选置信度与改绑/apply 去重/DAV 人话报错/拉取冲突/关页拦截/恢复入口 */
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
  const fetchCalls = [];
  const dom = new JSDOM(html, {
    url: "http://localhost/", runScripts: "dangerously", pretendToBeVisual: true,
    userAgent: seed.ua || undefined,
    beforeParse(window) {
      if (seed.ua) { try { Object.defineProperty(window.navigator, "userAgent", { configurable: true, get: () => seed.ua }); } catch (e) {} }
      window.fetch = (url, opts = {}) => { fetchCalls.push({ url: String(url), method: opts.method || "GET" }); return Promise.resolve({ ok: true, status: 200, text: () => Promise.resolve(seed.remote ? JSON.stringify(seed.remote) : "{}") }); };
      window.URL.createObjectURL = () => "blob:stub";
      if (seed.ls) for (const k in seed.ls) window.localStorage.setItem(k, seed.ls[k]);
    }
  });
  const doc = dom.window.document;
  doc.querySelectorAll("dialog").forEach(d => { d.showModal = () => { d.dataset.opened = "1"; }; d.close = () => { d.dataset.opened = ""; }; });
  return { dom, win: dom.window, doc, fetchCalls };
}
const ID = (v, type = "email", id) => ({ id: id || ("i_" + v), type, value: v, label: "" });
const LK = (iid, name, domain, extra = {}) => Object.assign({ id: "l_" + Math.random().toString(36).slice(2, 8), identityId: iid, domain, name, username: "", method: "密码登录", status: "active", createdAt: Date.now() }, extra);

(async () => {
  /* ---------- 1. 安装提示：iOS 出现 / 桌面不出现 / 关掉记住 ---------- */
  {
    const { win, doc } = makeDom({ ua: "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1" });
    await sleep(60);
    ok("iOS 未装时有加主屏提示", (doc.getElementById("installTip").textContent || "").includes("添加到主屏幕"));
    doc.getElementById("btnInstallTipX").click(); await sleep(20);
    ok("点知道了后提示消失且记住", doc.getElementById("installTip").innerHTML === "" && win.localStorage.getItem("atlas-install-tip") === "1");
    win.close();
  }
  {
    const { win, doc } = makeDom();
    await sleep(60);
    ok("桌面 UA 不出安装提示", doc.getElementById("installTip").innerHTML === "");
    win.close();
  }

  /* ---------- 2. 打码持久化：atlas-privacy=1 时重开即打码 ---------- */
  {
    const db = { identities: [ID("me@example.com")], links: [], updatedAt: 5 };
    const { win, doc } = makeDom({ ls: { "atlas-db": JSON.stringify(db), "atlas-privacy": "1" } });
    await sleep(60);
    const val = doc.querySelector(".idcard .val");
    ok("打码持久：重开页面卡面已打码", !!val && val.textContent.includes("•••"), val && val.textContent);
    win.close();
  }

  /* ---------- 3. 删服务可撤销 ---------- */
  {
    const db = { identities: [ID("me@example.com", "email", "a1")], links: [LK("a1", "GitHub", "github.com"), LK("a1", "知乎", "zhihu.com")], updatedAt: 5 };
    const { win, doc } = makeDom({ ls: { "atlas-db": JSON.stringify(db) } });
    await sleep(60);
    doc.querySelectorAll(".tabbtn")[1].click(); await sleep(30);
    doc.querySelector("#appList [data-del]").click(); await sleep(30);
    let saved = JSON.parse(win.localStorage.getItem("atlas-db"));
    ok("删服务后 links 少一条 + 撤销条出现", saved.links.length === 1 && doc.getElementById("undoBar").classList.contains("show"));
    doc.getElementById("undoBtn").click(); await sleep(30);
    saved = JSON.parse(win.localStorage.getItem("atlas-db"));
    ok("点撤销后数据恢复", saved.links.length === 2);
    win.close();
  }

  /* ---------- 4. 删身份卡进回收站 + 恢复 ---------- */
  {
    const db = { identities: [ID("me@example.com", "email", "a1"), ID("13800138000", "phone", "a2")], links: [LK("a1", "GitHub", "github.com")], updatedAt: 5 };
    const { win, doc } = makeDom({ ls: { "atlas-db": JSON.stringify(db) } });
    win.confirm = () => true;
    await sleep(60);
    win.eval("openIdDetail('a1')");
    doc.getElementById("btnIdDelete").click(); await sleep(30);
    let saved = JSON.parse(win.localStorage.getItem("atlas-db"));
    ok("删卡进回收站（identities-1, trash=1, links 带走）", saved.identities.length === 1 && saved.trash.length === 1 && saved.links.length === 0, JSON.stringify(saved.trash && saved.trash.length));
    doc.querySelectorAll(".tabbtn")[3].click(); await sleep(20);
    ok("设置页回收站副标题显示数量", (doc.getElementById("setTrashSub").textContent || "").includes("1"));
    doc.getElementById("btnTrash").click(); await sleep(20);
    ok("回收站列表有恢复按钮", !!doc.querySelector("#trashList [data-restore]"));
    doc.querySelector("#trashList [data-restore]").click(); await sleep(30);
    saved = JSON.parse(win.localStorage.getItem("atlas-db"));
    ok("恢复后整卡回来", saved.identities.length === 2 && saved.links.length === 1 && saved.trash.length === 0);
    win.close();
  }

  /* ---------- 5. 加身份：查重 + 格式警告 ---------- */
  {
    const db = { identities: [ID("me@example.com", "email", "a1")], links: [], updatedAt: 5 };
    const { win, doc } = makeDom({ ls: { "atlas-db": JSON.stringify(db) } });
    let confirmMsg = "";
    win.confirm = m => { confirmMsg = m; return false; };
    await sleep(60);
    doc.getElementById("idType").value = "email";
    doc.getElementById("idValue").value = "me@example.com";
    doc.getElementById("btnIdSave").click(); await sleep(20);
    let saved = JSON.parse(win.localStorage.getItem("atlas-db"));
    ok("同值身份不重复新建", saved.identities.length === 1);
    doc.getElementById("idValue").value = "notanemail";
    doc.getElementById("btnIdSave").click(); await sleep(20);
    saved = JSON.parse(win.localStorage.getItem("atlas-db"));
    ok("非法邮箱触发警告且未保存", confirmMsg.includes("不像邮箱") && saved.identities.length === 1, confirmMsg);
    win.close();
  }

  /* ---------- 6. 搜索拼音 / 高亮 / 排序 ---------- */
  {
    const links = [LK("a1", "微信", "weixin.qq.com"), LK("a1", "支付宝", "alipay.com"), LK("a1", "GitHub", "github.com")];
    const db = { identities: [ID("me@example.com", "email", "a1")], links, updatedAt: 5 };
    const { win, doc } = makeDom({ ls: { "atlas-db": JSON.stringify(db) } });
    await sleep(60);
    doc.querySelectorAll(".tabbtn")[1].click(); await sleep(30);
    const q = doc.getElementById("q");
    q.value = "wx"; q.oninput(); await sleep(20);
    ok("搜 wx 命中微信、不含支付宝", doc.getElementById("appList").textContent.includes("微信") && !doc.getElementById("appList").textContent.includes("支付宝"));
    ok("结果计数显示", (doc.getElementById("appCount").textContent || "").includes("1"));
    q.value = "支付"; q.oninput(); await sleep(20);
    ok("中文命中高亮 mark", doc.querySelector("#appList .nm mark") && doc.querySelector("#appList .nm mark").textContent === "支付");
    q.value = ""; q.oninput(); await sleep(20);
    const sel = doc.getElementById("appSort"); sel.value = "name"; sel.onchange({ target: sel }); await sleep(20);
    const names = [...doc.querySelectorAll("#appList .svc .nm")].map(e => e.textContent);
    ok("按名称排序生效（中文按拼音：微信<支付宝<GitHub）", names.length === 3 && names[0].includes("微信") && names[1].includes("支付宝") && names[2].includes("GitHub"), JSON.stringify(names));
    win.close();
  }

  /* ---------- 7. 渲染上限 120 ---------- */
  {
    const links = []; for (let i = 0; i < 130; i++) links.push(LK("a1", "服务" + i, "s" + i + ".com"));
    const db = { identities: [ID("me@example.com", "email", "a1")], links, updatedAt: 5 };
    const { win, doc } = makeDom({ ls: { "atlas-db": JSON.stringify(db) } });
    await sleep(60);
    doc.querySelectorAll(".tabbtn")[1].click(); await sleep(40);
    const rows = doc.querySelectorAll("#appList .svc").length;
    ok("130 条只渲染 ≤120 行 + 显示全部按钮", rows > 0 && rows <= 120 && !!doc.getElementById("btnShowAllApps"), "rows=" + rows);
    doc.getElementById("btnShowAllApps").click(); await sleep(40);
    ok("点显示全部后 130 行", doc.querySelectorAll("#appList .svc").length === 130);
    win.close();
  }

  /* ---------- 8. 一键补标登录方式 ---------- */
  {
    const links = [LK("a1", "甲", "a.com"), LK("a1", "乙", "b.com"), LK("a1", "丙", "c.com")];
    links.forEach(l => delete l.method);
    const db = { identities: [ID("me@example.com", "email", "a1")], links, updatedAt: 5 };
    const { win, doc } = makeDom({ ls: { "atlas-db": JSON.stringify(db) } });
    win.confirm = () => true;
    await sleep(60);
    doc.querySelectorAll(".tabbtn")[1].click(); await sleep(30);
    doc.querySelector('[data-h="nomethod"]').click(); await sleep(30);
    ok("未标筛选视图有一键补标按钮", !!doc.getElementById("btnBulkMethod"));
    doc.getElementById("btnBulkMethod").click(); await sleep(30);
    const saved = JSON.parse(win.localStorage.getItem("atlas-db"));
    ok("一键补标后全部有 method", saved.links.every(l => l.method === "密码登录"));
    win.close();
  }

  /* ---------- 9. 空卡定位轮询 ---------- */
  {
    const db = { identities: [ID("e1@x.com", "email", "e1"), ID("e2@x.com", "email", "e2"), ID("e3@x.com", "email", "e3")], links: [LK("e3", "GitHub", "github.com")], updatedAt: 5 };
    const { win, doc } = makeDom({ ls: { "atlas-db": JSON.stringify(db) } });
    await sleep(60);
    doc.querySelectorAll(".tabbtn")[1].click(); await sleep(30);
    doc.querySelector('[data-h="empty"]').click(); await sleep(30);
    const t1 = doc.getElementById("svcTitle").textContent;
    doc.querySelectorAll(".tabbtn")[1].click(); await sleep(30);
    doc.querySelector('[data-h="empty"]').click(); await sleep(30);
    const t2 = doc.getElementById("svcTitle").textContent;
    ok("空卡定位两次落到不同卡", t1 !== t2 && t1.includes("@x.com") && t2.includes("@x.com"), t1 + " / " + t2);
    win.close();
  }

  /* ---------- 10. 最近添加可点开编辑 ---------- */
  {
    const db = { identities: [ID("me@example.com", "email", "a1")], links: [LK("a1", "GitHub", "github.com", { createdAt: Date.now() })], updatedAt: 5 };
    const { win, doc } = makeDom({ ls: { "atlas-db": JSON.stringify(db) } });
    await sleep(60);
    const rc = doc.querySelector(".rcard[data-edit]");
    ok("最近卡带 data-edit", !!rc);
    rc.click(); await sleep(20);
    ok("点最近卡打开服务编辑且标题正确", doc.getElementById("dlgSvcEdit").dataset.opened === "1" && doc.getElementById("svcEditTitle").textContent === "GitHub");
    win.close();
  }

  /* ---------- 11. 编辑弹窗改绑身份 ---------- */
  {
    const db = { identities: [ID("me@example.com", "email", "a1"), ID("13800138000", "phone", "a2")], links: [LK("a1", "GitHub", "github.com", { id: "l1" })], updatedAt: 5 };
    const { win, doc } = makeDom({ ls: { "atlas-db": JSON.stringify(db) } });
    await sleep(60);
    win.eval("openSvcEdit('l1')");
    doc.getElementById("editIdentity").value = "a2";
    doc.getElementById("btnSvcEditSave").click(); await sleep(20);
    const saved = JSON.parse(win.localStorage.getItem("atlas-db"));
    ok("改绑后 identityId 更新", saved.links[0].identityId === "a2");
    win.close();
  }

  /* ---------- 12. 候选：置信度 / 改绑下拉 / apply 去重 / 坏邮箱不识别 ---------- */
  {
    const { win, doc } = makeDom();
    await sleep(60);
    win.eval("parseText('联系 a@b.c 或 me@example.com，我注册了 GitHub')");
    const cands = win.eval("candidates");
    const idVals = cands.filter(c => c.kind === "identity").map(c => c.value);
    ok("坏邮箱 a@b.c 不生成身份、正常邮箱生成", !idVals.includes("a@b.c") && idVals.includes("me@example.com"), JSON.stringify(idVals));
    win.eval("showCandidates()");
    const ghIdx = cands.findIndex(c => c.kind === "link" && (c.domain === "github.com"));
    ok("文本猜出的绑定候选存在", ghIdx >= 0);
    const cb = doc.querySelector('[data-ci="' + ghIdx + '"]');
    ok("低置信候选默认不勾 + 有 ⚠ 标", !!cb && cb.checked === false && doc.getElementById("candBox").textContent.includes("不太确定"));
    ok("候选行有改绑身份下拉", !!doc.querySelector('[data-ciid="' + ghIdx + '"]'));
    const idRef = cands.find(c => c.kind === "identity" && c.value === "me@example.com").ref.id;
    const sel = doc.querySelector('[data-ciid="' + ghIdx + '"]');
    sel.value = idRef; sel.onchange(); await sleep(10);
    cb.checked = true; cb.onchange(); await sleep(10);
    doc.getElementById("btnApplyCand").click(); await sleep(30);
    let saved = JSON.parse(win.localStorage.getItem("atlas-db"));
    ok("apply 后入库且绑对身份", saved.links.length === 1 && saved.links[0].identityId === idRef && saved.identities.length === 1, JSON.stringify(saved.links));
    ok("apply 后切到卡包页（无 alert 流程）", doc.getElementById("pageWallet").style.display !== "none");
    /* apply 层去重：手工塞一条一模一样的候选再 apply */
    win.eval("candidates.push({kind:'link',key:'dup',domain:'github.com',name:'GitHub',username:'',identityId:'" + idRef + "',checked:true,why:'手动测试'});showCandidates()");
    doc.getElementById("btnApplyCand").click(); await sleep(30);
    saved = JSON.parse(win.localStorage.getItem("atlas-db"));
    ok("重复 apply 不翻倍", saved.links.length === 1, "links=" + saved.links.length);
    win.close();
  }

  /* ---------- 13. DAV 错误人话 + 拉取冲突保护 + 关页拦截 ---------- */
  {
    ok("davErrMsg 翻译（源码级）", html.includes("账号或密码不对") && html.includes("地址不对或文件夹不存在") && html.includes("连不上服务器"));
    const dav = JSON.stringify({ url: "https://dav.example.com/dav/atlas.json", user: "u", pass: "p" });
    const local = { identities: [ID("local@x.com", "email", "L1")], links: [], updatedAt: 1000 };
    const { win, doc } = makeDom({ ls: { "atlas-dav": dav, "atlas-db": JSON.stringify(local) }, remote: { identities: [], links: [], updatedAt: 1 } });
    await sleep(60);
    ok("davErrMsg(401) 含人话", win.eval("davErrMsg(new Error('HTTP 401'))").includes("账号或密码不对"));
    ok("davErrMsg(404) 含人话", win.eval("davErrMsg(new Error('HTTP 404'))").includes("地址不对或文件夹不存在"));
    ok("davErrMsg(TypeError) 含人话", win.eval("davErrMsg(new TypeError('Failed to fetch'))").includes("连不上服务器"));
    /* 本地弄脏：改 fetch 让 PUT 挂起，save() 后 davDirty 保持 true */
    const remote2 = { identities: [ID("remote@x.com", "email", "R1")], links: [], updatedAt: Date.now() + 1e9 };
    win.fetch = (url, opts = {}) => (opts.method === "PUT") ? new Promise(() => {}) : Promise.resolve({ ok: true, status: 200, text: () => Promise.resolve(JSON.stringify(remote2)) });
    win.eval("save()");
    await win.eval("pull(true)");
    let cur = JSON.parse(win.localStorage.getItem("atlas-db"));
    ok("有未上传改动时自动拉取不覆盖本地", cur.identities.length === 1 && cur.identities[0].id === "L1");
    ok("冲突时胶囊亮红提示", doc.getElementById("syncStatus").className.includes("err"), doc.getElementById("syncStatus").textContent);
    const ev = new win.Event("beforeunload", { cancelable: true });
    win.dispatchEvent(ev);
    ok("有未同步改动时关页被拦截", ev.defaultPrevented === true);
    win.close();
  }

  /* ---------- 14. 屏幕锁 ---------- */
  {
    const { win, doc } = makeDom();
    await sleep(60);
    win.eval("localStorage.setItem('atlas-lock-pin', hashPin('1234')); localStorage.setItem('atlas-lock','1'); showLockIfNeeded()");
    ok("开启屏幕锁后锁定层出现", doc.getElementById("lockScreen").style.display === "flex");
    doc.getElementById("lockPin").value = "0000";
    doc.getElementById("btnUnlock").click(); await sleep(10);
    ok("错 PIN 不解锁", doc.getElementById("lockScreen").style.display === "flex");
    doc.getElementById("lockPin").value = "1234";
    doc.getElementById("btnUnlock").click(); await sleep(10);
    ok("对 PIN 解锁", doc.getElementById("lockScreen").style.display === "none");
    win.close();
  }

  /* ---------- 15. 设置页恢复入口（整份覆盖） ---------- */
  {
    const db = { identities: [ID("old@x.com", "email", "o1")], links: [], updatedAt: 5 };
    const { win, doc } = makeDom({ ls: { "atlas-db": JSON.stringify(db) } });
    win.confirm = () => true;
    await sleep(60);
    ok("设置页有导入备份恢复行", !!doc.getElementById("btnRestore"));
    const backup = { identities: [ID("new@x.com", "email", "n1"), ID("13900139000", "phone", "n2")], links: [LK("n1", "GitHub", "github.com")], updatedAt: 777 };
    const file = new win.File([JSON.stringify(backup)], "bind-backup.json", { type: "application/json" });
    const input = doc.getElementById("fileRestore");
    Object.defineProperty(input, "files", { configurable: true, value: [file] });
    input.dispatchEvent(new win.Event("change")); await sleep(60);
    const saved = JSON.parse(win.localStorage.getItem("atlas-db"));
    ok("恢复后 DB 被整份替换", saved.identities.length === 2 && saved.links.length === 1 && saved.identities[0].value === "new@x.com");
    win.close();
  }

  /* ---------- 16. 导出首次明文提醒 ---------- */
  {
    const { win, doc } = makeDom();
    let msg = ""; win.confirm = m => { msg = m; return false; };
    await sleep(60);
    doc.getElementById("btnExport").click(); await sleep(10);
    ok("首次导出弹明文提醒", msg.includes("明文") && msg.includes("不含密码"), msg.slice(0, 30));
    win.close();
  }

  /* ---------- 17. 关系图：手势提示 + 服务过多引导 ---------- */
  {
    const links = []; for (let i = 0; i < 45; i++) links.push(LK("a1", "服务" + i, "s" + i + ".com"));
    const db = { identities: [ID("me@example.com", "email", "a1")], links, updatedAt: 5 };
    const { win, doc } = makeDom({ ls: { "atlas-db": JSON.stringify(db) } });
    await sleep(60);
    doc.querySelectorAll(".tabbtn")[2].click(); await sleep(60);
    ok("星系画布有手势提示", !!doc.getElementById("gHint"));
    ok("服务 >40 时有缩小范围引导", (doc.getElementById("graphBox").textContent || "").includes("先看它自己的星系"));
    ok("chips 渐隐 CSS 在位", html.includes("-webkit-mask-image:linear-gradient(90deg,#000 0,#000 calc(100% - 34px),transparent 100%)"));
    win.close();
  }

  /* ---------- 18. 文案与预设的源码级断言 ---------- */
  ok("DAV 快捷填充（坚果云）存在", html.includes('data-davpreset="jg"') && html.includes("应用密码"));
  ok("长按教学文案已更新", html.includes("长按卡片约半秒（卡会震一下）可拖动排序"));
  ok("粘贴框给了具体例子", html.includes("它会自动认出里面的邮箱、手机号和服务名"));
  ok("弹窗点遮罩关闭已挂", html.includes('if(e.target===d)d.close()'));

  console.log(fails === 0 ? "PM_TESTS_OK" : ("PM_FAILURES=" + fails));
  process.exit(fails ? 1 : 0);
})().catch(e => { console.error("HARNESS_ERROR", e); process.exit(2); });
