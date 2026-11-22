import SwiftUI
import UIKit

/// 原生星系图原型：验证系统手势的手感，不接业务。
///
/// 变换模型：screen = 视图中心 + T + world * S，其中 S = fitScale * zoom。
/// - DragGesture 平移：手指位移直接进 T（增量公式，松手不跳），松手带一点
///   predictedEndTranslation 惯性衰减。
/// - MagnificationGesture 捏合：以当前手指位置为锚点做标准锚定缩放——
///   取锚点下的世界点 w=(a-T)/S，缩放后令 T' = a - w*S'，锚点下的内容不动。
///   锚点取 DragGesture 实时上报的手指位置（两手势 simultaneous 并行）。
/// - 捏合中单指拖动只刷新锚点、不平移，松开一指后剩余手指不续拖，防跳变。
/// - 点选/双击复位在 DragGesture.onEnded 里手工判定（位移 <8pt 视为点按，
///   气泡位置全是算出来的，命中测试就是距离比较），不与系统手势抢认。
struct ProtoGalaxyView: View {
    let identityName: String
    let identityMark: String
    let services: [ProtoService]
    var onFeedback: (String) -> Void

    @State private var viewSize: CGSize = .zero
    @State private var zoom: CGFloat = 1            // 相对 fitScale 的倍率
    @State private var translation: CGSize = .zero  // 世界中心相对视图中心的偏移
    @State private var selectedID: Int? = nil

    // 手势记账
    @State private var anchorPrev: CGPoint? = nil   // 上一帧锚点（视图中心相对坐标）
    @State private var lastMag: CGFloat? = nil      // 上一帧捏合倍率（增量换算用）
    @State private var dragMoved: CGFloat = 0
    @State private var dragBuzzed = false
    @State private var pinchBuzzed = false
    @State private var pinchActive = false
    @State private var lastTapTime: Date = .distantPast
    @State private var lastTapPoint: CGPoint = .zero

    private let spacing: CGFloat = 56       // 蜂窝环距（世界单位）
    private let bubbleWorldD: CGFloat = 46  // 气泡直径（世界单位）
    private let coreWorldD: CGFloat = 96    // 核心圆直径（世界单位）

    // MARK: - 布局与变换（纯计算，手势与渲染共用同一套，保证命中测试对得上）

    /// 第 index 个气泡的世界坐标：六边形环形排布（第 r 环 6r 个，沿六条边插值）
    private func worldPosition(index: Int) -> CGPoint {
        var rest = index
        var ring = 1
        while rest >= 6 * ring { rest -= 6 * ring; ring += 1 }
        let side = rest / ring
        let step = rest % ring
        let r = CGFloat(ring) * spacing
        let a0 = Double(side) * Double.pi / 3 - Double.pi / 2
        let a1 = Double(side + 1) * Double.pi / 3 - Double.pi / 2
        let x0 = CGFloat(cos(a0)) * r, y0 = CGFloat(sin(a0)) * r
        let x1 = CGFloat(cos(a1)) * r, y1 = CGFloat(sin(a1)) * r
        let t = CGFloat(step) / CGFloat(ring)
        return CGPoint(x: x0 + (x1 - x0) * t, y: y0 + (y1 - y0) * t)
    }

    private func worldRadius() -> CGFloat {
        let n = services.count
        if n == 0 { return coreWorldD / 2 }
        var ring = 1
        var rest = n
        while rest > 6 * ring { rest -= 6 * ring; ring += 1 }
        return CGFloat(ring) * spacing + bubbleWorldD / 2
    }

    private func fitScale(size: CGSize) -> CGFloat {
        guard size.width > 0, size.height > 0 else { return 1 }
        let avail = min(size.width, size.height) / 2 - 6
        return min(avail / worldRadius(), 1.2)
    }

    private func currentScale(size: CGSize) -> CGFloat { fitScale(size: size) * zoom }

    private func screenPos(_ world: CGPoint, size: CGSize) -> CGPoint {
        let s = currentScale(size: size)
        return CGPoint(x: size.width / 2 + translation.width + world.x * s,
                       y: size.height / 2 + translation.height + world.y * s)
    }

    private func bubbleScreenD(size: CGSize) -> CGFloat {
        min(max(bubbleWorldD * currentScale(size: size), 18), 72)
    }

