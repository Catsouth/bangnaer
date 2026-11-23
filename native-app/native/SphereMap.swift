import SwiftUI
import UIKit

// MARK: - sphere galaxy （绑哪儿第三批：关系图整页三维球形星系，替换上游双列连线图）
//
// The whole tab is one sphere: every account is a bubble on a Fibonacci sphere, drawn with a
// single Canvas (150+ bubbles never become views). Drag rotates (yaw/pitch accumulate, release
// keeps an exponentially decaying spin), pinch zooms, back-side bubbles fade/shrink and can't
// be tapped; a front bubble tap opens the account. Bubble rims are coloured by the group of
// the account's first bound identity: Email / SIM / 自定义 (login), grey when unbound.
// Adding identities lives on the top-right "+" and in the legend segments'
// long-press identity sheets — the sphere itself takes no long-press at all
// （第四轮细化）: a blank-area long-press fought the drag rotation past two
// rounds of arbitration guards, so the gesture was removed outright.

enum SphereGroup: Int, CaseIterable, Identifiable {
  case email, sim, custom, none
  var id: Int { rawValue }
  var name: String {
    switch self {
    case .email: return "Email"
    case .sim: return "SIM"
    case .custom: return "自定义"
    case .none: return "未绑定"
    }
  }
  var color: Color {
    switch self {
    case .email: return Color(hex: "#0a84ff")
    case .sim: return Color(hex: "#30d158")
    case .custom: return Color(hex: "#bf5af2")
    case .none: return Color(hex: "#8e8e93")
    }
  }
  static func of(_ i: Identity?) -> SphereGroup {
    guard let i else { return .none }
    switch i.type {
    case "email": return .email
    case "phone": return .sim
    default: return .custom   // login cards (any provider) form the 自定义 group
    }
  }
}

/// One focus state for the sphere (patch batch): an identity (the demo scripts set
/// it through store.demoFocus) or a whole legend group (chip tap). The canvas
/// dimming reads only this, so the two sources can never fight or drift apart.
enum SphereFocus: Equatable {
  case identity(String)
  case group(SphereGroup)
}

struct Vec3 { var x: Double, y: Double, z: Double }

struct SphereBubble {
  let account: Account
  let dir: Vec3
  let baseR: CGFloat
  let group: SphereGroup
}

enum SphereMath {
  /// Fibonacci sphere: near-uniform points, stable for a stable input order.
  static func directions(_ n: Int) -> [Vec3] {
    guard n > 0 else { return [] }
    let golden = Double.pi * (3 - sqrt(5))
    return (0..<n).map { i in
      let y = 1 - Double(i) / Double(max(n - 1, 1)) * 2
      let r = sqrt(max(0, 1 - y * y))
      let th = golden * Double(i)
      return Vec3(x: cos(th) * r, y: y, z: sin(th) * r)
    }
  }
  /// yaw around Y, then pitch around X. Viewer sits at +Z: z > 0 faces the user.
  static func rotate(_ p: Vec3, yaw: Double, pitch: Double) -> Vec3 {
    let cy = cos(yaw), sy = sin(yaw)
    let x1 = p.x * cy + p.z * sy, z1 = -p.x * sy + p.z * cy
    let cp = cos(pitch), sp = sin(pitch)
    return Vec3(x: x1, y: p.y * cp - z1 * sp, z: p.y * sp + z1 * cp)
  }
  static let focal = 3.2
  static func project(_ p: Vec3, yaw: Double, pitch: Double, radius R: Double) -> (x: Double, y: Double, z: Double, scale: Double) {
    let q = rotate(p, yaw: yaw, pitch: pitch)
    let s = focal / (focal - q.z)
    return (q.x * R * s, -q.y * R * s, q.z, s)
  }
}

struct SphereSpin {
  var yaw0: Double, pitch0: Double, vx: Double, vy: Double, start: Date
  static let decay = 1.8
  func rotation(at date: Date) -> (yaw: Double, pitch: Double) {
    let t = max(0, date.timeIntervalSince(start))
    let f = (1 - exp(-Self.decay * t)) / Self.decay
    return (yaw0 + vx * f, pitch0 + vy * f)
  }
  func speed(at date: Date) -> Double {
    let t = max(0, date.timeIntervalSince(start))
    return hypot(vx, vy) * exp(-Self.decay * t)
  }
}

