/* 关系图 v2 星系蜂窝：计数与高亮桩测
   - 全部视图：气泡数=去重服务数、线条数=有效绑定数（已注销不画）
   - 单身份视图：气泡数=该身份服务数、线条数=该身份有效绑定数
   - 点气泡：高亮线 opacity 0.95、其余 0.06、信息条出现；再点取消
   - 示例数据：4 身份 / 11 绑定（1 注销）→ 10 气泡 10 线 */
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
      window.fetch = (url, opts = {}) => { fetchCalls.push({ url: String(url), method: opts.method || "GET" }); return Promise.resolve({ ok: true, status: 200, text: () => Promise.resolve("{}") }); };
      window.URL.createObjectURL = () => "blob:stub";
      if (seed && seed.ls) for (const k in seed.ls) window.localStorage.setItem(k, seed.ls[k]);
    }
  });
  return { dom, fetchCalls };
}
const paths = doc => [...doc.querySelectorAll("#graphBox path.gl")];
const bubs = doc => [...doc.querySelectorAll("[data-gbub]")];
const chips = doc => [...doc.querySelectorAll("[data-gchip]")];

(async () => {
  /* ---------- A. 自定义数据：计数与高亮 ---------- */
  {
    const db = {
      identities: [
        { id: "e1", type: "email", value: "a@x.com", label: "" },
        { id: "e2", type: "email", value: "b@x.com", label: "" },
        { id: "p1", type: "phone", value: "13500000000", label: "" },
        { id: "w1", type: "wechat", value: "wx_one", label: "" }
      ],
      links: [
        { id: "l1", identityId: "e1", domain: "a.com", name: "A站", username: "u1", method: "密码登录", status: "active", createdAt: 1 },
        { id: "l2", identityId: "e1", domain: "b.com", name: "B站", username: "u1", method: "密码登录", status: "active", createdAt: 2 },
        { id: "l3", identityId: "e2", domain: "a.com", name: "A站", username: "u2", method: "Google 授权", status: "active", createdAt: 3 },
        { id: "l4", identityId: "p1", domain: "c.com", name: "C站", username: "u3", method: "手机号验证码", status: "active", createdAt: 4 },
        { id: "l5", identityId: "w1", domain: "d.com", name: "D站", username: "u4", method: "微信授权", status: "active", createdAt: 5 },
        { id: "l6", identityId: "p1", domain: "x.com", name: "X站", username: "u3", method: "密码登录", status: "cancelled", createdAt: 6 }
      ],
      updatedAt: 1000
    };
    const { dom } = makeDom({ ls: { "atlas-db": JSON.stringify(db) } });
    const win = dom.window, doc = win.document;
    await sleep(60);
    doc.querySelectorAll(".tabbtn")[2].click(); await sleep(60);
    ok("chips=全部+4 身份", chips(doc).length === 5, "chips=" + chips(doc).length);
    ok("全部视图气泡=去重服务数 4", bubs(doc).length === 4, "bubs=" + bubs(doc).length);
    ok("全部视图线条=有效绑定数 5（注销不画）", paths(doc).length === 5, "paths=" + paths(doc).length);
    ok("已注销服务 X站 无气泡", !bubs(doc).some(b => b.dataset.gbub.includes("x.com")));
    const parts = doc.querySelectorAll("#graphBox circle.gp").length;
    ok("粒子数=每线 3（流光头+2 尾点）且 ≤绑定×3", parts === paths(doc).length * 3 && parts <= 15, "particles=" + parts);
    ok("连线有光晕打底层（glglow=线数）", doc.querySelectorAll("#graphBox path.glglow").length === paths(doc).length);
    // A站 的两条线颜色不同（e1 邮箱色 / e2 同为邮箱色，但来自两条绑定）——检查 A 有 2 条线
    const aPaths = paths(doc).filter(p => { const b = bubs(doc).find(x => x.dataset.gbub === "a.com|A站"); return b && p.getAttribute("d").includes(""); });
    ok("线条带 stroke 颜色", paths(doc).every(p => (p.getAttribute("stroke") || "").startsWith("#")));
    // 选 e1
    doc.querySelector('[data-gchip="e1"]').click(); await sleep(40);
    ok("单身份 e1 气泡=2", bubs(doc).length === 2, "bubs=" + bubs(doc).length);
    ok("单身份 e1 线条=2", paths(doc).length === 2, "paths=" + paths(doc).length);
    ok("核心文字在圆内（.gcore 含 e1 值）", (doc.querySelector(".gcore") || { textContent: "" }).textContent.includes("a@x.com"));
    ok("核心外无 caption 节点（.gcore-name 不存在）", !doc.querySelector(".gcore-name"));
    // 点 A 气泡高亮
    const bubA = bubs(doc).find(b => b.dataset.gbub === "a.com|A站");
    bubA.click(); await sleep(40);
    ok("点气泡出现信息条且含服务名", !!doc.querySelector(".ginfo") && doc.querySelector(".ginfo").textContent.includes("A站"));
    ok("信息条含身份与登录方式", doc.querySelector(".ginfo").textContent.includes("a@x.com") && doc.querySelector(".ginfo").textContent.includes("密码登录"));
    ok("气泡带 hl 类", bubA.classList.contains("hl") || doc.querySelector("[data-gbub].hl") !== null);
    const ops = paths(doc).map(p => p.getAttribute("opacity"));
    ok("高亮线 opacity=1×1、其余 0.06", ops.filter(o => o === "1").length === 1 && ops.filter(o => o === "0.06").length === 1, ops.join(","));
    // 再点取消
    doc.querySelector('[data-gbub="a.com|A站"]').click(); await sleep(40);
    ok("再点气泡取消高亮（信息条消失）", !doc.querySelector(".ginfo"));
    // 切回全部
    doc.querySelector('[data-gchip="all"]').click(); await sleep(40);
    ok("切回全部：气泡 4 线条 5", bubs(doc).length === 4 && paths(doc).length === 5, `bubs=${bubs(doc).length} paths=${paths(doc).length}`);
    /* ---------- A2. v1.6.1：标签方向 / 气泡尺寸 / 蜂窝拖动 ---------- */
    ok("气泡名称都带方向 class（lb-*）", bubs(doc).every(b => /lb-(n|s|e|w|ne|nw|se|sw)/.test((b.querySelector(".gbub-name") || {}).className || "")));
    ok("全部视图气泡直径变量 --bub:44px", (doc.querySelector(".gworld")?.style.getPropertyValue("--bub") || "").trim() === "44px");
    ok("bubLabelDir 方位正确", win.bubLabelDir(0, -1) === "lb-n" && win.bubLabelDir(1, 0) === "lb-e" && win.bubLabelDir(0, 1) === "lb-s" && win.bubLabelDir(-1, 0) === "lb-w" && win.bubLabelDir(1, 1) === "lb-se" && win.bubLabelDir(-1, -1) === "lb-nw");
    ok("距离缩放函数在位且单调（近大远小）", typeof win.galaxyDistScale === "function" && win.galaxyDistScale(0) > win.galaxyDistScale(240) && win.galaxyDistScale(999) >= 0.55);
    ok("拖动函数在位（galaxyApplyPan/galaxyClampPan/galaxyAttachDrag）", ["galaxyApplyPan", "galaxyClampPan", "galaxyAttachDrag"].every(f => typeof win[f] === "function"));
    ok("源码含拖动阈值常量 GALAXY_DRAG_THRESH=6", /GALAXY_DRAG_THRESH\s*=\s*6/.test(html));
    ok("画布 CSS 带 touch-action:none", /\.gstage\{[^}]*touch-action:\s*none/.test(html));
    doc.querySelector('[data-gchip="e1"]').click(); await sleep(40);
    ok("单身份视图气泡直径变量 --bub:46px", (doc.querySelector(".gworld")?.style.getPropertyValue("--bub") || "").trim() === "46px");
    const st = doc.getElementById("gstage"), world = st.querySelector(".gworld");
    const pe = (type, x, y) => { const ev = new win.MouseEvent(type, { bubbles: true, cancelable: true }); Object.defineProperties(ev, { clientX: { value: x }, clientY: { value: y }, pointerId: { value: 7 } }); return ev; };
    st.dispatchEvent(pe("pointerdown", 200, 200));
    st.dispatchEvent(pe("pointermove", 262, 214));
    await sleep(80);
    const tf = world.style.transform || "";
    ok("拖动后世界层带非零 translate", /translate\(/.test(tf) && !tf.startsWith("translate(0.0px, 0.0px)"), tf);
    const bsVal = parseFloat((bubs(doc)[0].style.getPropertyValue("--bs") || "1"));
    ok("拖动后气泡带距离缩放变量 --bs", bsVal >= 0.55 && bsVal <= 1.05, "--bs=" + bsVal);
    st.dispatchEvent(pe("pointerup", 262, 214));
    bubs(doc)[0].click(); await sleep(30);
    ok("拖动后紧随的点击被抑制（无信息条）", !doc.querySelector(".ginfo"));
    await sleep(160);
    bubs(doc)[0].click(); await sleep(40);
    ok("抑制窗口过后点击恢复（信息条出现）", !!doc.querySelector(".ginfo"));
    dom.window.close();
  }

  /* ---------- B. 示例数据计数 ---------- */
  {
    const { dom } = makeDom();
    const win = dom.window, doc = win.document;
    await sleep(60);
    const demoBtn = doc.querySelector("#btnDemoStart");
    ok("示例入口存在", !!demoBtn);
    demoBtn.click(); await sleep(40);
    doc.querySelectorAll(".tabbtn")[2].click(); await sleep(60);
    ok("示例 chips=全部+4 身份", chips(doc).length === 5, "chips=" + chips(doc).length);
    ok("示例全部视图气泡=10（去重服务）", bubs(doc).length === 10, "bubs=" + bubs(doc).length);
    ok("示例全部视图线条=10（11 绑定-1 注销）", paths(doc).length === 10, "paths=" + paths(doc).length);
    ok("示例已注销 人人网 无气泡", !bubs(doc).some(b => b.dataset.gbub.includes("renren")));
    // 选手机号身份（demo-phone，4 个在用服务）
    doc.querySelector('[data-gchip="demo-phone"]').click(); await sleep(40);
    ok("示例手机号视图气泡=4 线条=4", bubs(doc).length === 4 && paths(doc).length === 4, `bubs=${bubs(doc).length} paths=${paths(doc).length}`);
    ok("示例手机号核心文字在圆内且无 caption 节点", (doc.querySelector(".gcore") || { textContent: "" }).textContent.includes("13800138000") && !doc.querySelector(".gcore-name"));
    ok("示例手机号粒子=线×3=12", doc.querySelectorAll("#graphBox circle.gp").length === 12, "particles=" + doc.querySelectorAll("#graphBox circle.gp").length);
    dom.window.close();
  }

  /* ---------- C. v1.10.1：初始落位按包围盒（居中、略偏下），切 chips 重新落位 ---------- */
  {
    const { dom } = makeDom({ ls: { "atlas-db": JSON.stringify({
      identities: [
        { id: "e1", type: "email", value: "a@x.com", label: "" },
        { id: "e2", type: "email", value: "b@x.com", label: "" },
        { id: "p1", type: "phone", value: "13500000000", label: "" },
        { id: "w1", type: "wechat", value: "wx_one", label: "" }
      ],
      links: [
        { id: "l1", identityId: "e1", domain: "a.com", name: "A站", username: "u1", method: "密码登录", status: "active", createdAt: 1 },
        { id: "l2", identityId: "e1", domain: "b.com", name: "B站", username: "u1", method: "密码登录", status: "active", createdAt: 2 },
        { id: "l3", identityId: "e2", domain: "a.com", name: "A站", username: "u2", method: "Google 授权", status: "active", createdAt: 3 },
        { id: "l4", identityId: "p1", domain: "c.com", name: "C站", username: "u3", method: "手机号验证码", status: "active", createdAt: 4 },
        { id: "l5", identityId: "w1", domain: "d.com", name: "D站", username: "u4", method: "微信授权", status: "active", createdAt: 5 }
      ],
      updatedAt: 1000
    }) } });
    const win = dom.window, doc = win.document;
    await sleep(60);
    /* 纯函数：包围盒/缩放/平移的数学先钉死（不依赖 DOM） */
    ok("落位函数在位（galaxyBBox/galaxyFitScale/galaxyFitPan）",
      ["galaxyBBox", "galaxyFitScale", "galaxyFitPan"].every(f => typeof win[f] === "function"));
    const bbT = win.galaxyBBox(168, 168, [[-54, 93.5], [54, 93.5]], 23);
    ok("galaxyBBox：偏下双气泡的包围盒中心在世界中心下方（cy=208.25）",
      Math.abs(bbT.w - 154) < 0.01 && Math.abs(bbT.h - 152.5) < 0.01 && Math.abs(bbT.cx - 168) < 0.01 && Math.abs(bbT.cy - 208.25) < 0.01,
      `w=${bbT.w} h=${bbT.h} cx=${bbT.cx} cy=${bbT.cy}`);
    const panT = win.galaxyFitPan(bbT, 168, 168, 1.25, 336);
    ok("galaxyFitPan：包围盒中心映射到画布（中线, 56% 高）",
      Math.abs((bbT.cx - 168) * 1.25 + panT.x) < 0.01 && Math.abs((168 + (bbT.cy - 168) * 1.25 + panT.y) - 336 * 0.56) < 0.01,
      `pan=${panT.x},${panT.y}`);
    ok("galaxyFitScale：不小于原 f（大图不缩）、封顶 1.25（小图不爆）",
      win.galaxyFitScale({ w: 900, h: 900 }, 0.6, 360, 336) === 0.6 && win.galaxyFitScale({ w: 10, h: 10 }, 1, 360, 336) === 1.25);
    /* DOM 集成：jsdom 无布局，clientWidth=0 → 代码回退 stageW=360，公式照常跑 */
    const STAGE_W = 360;
    const readFit = () => {
      const st = doc.getElementById("gstage"), world = st.querySelector(".gworld");
      const m = (world.style.transform || "").match(/translate\((-?[\d.]+)px, (-?[\d.]+)px\) scale\(([\d.]+)\)/);
      if (!m) return null;
      const worldW = parseFloat(world.style.width), cx = worldW / 2, cy = worldW / 2;
      const bubR = parseFloat(world.style.getPropertyValue("--bub")) / 2;
      const core = st.querySelector(".gcore"), coreR = core ? parseFloat(core.style.width) / 2 : 36;
      let x0 = cx - coreR, x1 = cx + coreR, y0 = cy - coreR, y1 = cy + coreR;
      bubs(doc).forEach(b => {
        const bx = parseFloat(b.style.left), by = parseFloat(b.style.top);
        x0 = Math.min(x0, bx - bubR); x1 = Math.max(x1, bx + bubR); y0 = Math.min(y0, by - bubR); y1 = Math.max(y1, by + bubR);
      });
      return { pan: { x: +m[1], y: +m[2] }, s: +m[3], stageH: parseFloat(st.style.height), cx, cy,
               bb: { cx: (x0 + x1) / 2, cy: (y0 + y1) / 2, x0, x1, y0, y1 }, tf: world.style.transform };
    };
    const checkFit = (name, F) => {
      const mx = STAGE_W / 2 + (F.bb.cx - F.cx) * F.s + F.pan.x, my = F.stageH / 2 + (F.bb.cy - F.cy) * F.s + F.pan.y;
      ok(name + "：包围盒中心落在画布中线、垂直 56%",
        Math.abs(mx - STAGE_W / 2) < 1.6 && Math.abs(my - F.stageH * 0.56) < 1.6, `mapped=${mx.toFixed(1)},${my.toFixed(1)} stageH=${F.stageH}`);
      const ex0 = STAGE_W / 2 + (F.bb.x0 - F.cx) * F.s + F.pan.x, ex1 = STAGE_W / 2 + (F.bb.x1 - F.cx) * F.s + F.pan.x;
      const ey0 = F.stageH / 2 + (F.bb.y0 - F.cy) * F.s + F.pan.y, ey1 = F.stageH / 2 + (F.bb.y1 - F.cy) * F.s + F.pan.y;
      ok(name + "：整群完整可见不溢出",
        ex0 >= -1 && ex1 <= STAGE_W + 1 && ey0 >= -1 && ey1 <= F.stageH + 1,
        `x:${ex0.toFixed(1)}~${ex1.toFixed(1)} y:${ey0.toFixed(1)}~${ey1.toFixed(1)}`);
    };
    doc.querySelectorAll(".tabbtn")[2].click(); await sleep(60);
    doc.querySelector('[data-gchip="e1"]').click(); await sleep(40);
    const fitE1 = readFit();
    ok("e1 视图（双气泡偏下）初始落位非旧版 (0,0)+原缩放", !!fitE1 && (Math.abs(fitE1.pan.y) > 5 || fitE1.s > 1.05), fitE1 && fitE1.tf);
    if (fitE1) checkFit("e1 视图", fitE1);
    doc.querySelector('[data-gchip="all"]').click(); await sleep(40);
    const fitAll = readFit();
    ok("切回全部：重新落位（transform 变化）", !!fitAll && !!fitE1 && fitAll.tf !== fitE1.tf, fitAll && fitAll.tf);
    if (fitAll) checkFit("全部视图", fitAll);
    doc.querySelector('[data-gchip="e1"]').click(); await sleep(40);
    const fitE1b = readFit();
    ok("再切回 e1：落位确定性复现（与首次一致）", !!fitE1b && !!fitE1 && fitE1b.tf === fitE1.tf, fitE1b && fitE1b.tf);
    bubs(doc)[0].click(); await sleep(40);
    const fitAfterTap = readFit();
    ok("同范围内点气泡重渲染：保留当前平移不重落位", !!fitAfterTap && !!fitE1b && fitAfterTap.tf === fitE1b.tf, fitAfterTap && fitAfterTap.tf);
    dom.window.close();
  }

  console.log(fails ? `\n${fails} FAIL` : "\nALL_GALAXY_TESTS_OK");
  process.exit(fails ? 1 : 0);
})().catch(e => { console.error("ERR", e); process.exit(1); });