    private func coreScreenD(size: CGSize) -> CGFloat {
        min(max(coreWorldD * currentScale(size: size), 40), 110)
    }

    /// 锚定变换：把世界点（当前位于 prevAnchor 处）搬到新锚点 anchor 下，
    /// 并把缩放换到 sNew。纯平移时 sNew==现缩放，公式退化为 T += 手指位移。
    private func applyTransform(anchor: CGPoint, newScale sNewRaw: CGFloat) {
        let size = viewSize
        guard size.width > 0 else { return }
        let fit = fitScale(size: size)
        let sOld = fit * zoom
        guard sOld > 0 else { return }
        let sNew = min(max(sNewRaw, fit * 0.5), fit * 2.5)
        let prev = anchorPrev ?? anchor
        let wx = (prev.x - translation.width) / sOld
        let wy = (prev.y - translation.height) / sOld
        var tx = anchor.x - wx * sNew
        var ty = anchor.y - wy * sNew
        // 松限幅：只防整群拖没（世界中心可离开画布，但不许超过世界范围+半屏）
        let reach = worldRadius() * sNew + min(size.width, size.height) / 2
        tx = min(max(tx, -reach), reach)
        ty = min(max(ty, -reach), reach)
        translation = CGSize(width: tx, height: ty)
        zoom = sNew / fit
        anchorPrev = anchor
    }

    private func clampedTranslation(_ t: CGSize, size: CGSize) -> CGSize {
        let reach = worldRadius() * currentScale(size: size) + min(size.width, size.height) / 2
        return CGSize(width: min(max(t.width, -reach), reach),
                      height: min(max(t.height, -reach), reach))
    }