struct MapView: View {
  @Environment(Store.self) var store
  // committed rotation / zoom
  @State private var yaw = 0.6
  @State private var pitch = -0.3
  @State private var zoom: CGFloat = 1
  // gesture bookkeeping
  @State private var dragBase: (yaw: Double, pitch: Double)? = nil
  @State private var dragOrigin: CGSize = .zero
  @State private var dragLast: (date: Date, t: CGSize)? = nil
  @State private var dragVel: CGSize = .zero
  @State private var pinchBase: CGFloat? = nil
  @State private var spin: SphereSpin? = nil
  // interaction feedback / menus
  @State private var focus: SphereFocus? = nil
  @State private var groupSheet: SphereGroup? = nil
  @State private var pendingAdd: String? = nil
  @State private var tapTick = 0
  @State private var pressTick = 0
  @State private var iconTick = 0
  @Namespace private var segNS

  static let pitchLimit = 1.25
  static let radPerPoint = 0.0055

  var bubbles: [SphereBubble] {
    let accs = store.index.byName
    let dirs = SphereMath.directions(accs.count)
    return accs.enumerated().map { k, a in
      let first = a.identityIds.lazy.compactMap { store.index.identityByID[$0] }.first
      let r = min(24, 13 + 4.5 * sqrt(Double(a.identityIds.count)))
      return SphereBubble(account: a, dir: dirs[k], baseR: r, group: SphereGroup.of(first))
    }
  }
  var groupCounts: [SphereGroup: Int] {
    var out: [SphereGroup: Int] = [:]
    for b in bubbles { out[b.group, default: 0] += 1 }
    return out
  }

