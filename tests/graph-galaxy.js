/* 关系图 v2 星系蜂窝：计数与高亮桩测
   - 全部视图：气泡数=去重服务数、线条数=有效绑定数（已注销不画）
   - 单身份视图：气泡数=该身份服务数、线条数=该身份有效绑定数
   - 点气泡：高亮线 opacity 0.95、其余 0.06、信息条出现；再点取消
   - 示例数据：4 身份 / 11 绑定（1 注销）→ 10 气泡 10 线
   - C 组：包围盒落位（中心中线/垂直 56%、整群不溢出、切范围重落、同范围保留平移）
   - D 组（v1.10.2）：双维容纳 fit（真机 390×540 断言）/ 隐藏预渲染后可见重 fit / 双指捏合缩放 */
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
    ok("落位函数在位（galaxyBBox/galaxyFitScale/galaxyFitPoint/galaxyPinchFrame）",
      ["galaxyBBox", "galaxyFitScale", "galaxyFitPoint", "galaxyPinchFrame"].every(f => typeof win[f] === "function"));
    const bbT = win.galaxyBBox(168, 168, [[-54, 93.5], [54, 93.5]], 23);
    ok("galaxyBBox：偏下双气泡的包围盒中心在世界中心下方（cy=208.25）",
      Math.abs(bbT.w - 154) < 0.01 && Math.abs(bbT.h - 152.5) < 0.01 && Math.abs(bbT.cx - 168) < 0.01 && Math.abs(bbT.cy - 208.25) < 0.01,
      `w=${bbT.w} h=${bbT.h} cx=${bbT.cx} cy=${bbT.cy}`);
    const ptT = win.galaxyFitPoint(bbT, 1.25, 360, 336);
    ok("galaxyFitPoint：包围盒中心映射到画布（中线, 56% 高），映射 S(p)=T+p*f",
      Math.abs(ptT.x + bbT.cx * 1.25 - 180) < 0.01 && Math.abs(ptT.y + bbT.cy * 1.25 - 336 * 0.56) < 0.01,
      `t=${ptT.x},${ptT.y}`);
    ok("galaxyFitScale：宽高两维取小（大图按容纳缩放，不再被宽度口径的旧 f 抬高）、封顶 1.25（小图不爆）",
      Math.abs(win.galaxyFitScale({ w: 900, h: 900 }, 360, 336) - (336 - 16) / 900) < 1e-9 && win.galaxyFitScale({ w: 10, h: 10 }, 360, 336) === 1.25);
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
      return { t: { x: +m[1], y: +m[2] }, s: +m[3], stageH: parseFloat(st.style.height),
               bb: { cx: (x0 + x1) / 2, cy: (y0 + y1) / 2, x0, x1, y0, y1 }, tf: world.style.transform };
    };
    /* v1.10.2 映射模型：世界层锚定 left:0/top:0 + origin 0 0，屏幕坐标 = T + 世界坐标 * f */
    const checkFit = (name, F, stageW = STAGE_W, stageH = F.stageH) => {
      const mx = F.t.x + F.bb.cx * F.s, my = F.t.y + F.bb.cy * F.s;
      const ex0 = F.t.x + F.bb.x0 * F.s, ex1 = F.t.x + F.bb.x1 * F.s;
      const ey0 = F.t.y + F.bb.y0 * F.s, ey1 = F.t.y + F.bb.y1 * F.s;
      /* 垂直落点：首选 56%；整群接近画布高、56% 会挤掉下边距时，落点回移到刚好留住 8px 下边距处 */
      const vCenterOk = Math.abs(my - stageH * 0.56) < 1.6 || Math.abs(ey1 - (stageH - 8)) < 1.6;
      ok(name + "：包围盒中心落在画布中线、垂直 56%（或为保边距回移）",
        Math.abs(mx - stageW / 2) < 1.6 && vCenterOk, `mapped=${mx.toFixed(1)},${my.toFixed(1)} stage=${stageW}x${stageH}`);
      ok(name + "：整群完整可见不溢出（四边距 ≥8px 口径，容差 1px）",
        ex0 >= 7 && ex1 <= stageW - 7 && ey0 >= 7 && ey1 <= stageH - 7,
        `x:${ex0.toFixed(1)}~${ex1.toFixed(1)} y:${ey0.toFixed(1)}~${ey1.toFixed(1)}`);
    };
    doc.querySelectorAll(".tabbtn")[2].click(); await sleep(60);
    doc.querySelector('[data-gchip="e1"]').click(); await sleep(40);
    const fitE1 = readFit();
    ok("e1 视图（双气泡偏下）初始落位非旧版 (0,0)+原缩放", !!fitE1 && (Math.abs(fitE1.t.y) > 5 || fitE1.s > 1.05), fitE1 && fitE1.tf);
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

  /* ============ D 组：v1.10.2 真机回归（双维 fit / 隐藏重落 / 捏合缩放） ============ */
  {
    /* 纯函数：真机量级画布 390×540。包围盒取真机示例数据「全部」视图的形状：
       核心 + 10 气泡（ring1 六个 + ring2 四个只占上/右），包围盒中心明显偏离世界中心 */
    const { dom: dom0 } = makeDom({});
    const w0 = dom0.window;
    await sleep(30);
    const bbD = w0.galaxyBBox(276, 276, [[0, -108], [93.5, -54], [93.5, 54], [0, 108], [-93.5, 54], [-93.5, -54], [0, -216], [93.5, -162], [187.1, -108], [187.1, 0]], 22);
    const fD = w0.galaxyFitScale(bbD, 390, 540), tD = w0.galaxyFitPoint(bbD, fD, 390, 540);
    const dX0 = tD.x + bbD.x0 * fD, dX1 = tD.x + bbD.x1 * fD, dY0 = tD.y + bbD.y0 * fD, dY1 = tD.y + bbD.y1 * fD;
    ok("D fit@390×540：包围盒四边都在画布内且留 ≥8px 边距",
      dX0 >= 8 - 1e-6 && dX1 <= 390 - 8 + 1e-6 && dY0 >= 8 - 1e-6 && dY1 <= 540 - 8 + 1e-6,
      `x:${dX0.toFixed(1)}~${dX1.toFixed(1)} y:${dY0.toFixed(1)}~${dY1.toFixed(1)} f=${fD.toFixed(3)}`);
    ok("D fit@390×540：包围盒中心落在（水平中线, 垂直 56%）",
      Math.abs(tD.x + bbD.cx * fD - 195) < 0.01 && Math.abs(tD.y + bbD.cy * fD - 540 * 0.56) < 0.01,
      `c=${(tD.x + bbD.cx * fD).toFixed(1)},${(tD.y + bbD.cy * fD).toFixed(1)}`);
    /* 高瘦包围盒：缩放必须被画布高度反算压住（嫌疑 c），56% 落点为保住上下边距回移 */
    const bbTall = { x0: 100, x1: 300, y0: 0, y1: 800, cx: 200, cy: 400, w: 200, h: 800 };
    const fTall = w0.galaxyFitScale(bbTall, 390, 540), tTall = w0.galaxyFitPoint(bbTall, fTall, 390, 540);
    ok("D fit 高瘦包围盒：缩放按高度容纳（f=(540-16)/800），上下边距恰为 8px",
      Math.abs(fTall - (540 - 16) / 800) < 1e-9 && Math.abs(tTall.y + bbTall.y0 * fTall - 8) < 0.01 && Math.abs(tTall.y + bbTall.y1 * fTall - (540 - 8)) < 0.01,
      `f=${fTall} ty=${tTall.y}`);
    /* 捏合纯逻辑：锚点不变性 + 相对 fit 的 0.5–2.5 倍限幅 */
    const pf = w0.galaxyPinchFrame(1.0, 1.0, 200, 300, 1.6, 195, 302);
    ok("D galaxyPinchFrame：锚点世界点缩放前后钉在同一屏幕位",
      Math.abs(pf.f - 1.6) < 1e-9 && Math.abs(pf.tx + 200 * pf.f - 195) < 1e-9 && Math.abs(pf.ty + 300 * pf.f - 302) < 1e-9,
      `f=${pf.f} t=${pf.tx},${pf.ty}`);
    ok("D galaxyPinchFrame：限幅在 fit 的 0.5–2.5 倍（与 fit 缩放成比例）",
      w0.galaxyPinchFrame(1.0, 1.0, 0, 0, 10, 0, 0).f === 2.5 && w0.galaxyPinchFrame(1.0, 1.0, 0, 0, 0.01, 0, 0).f === 0.5 &&
      w0.galaxyPinchFrame(0.8, 0.8, 0, 0, 10, 0, 0).f === 2.0);
    dom0.window.close();

    /* DOM 行为：桩造 clientWidth/clientHeight —— 隐藏预渲染（0）走回退落位，
       可见（390×336）后必须按真实尺寸重新 fit（嫌疑 a 的回归断言） */
    const sizeHolder = { w: 0, h: 0 };
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
    Object.defineProperty(win.HTMLElement.prototype, "clientWidth", { configurable: true, get() { return sizeHolder.w; } });
    Object.defineProperty(win.HTMLElement.prototype, "clientHeight", { configurable: true, get() { return sizeHolder.h; } });
    const readFitD = () => {
      const st = doc.getElementById("gstage"); if (!st) return null;
      const world = st.querySelector(".gworld");
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
      return { t: { x: +m[1], y: +m[2] }, s: +m[3], stageH: parseFloat(st.style.height),
               bb: { cx: (x0 + x1) / 2, cy: (y0 + y1) / 2, x0, x1, y0, y1 }, tf: world.style.transform };
    };
    await sleep(60);
    doc.querySelectorAll(".tabbtn")[2].click(); await sleep(60);
    const F0 = readFitD();
    ok("D 隐藏预渲染：测不到尺寸时回退落位也有完整 transform", !!F0, F0 && F0.tf);
    sizeHolder.w = 390; sizeHolder.h = 336;
    win.render(); await sleep(40);
    const F1 = readFitD();
    ok("D 可见后重新 fit：transform 按 390 宽画布重算（与回退落位不同）", !!F1 && !!F0 && F1.tf !== F0.tf, F1 && F1.tf);
    if (F1) {
      const mx = F1.t.x + F1.bb.cx * F1.s, my = F1.t.y + F1.bb.cy * F1.s;
      const ex0 = F1.t.x + F1.bb.x0 * F1.s, ex1 = F1.t.x + F1.bb.x1 * F1.s;
      const ey0 = F1.t.y + F1.bb.y0 * F1.s, ey1 = F1.t.y + F1.bb.y1 * F1.s;
      const vOk = Math.abs(my - 336 * 0.56) < 1.6 || Math.abs(ey1 - (336 - 8)) < 1.6;
      ok("D 可见后落位：中心在（195, 56%）且四边距 ≥8px 口径内",
        Math.abs(mx - 195) < 1.6 && vOk && ex0 >= 7 && ex1 <= 390 - 7 && ey0 >= 7 && ey1 <= 336 - 7,
        `c=${mx.toFixed(1)},${my.toFixed(1)} x:${ex0.toFixed(1)}~${ex1.toFixed(1)} y:${ey0.toFixed(1)}~${ey1.toFixed(1)}`);
    }
    /* 捏合冒烟：双指拉开 → 缩放放大并被限幅；重渲染保留缩放；松手后点击先吞后恢复 */
    const st = doc.getElementById("gstage");
    const s0 = F1 ? F1.s : 1;
    const pev = (type, id, x, y) => { const e = new win.MouseEvent(type, { bubbles: true, cancelable: true }); Object.defineProperties(e, { pointerId: { value: id }, clientX: { value: x }, clientY: { value: y } }); return e; };
    st.dispatchEvent(pev("pointerdown", 1, 150, 150));
    st.dispatchEvent(pev("pointerdown", 2, 190, 150));
    st.dispatchEvent(pev("pointermove", 2, 390, 150));
    const FP = readFitD();
    ok("D 捏合：双指拉开后缩放放大并停在限幅内（≤fit×2.5）", !!FP && FP.s > s0 * 2 && FP.s <= s0 * 2.5 + 0.01, FP && FP.tf);
    st.dispatchEvent(pev("pointerup", 2, 390, 150));
    st.dispatchEvent(pev("pointerup", 1, 150, 150));
    win.render(); await sleep(40);
    const FR = readFitD();
    ok("D 捏合后重渲染：缩放与平移保留（不被 fit 重置）", !!FR && !!FP && FR.tf === FP.tf, FR && FR.tf);
    const bub1 = bubs(doc)[0];
    bub1.click(); await sleep(30);
    ok("D 捏合松手后：紧随的气泡点击被吞（不弹信息条）", !doc.querySelector(".ginfo"));
    await sleep(160);
    bub1.click(); await sleep(40);
    ok("D 点击吞没过期后：气泡点击恢复（信息条出现）", !!doc.querySelector(".ginfo"));
    dom.window.close();
  }

  console.log(fails ? `\n${fails} FAIL` : "\nALL_GALAXY_TESTS_OK");
  process.exit(fails ? 1 : 0);
})().catch(e => { console.error("ERR", e); process.exit(1); });