    // MARK: - 手势

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { v in
                let a = CGPoint(x: v.location.x - viewSize.width / 2,
                                y: v.location.y - viewSize.height / 2)
                if anchorPrev == nil { anchorPrev = a }
                dragMoved = max(dragMoved, hypot(v.translation.width, v.translation.height))
                if !dragBuzzed && dragMoved > 8 {
                    dragBuzzed = true
                    ProtoHaptics.light()   // 手势被识别：震一次
                }
                if pinchActive {
                    anchorPrev = a         // 捏合中只刷新锚点，平移交给缩放公式
                } else {
                    applyTransform(anchor: a, newScale: currentScale(size: viewSize))
                }
            }
            .onEnded { v in
                let wasPinch = pinchActive
                anchorPrev = nil
                dragBuzzed = false
                pinchActive = false
                if wasPinch {
                    dragMoved = 0
                    return                 // 捏合收尾：不点选、不惯性，防跳变
                }
                if dragMoved <= 8 {
                    handleTap(at: v.location)
                } else {
                    // 惯性：取预测终点多出的那段，打三折后缓出，并限幅
                    let extra = CGSize(width: v.predictedEndTranslation.width - v.translation.width,
                                       height: v.predictedEndTranslation.height - v.translation.height)
                    if hypot(extra.width, extra.height) > 12 {
                        let target = clampedTranslation(
                            CGSize(width: translation.width + extra.width * 0.3,
                                   height: translation.height + extra.height * 0.3),
                            size: viewSize)
                        withAnimation(.easeOut(duration: 0.35)) { translation = target }
                    }
                }
                dragMoved = 0
            }
    }

    private var pinchGesture: some Gesture {
        MagnificationGesture()
            .onChanged { m in
                if lastMag == nil {
                    lastMag = 1
                    pinchActive = true
                }
                if !pinchBuzzed && (m > 1.03 || m < 0.97) {
                    pinchBuzzed = true
                    ProtoHaptics.light()   // 捏合成立：震一次
                }
                let r = m / (lastMag ?? 1)
                lastMag = m
                let a = anchorPrev ?? .zero
                applyTransform(anchor: a, newScale: currentScale(size: viewSize) * r)
            }
            .onEnded { _ in
                lastMag = nil
                pinchBuzzed = false
            }
    }

    /// 点按处理：300ms 内同位置第二下 = 双击复位；否则命中测试选气泡
    private func handleTap(at point: CGPoint) {
        let now = Date()
        if now.timeIntervalSince(lastTapTime) < 0.3,
           hypot(point.x - lastTapPoint.x, point.y - lastTapPoint.y) < 30 {
            lastTapTime = .distantPast
            selectedID = nil
            withAnimation(.easeInOut(duration: 0.3)) {
                zoom = 1
                translation = .zero
            }
            onFeedback("星系图已复位")
            return
        }
        lastTapTime = now
        lastTapPoint = point
        let size = viewSize
        let d = bubbleScreenD(size: size)
        for (idx, svc) in services.enumerated().reversed() {
            let c = screenPos(worldPosition(index: idx), size: size)
            if hypot(point.x - c.x, point.y - c.y) <= d / 2 + 4 {
                selectedID = svc.id
                ProtoHaptics.light()
                onFeedback("已选中 \(svc.name)（\(svc.domain)）")
                return
            }
        }
        let cc = screenPos(.zero, size: size)
        if hypot(point.x - cc.x, point.y - cc.y) <= coreScreenD(size: size) / 2 {
            selectedID = nil
            onFeedback("核心「\(identityName)」：共 \(services.count) 个服务")
            return
        }
        selectedID = nil
    }

    // MARK: - 视图

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // 整块区域（含空白黑区）都是手势面
                Color(red: 0.02, green: 0.02, blue: 0.03)

                // 连线
                Canvas { ctx, size in
                    let core = screenPos(.zero, size: size)
                    for (idx, _) in services.enumerated() {
                        let p = screenPos(worldPosition(index: idx), size: size)
                        var path = Path()
                        path.move(to: core)
                        path.addLine(to: p)
                        ctx.stroke(path, with: .color(Color.blue.opacity(0.45)), lineWidth: 1.2)
                    }
                }

                // 气泡
                ForEach(Array(services.enumerated()), id: \.element.id) { idx, svc in
                    bubble(svc, center: screenPos(worldPosition(index: idx), size: geo.size),
                           size: geo.size)
                }

                // 核心圆
                coreView(center: screenPos(.zero, size: geo.size), size: geo.size)

                // 左下角操作提示（不挡手势：自身无手势，事件穿透到容器）
                VStack {
                    Spacer()
                    HStack {
                        Text("拖动平移 · 双指捏合缩放 · 双击复位 · 点气泡选中")
                            .font(.caption2)
                            .foregroundColor(.gray)
                        Spacer()
                    }
                    .padding(.leading, 10)
                    .padding(.bottom, 6)
                }
            }
            .contentShape(Rectangle())
            .gesture(dragGesture)
            .simultaneousGesture(pinchGesture)
            .onAppear { viewSize = geo.size }
            .onChange(of: geo.size) { viewSize = $0 }
        }
    }

    @ViewBuilder
    private func bubble(_ svc: ProtoService, center: CGPoint, size: CGSize) -> some View {
        let d = bubbleScreenD(size: size)
        let selected = selectedID == svc.id
        ZStack {
            Circle()
                .fill(Color(white: 0.12))
            Circle()
                .stroke(selected ? Color.blue : Color.white.opacity(0.25),
                        lineWidth: selected ? 2.5 : 1)
            Text(svc.initial)
                .font(.system(size: d * 0.42, weight: .semibold))
                .foregroundColor(svc.tint)
        }
        .frame(width: d, height: d)
        .position(center)

        if d >= 34 {
            Text(svc.name)
                .font(.system(size: 9))
                .foregroundColor(.gray)
                .position(x: center.x, y: center.y + d / 2 + 7)
        }
    }

    @ViewBuilder
    private func coreView(center: CGPoint, size: CGSize) -> some View {
        let d = coreScreenD(size: size)
        ZStack {
            Circle()
                .fill(LinearGradient(colors: [Color.blue, Color.purple],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
            Circle()
                .stroke(Color.white.opacity(0.35), lineWidth: 1)
            VStack(spacing: 1) {
                Text(identityMark)
                    .font(.system(size: d * 0.3, weight: .bold))
                    .foregroundColor(.white)
                Text("\(services.count)")
                    .font(.system(size: d * 0.16))
                    .foregroundColor(.white.opacity(0.85))
            }
        }
        .frame(width: d, height: d)
        .position(center)
    }
}