  var body: some View {
    NavigationStack {
      GeometryReader { geo in
        ZStack {
          if store.data.accounts.isEmpty {
            Text(store.data.identities.isEmpty
                 ? "添加邮箱或手机号后，这里会把它们和网站排成一颗球。"
                 : "添加网站后，这里会把它们排成一颗球。")
              .foregroundStyle(.secondary).multilineTextAlignment(.center).padding(40)
              .frame(maxWidth: .infinity, maxHeight: .infinity)
          } else {
            // Gestures live on the sphere itself, NOT on the whole tab (patch batch):
            // the legend chips keep their own tap / long-press and never fight the
            // canvas for recognition — that fight was the long-press flicker.
            sphere(in: geo.size)
              .contentShape(Rectangle())
              .simultaneousGesture(dragGesture)
              .simultaneousGesture(pinchGesture)
              .onTapGesture { loc in tap(at: loc, in: geo.size) }
            legend.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
              .padding(.horizontal, 16).padding(.top, 10)
              .allowsHitTesting(true)
          }
        }
        .frame(width: geo.size.width, height: geo.size.height)
      }
      .navigationTitle("")
      .toolbar { TopButtons() }
      .toolbar(.hidden, for: .tabBar)
      .background(Glow().ignoresSafeArea())
      .sensoryFeedback(.selection, trigger: tapTick)
      .sensoryFeedback(.impact(weight: .light), trigger: pressTick)
    }
    .onAppear { iconTick &+= 1 }
    .task {
      // icons keep landing for a moment after the tab opens (favicons); one delayed
      // repaint picks them up — during a spin the canvas repaints anyway
      try? await Task.sleep(for: .seconds(1.2))
      iconTick &+= 1
    }
    .onChange(of: store.demoFocus) { _, f in
      withAnimation(Motion.smooth) { focus = (f == nil || f == "none") ? nil : .identity(f!) }
    }
    .sheet(item: $groupSheet, onDismiss: applyPendingAdd) { g in
      GroupIdentitiesSheet(group: g,
                           onPick: { i in
                             withAnimation(Motion.smooth) { focus = .identity(i.id) }
                             groupSheet = nil
                           },
                           onAdd: { t in
                             pendingAdd = t
                             groupSheet = nil
                           })
        .environment(store)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
  }

  // MARK: canvas

  @ViewBuilder func sphere(in size: CGSize) -> some View {
    let specs = bubbles
    if let spin {
      TimelineView(.animation) { ctx in
        let ang = spin.rotation(at: ctx.date)
        canvas(specs: specs, size: size, yaw: ang.yaw, pitch: clampPitch(ang.pitch))
      }
      .task(id: spin.start) {
        // the ViewBuilder above can't run side effects, so spin-end detection
        // lives here: poll the captured spin's decay, then fold it into yaw/pitch
        let mine = spin
        while !Task.isCancelled {
          if mine.speed(at: Date()) < 0.06 {
            if self.spin?.start == mine.start { commitSpin() }
            return
          }
          try? await Task.sleep(for: .milliseconds(60))
        }
      }
    } else {
      canvas(specs: specs, size: size, yaw: yaw, pitch: pitch)
    }
  }

  func canvas(specs: [SphereBubble], size: CGSize, yaw: Double, pitch: Double) -> some View {
    let _ = iconTick
    return Canvas { ctx, _ in
      let center = CGPoint(x: size.width / 2, y: size.height / 2 - 24)
      let R = Double(min(size.width, size.height)) * 0.40 * Double(zoom)
      // faint sphere body so the ball reads as one object
      let disc = CGRect(x: center.x - CGFloat(R) * 1.05, y: center.y - CGFloat(R) * 1.05, width: CGFloat(R) * 2.1, height: CGFloat(R) * 2.1)
      ctx.fill(Path(ellipseIn: disc), with: .color(.primary.opacity(0.04)))
      ctx.stroke(Path(ellipseIn: disc), with: .color(.primary.opacity(0.07)), lineWidth: 1)

      struct P { let b: SphereBubble; let c: CGPoint; let r: CGFloat; let z: Double }
      // Pinch out shrinks the icons with the ball; pinch in never blows them past
      // their normal size — positions still project with the real zoom (patch batch).
      let iconScale = min(1.0, Double(zoom))
      var ps: [P] = specs.map { b in
        let p = SphereMath.project(b.dir, yaw: yaw, pitch: pitch, radius: R)
        let t = (p.z + 1) / 2
        let r = b.baseR * CGFloat(p.scale) * CGFloat(0.7 + 0.3 * t) * CGFloat(iconScale)
        return P(b: b, c: CGPoint(x: center.x + CGFloat(p.x), y: center.y + CGFloat(p.y)), r: r, z: p.z)
      }
      ps.sort { $0.z < $1.z }   // back bubbles first
      // Identity focus （第五轮）: only the bubbles bound to the focused
      // identity exist at all — the rest are not drawn (and tap() hit-tests
      // the same filtered set), so the ball shows exactly that identity's
      // services, threads included. Group focus keeps the dim-everything-else
      // treatment below; tapping empty sphere clears the focus either way.
      if let f = focus, case .identity(let fid) = f {
        ps = ps.filter { $0.b.account.identityIds.contains(fid) }
      }
      // Focus threads （第三轮细化）: an identity focus connects the centre to
      // every bubble bound to that identity, in the identity's own colour,
      // under the bubbles (drawn first, and the canvas never hit-tests anyway).
      // Alpha follows the same depth curve as the bubbles, so back-side
      // threads fade out with their bubbles. Group focus draws none — a whole
      // group threaded at once would be a thicket, not a highlight.
      if let f = focus, case .identity(let fid) = f, let who = store.identity(fid) {
        let thread = Color(hex: who.color)
        for item in ps where item.b.account.identityIds.contains(fid) {
          let t = (item.z + 1) / 2
          let a = (0.10 + 0.90 * pow(t, 1.4)) * 0.55
          var path = Path()
          path.move(to: center)
          path.addLine(to: item.c)
          ctx.stroke(path, with: .color(thread.opacity(a)), lineWidth: 1)
        }
      }
      for item in ps {
        let t = (item.z + 1) / 2
        var alpha = 0.10 + 0.90 * pow(t, 1.4)
        let dimmed: Bool = switch focus {
        case .identity: false   // unbound bubbles were filtered out above
        case .group(let g): item.b.group != g
        case nil: false
        }
        if dimmed { alpha *= 0.22 }
        let rect = CGRect(x: item.c.x - item.r, y: item.c.y - item.r, width: item.r * 2, height: item.r * 2)
        // body: the service icon when decoded, else a brand-colour letter tile
        let key = IconStore.shared.key(name: item.b.account.name, domain: item.b.account.domain, icon: item.b.account.icon)
        if let entry = IconStore.shared.cached(key) {
          if entry.favicon { ctx.fill(Path(ellipseIn: rect), with: .color(.white.opacity(alpha))) }
          var c = ctx
          c.clip(to: Path(ellipseIn: rect))
          let inset = entry.favicon ? item.r * 0.28 : 0
          c.draw(Image(uiImage: entry.image), in: rect.insetBy(dx: inset, dy: inset))
        } else {
          let brand = brandColor(name: item.b.account.name, domain: item.b.account.domain)
          ctx.fill(Path(ellipseIn: rect), with: .color(brand.opacity((0.30 + 0.70 * t) * alpha)))
          let letter = String(item.b.account.name.trimmingCharacters(in: .whitespaces).prefix(1)).uppercased()
          ctx.draw(Text(letter).font(.system(size: item.r * 0.92, weight: .semibold, design: .rounded)).foregroundStyle(.white.opacity(alpha)),
                   at: item.c, anchor: .center)
        }
        ctx.stroke(Path(ellipseIn: rect), with: .color(item.b.group.color.opacity(alpha)), lineWidth: 1.5)
        // name under the bigger front bubbles
        if item.r >= 16 && item.z > 0.1 {
          ctx.draw(Text(item.b.account.name).font(.system(size: 9, weight: .medium)).foregroundStyle(.primary.opacity(alpha)),
                   at: CGPoint(x: item.c.x, y: item.c.y + item.r + 8), anchor: .center)
        }
      }
    }
    .frame(width: size.width, height: size.height)
  }

  // MARK: gestures

  var dragGesture: some Gesture {
    DragGesture(minimumDistance: 4)
      .onChanged { v in
        if dragBase == nil {
          commitSpin()
          dragBase = (yaw, pitch)
          // The drag only starts past its minimum distance; absorbing that
          // first stretch keeps the ball from jumping when rotation kicks in
          // (patch batch).
          dragOrigin = v.translation
          dragVel = .zero
          dragLast = nil
        }
        let b = dragBase!
        let t = CGSize(width: v.translation.width - dragOrigin.width, height: v.translation.height - dragOrigin.height)
        yaw = b.yaw + Double(t.width) * Self.radPerPoint
        pitch = clampPitch(b.pitch + Double(t.height) * Self.radPerPoint)
        if let last = dragLast {
          let dt = v.time.timeIntervalSince(last.date)
          if dt > 0.016 {
            dragVel = CGSize(width: (t.width - last.t.width) / CGFloat(dt),
                             height: (t.height - last.t.height) / CGFloat(dt))
          }
        }
        dragLast = (v.time, t)
      }
      .onEnded { _ in
        dragBase = nil
        dragLast = nil
        let vx = Double(dragVel.width) * Self.radPerPoint
        let vy = Double(dragVel.height) * Self.radPerPoint
        if hypot(vx, vy) > 0.25 {
          // no haptic on spin start （第五轮）: sliding the ball stays silent;
          // pressTick now belongs only to the segment long-press.
          spin = SphereSpin(yaw0: yaw, pitch0: pitch, vx: min(max(vx, -9), 9), vy: min(max(vy, -9), 9), start: Date())
        }
      }
  }

  var pinchGesture: some Gesture {
    MagnificationGesture()
      .onChanged { s in
        if pinchBase == nil { commitSpin(); pinchBase = zoom }
        zoom = min(2.4, max(0.55, (pinchBase ?? 1) * s))
      }
      .onEnded { _ in
        pinchBase = nil
      }
  }

  func tap(at loc: CGPoint, in size: CGSize) {
    let ang: (yaw: Double, pitch: Double)
    if let spin { ang = spin.rotation(at: Date()) } else { ang = (yaw, pitch) }
    let center = CGPoint(x: size.width / 2, y: size.height / 2 - 24)
    let R = Double(min(size.width, size.height)) * 0.40 * Double(zoom)
    var best: (id: String, z: Double)? = nil
    for b in bubbles {
      // identity focus （第五轮）: hidden bubbles are not tappable either
      if let f = focus, case .identity(let fid) = f, !b.account.identityIds.contains(fid) { continue }
      let p = SphereMath.project(b.dir, yaw: ang.yaw, pitch: clampPitch(ang.pitch), radius: R)
      guard p.z > -0.05 else { continue }   // back side can't be tapped
      let t = (p.z + 1) / 2
      // same radius the canvas draws with (incl. the min(1, zoom) icon cap), + slack
      let r = Double(b.baseR) * p.scale * (0.7 + 0.3 * t) * min(1.0, Double(zoom)) + 6
      let d = hypot(Double(loc.x - center.x) - p.x, Double(loc.y - center.y) - p.y)
      if d <= r && (best == nil || p.z > best!.z) { best = (b.account.id, p.z) }
    }
    if let best {
      tapTick &+= 1
      store.route = .account(best.id)
    } else if focus != nil {
      // tapping empty sphere clears a chip / demo focus (patch batch)
      withAnimation(Motion.smooth) { focus = nil }
      tapTick &+= 1
    }
  }

  func commitSpin() {
    guard let s = spin else { return }
    let ang = s.rotation(at: Date())
    yaw = ang.yaw
    pitch = clampPitch(ang.pitch)
    spin = nil
  }
  func clampPitch(_ p: Double) -> Double { min(Self.pitchLimit, max(-Self.pitchLimit, p)) }

  // MARK: legend

  var visibleGroups: [SphereGroup] {
    SphereGroup.allCases.filter { $0 != .none || (groupCounts[.none] ?? 0) > 0 }
  }
  func groupIcon(_ g: SphereGroup) -> String {
    switch g {
    case .email: return "envelope"
    case .sim: return "simcard"
    case .custom: return "person.badge.key"
    case .none: return "circle.dashed"
    }
  }

  /// The legend is the wallet page's segmented control now （第二轮细化）: equal-width
  /// segments (icon + name + count) in one glass capsule, the focused group filled
  /// with its group colour, the thumb sliding via matchedGeometryEffect.
  var legend: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(spacing: 0) {
        ForEach(visibleGroups, id: \.rawValue) { g in segment(g) }
      }
      .padding(3)
      .background(.glass, in: Capsule())
      .animation(Motion.smooth, value: focus)
      Text("拖动旋转 · 捏合缩放 · 长按分段查看身份").font(.system(size: 11)).foregroundStyle(.secondary)
        .padding(.leading, 6)
    }
  }

  /// A segment is still a focus toggle: tap it and the sphere keeps only that
  /// group lit (the SphereFocus.group dimming); tap it again — or tap empty
  /// sphere — to clear. Long-press opens the group's identity sheet instead
  /// （第三轮细化）: the group's existing cards plus its trimmed add entries
  /// (see GroupIdentitiesSheet). The tap / long-press pair hangs on the label
  /// view itself, not a Button — a Button fires its action on touch-up even
  /// when a long-press recogniser completes, which would toggle the focus
  /// behind the sheet.
  func segment(_ g: SphereGroup) -> some View {
    let on = focus == .group(g)
    return HStack(spacing: 5) {
      Image(systemName: groupIcon(g)).font(.system(size: 13, weight: .semibold))
      Text(g.name).font(.system(size: 13, weight: .semibold)).lineLimit(1)
      Text("\(groupCounts[g] ?? 0)").font(.system(size: 12, weight: .medium)).foregroundStyle(on ? .primary : .secondary)
    }
    .frame(maxWidth: .infinity).frame(height: 34)
    .foregroundStyle(on ? .primary : .secondary)
    .background {
      if on {
        Capsule().fill(g.color.opacity(0.30))
          .overlay(Capsule().strokeBorder(g.color.opacity(0.55), lineWidth: 0.7))
          .matchedGeometryEffect(id: "segThumb", in: segNS)
      }
    }
    .contentShape(Rectangle())
    .onTapGesture {
      withAnimation(Motion.smooth) { focus = on ? nil : .group(g) }
      tapTick &+= 1
    }
    .onLongPressGesture(minimumDuration: 0.45) {
      groupSheet = g
      pressTick &+= 1
    }
    .accessibilityElement(children: .combine)
    .accessibilityLabel("\(g.name) \(groupCounts[g] ?? 0)")
    .accessibilityAddTraits(on ? [.isButton, .isSelected] : [.isButton])
  }

  /// The group sheet's add entries apply their route only once the sheet has
  /// fully dismissed — RootView's sheet can't stack over this one.
  func applyPendingAdd() {
    guard let t = pendingAdd else { return }
    pendingAdd = nil
    store.route = .newIdentity(t)
  }
}

/// Add entries per group, trimmed （第二轮细化）: Email offers only 添加邮箱，
/// SIM only 添加手机号， 自定义 (and 未绑定） keep all three. Shared by the
/// group sheet.
struct GroupAddOption: Identifiable {
  let type: String, title: String, icon: String
  var id: String { type }
}
func groupAddOptions(_ g: SphereGroup) -> [GroupAddOption] {
  var out: [GroupAddOption] = []
  if g == .email || g == .custom || g == .none { out.append(GroupAddOption(type: "email", title: "添加邮箱", icon: "envelope")) }
  if g == .sim || g == .custom || g == .none { out.append(GroupAddOption(type: "phone", title: "添加手机号", icon: "simcard")) }
  if g == .custom || g == .none { out.append(GroupAddOption(type: "login", title: "添加登录账号", icon: "person.badge.key")) }
  return out
}

/// Second-level sheet behind a legend segment's long-press （第三轮细化）: the
/// group's existing identity cards — label (value when unlabelled), value,
/// bound-count badge, each in its own skin like the original app's map listed
/// them down its left column. Tapping a card focuses the sphere on that
/// identity (threads and all) and closes the sheet; the group's add entries
/// stay in their own section below.
struct GroupIdentitiesSheet: View {
  @Environment(Store.self) var store
  @Environment(\.dismiss) var dismiss
  let group: SphereGroup
  let onPick: (Identity) -> Void
  let onAdd: (String) -> Void

  var identities: [Identity] { store.data.identities.filter { SphereGroup.of($0) == group } }

  var body: some View {
    NavigationStack {
      List {
        if identities.isEmpty {
          Section {
            Text("这一组还没有身份卡").foregroundStyle(.secondary)
          }
        } else {
          Section {
            ForEach(identities) { i in
              Button { onPick(i) } label: { row(i) }
                .buttonStyle(.plain)
            }
          }
        }
        Section {
          ForEach(groupAddOptions(group)) { opt in
            Button { onAdd(opt.type) } label: { Label(opt.title, systemImage: opt.icon) }
          }
        }
      }
      .navigationTitle(group.name).navigationBarTitleDisplayMode(.inline)
      .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { dismiss() } label: { Image(systemName: "xmark") } } }
    }
  }

  func row(_ i: Identity) -> some View {
    HStack(spacing: 12) {
      IdentityGlyph(identity: i, size: 15)
        .foregroundStyle(.white)
        .frame(width: 42, height: 42)
        .background(skinGradient(i.color), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
      VStack(alignment: .leading, spacing: 2) {
        Text(store.title(i)).font(.system(size: 15, weight: .semibold)).lineLimit(1)
        Text(i.label.isEmpty ? i.kindName : i.value).font(.system(size: 13)).foregroundStyle(.secondary).lineLimit(1)
      }
      Spacer(minLength: 8)
      Text("\(store.accounts(of: i.id).count)")
        .font(.system(size: 12, weight: .bold))
        .padding(.horizontal, 8).padding(.vertical, 3)
        .background(Color(hex: i.color).opacity(0.16), in: Capsule())
        .foregroundStyle(Color(hex: i.color))
    }
    .contentShape(Rectangle())
  }
}
