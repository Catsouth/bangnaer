import SwiftUI

@main
struct AtlasApp: App {
  @State private var store = Store()
  @StateObject private var sync = Sync()
  @StateObject private var dav = WebDAV()
  @State private var lock = AppLock()
  @Environment(\.scenePhase) private var phase

  var body: some Scene {
    WindowGroup {
      ZStack {
        RootView()
          .environment(store)
          .environmentObject(sync)
          .environmentObject(dav)
          .environment(lock)
          .onAppear {
            ThemeFX.apply(store.theme)
            sync.store = store
            dav.store = store
            let s = sync
            let d = dav
            store.onSaved = { [weak s, weak d] in s?.schedule(); d?.schedule() }
            if store.data.demo == true && UserDefaults.standard.string(forKey: "atlasDemo") == nil {
              store.show("这是示例数据", action: "清空") {
                store.mutate(nil) { s in s.identities = []; s.accounts = [] }
                store.setKind(store.kind)
              }
            }
            Task { await sync.run() }
          }
        // screen lock covers everything (incl. sheets: locking also drops any open route)
        if lock.locked {
          LockView()
            .environment(lock)
            .transition(.opacity)
            .zIndex(1)
        }
      }
      .onChange(of: phase) { _, p in
        switch p {
        case .background:
          lock.noteBackground()
        case .active:
          lock.noteForeground()
          if lock.locked { store.route = nil }
          Task { await sync.run() }
        default:
          break
        }
      }
      // 「用绑哪儿打开」: backup files handed over from Files / share sheet (the system
      // file picker has repeatedly refused valid JSON on device, so this is the
      // reliable way in). Only backup import — smart-import formats are not handled here.
      .onOpenURL { url in openBackup(url) }
    }
  }

  /// Reads a document handed to the app and feeds it to the same import the settings
  /// page uses. In-place documents are security-scoped: start/stop around the read,
  /// and still try the read when access wasn't granted (copied-to-Inbox URLs need none).
  /// Feedback is the existing toasts: importBackup announces the counts on success,
  /// anything unreadable or not a backup gets 「这不是绑哪儿的备份文件」.
  func openBackup(_ url: URL) {
    guard url.isFileURL else { return }
    let scoped = url.startAccessingSecurityScopedResource()
    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
    guard let d = try? Data(contentsOf: url), store.importBackup(d) else {
      store.show("这不是绑哪儿的备份文件")
      return
    }
  }
}

struct RootView: View {
  @Environment(Store.self) var store
  @Environment(\.colorScheme) private var scheme
  @State private var tab = 0
  @State private var dir: CGFloat = 1
  @Namespace private var barNS

  var body: some View {
    TabView(selection: Binding(get: { tab }, set: { t in dir = t >= tab ? 1 : -1; tab = t })) {
      WalletView().tabEnter(0, tab: tab, dir: dir).tag(0).tabItem { Label("卡包", systemImage: "rectangle.stack.fill") }
      SitesView().tabEnter(1, tab: tab, dir: dir).tag(1).tabItem { Label("全部 App", systemImage: "square.grid.2x2.fill") }
      MapView().tabEnter(2, tab: tab, dir: dir).tag(2).tabItem { Label("关系图", systemImage: "point.3.connected.trianglepath.dotted") }
      SettingsSheet(embedded: true).tabEnter(3, tab: tab, dir: dir).tag(3).tabItem { Label("设置", systemImage: "gearshape.fill") }
    }
    // The system tab bar is hidden per tab, on each NavigationStack's root content
    // (.toolbar(.hidden, for: .tabBar) there — on the TabView itself it does nothing,
    // the bar bled through the glass in simulator shots). The floating glass bar
    // below replaces it: liquid-glass capsule with the four tabs + a separate round
    // search button (iOS 27 style, approximated with ultraThinMaterial + highlight
    // stroke + soft shadow on the iOS 17 target).
    .overlay(alignment: .bottom) { bottomBar }
    .environment(\.selectedTab, tab)
    .sensoryFeedback(.selection, trigger: tab)
    .onChange(of: store.theme) { _, t in ThemeFX.apply(t) }
    .sheet(item: Binding(get: { store.route }, set: { r in store.route = r })) { r in sheet(r) }
    .overlay(alignment: .top) { ToastView() }
    .onAppear {
      // launch arguments used by the CI preview screenshots
      let d = UserDefaults.standard
      tab = d.integer(forKey: "atlasTab")
      switch d.string(forKey: "atlasRoute") {
      case "picker": store.route = .picker(store.active?.id)
      case "identity": if let i = store.active { store.route = .identity(i.id) }
      case "settings": tab = 3
      case "new": store.route = .newIdentity("email")
      default: break
      }
      if let demo = d.string(forKey: "atlasDemo") { Task { await runDemo(demo) } }
    }
  }

  // Scripted walkthroughs used to record the promo clips in CI (-atlasDemo <name>).
  func go(_ t: Int) { dir = t >= tab ? 1 : -1; tab = t }
  func wait(_ s: Double) async { try? await Task.sleep(for: .seconds(s)) }
  func swipe(_ id: String?) { withAnimation(.spring(duration: 0.55, bounce: 0)) { store.activeID = id } }
  @MainActor func runDemo(_ name: String) async {
    await wait(3.2)
    switch name {
    case "wallet":
      for id in store.deck.map(\.id).dropFirst() { swipe(id); await wait(1.5) }
      await wait(0.4); swipe(store.deck.first?.id)
    case "kind":
      withAnimation(Motion.smooth) { store.setKind("phone") }
      await wait(1.6)
      if store.deck.count > 1 { swipe(store.deck[1].id); await wait(1.5) }
      withAnimation(Motion.smooth) { store.setKind("email") }
    case "map":
      go(2); await wait(2.6)
      if let a = store.data.identities.first?.id { store.demoFocus = a; await wait(1.6) }
      if store.data.identities.count > 2 { store.demoFocus = store.data.identities[2].id; await wait(1.6) }
      store.demoFocus = "none"
    case "theme":
      ThemeFX.set("light", store: store); await wait(1.8)
      ThemeFX.set("dark", store: store); await wait(1.8)
      go(2); await wait(1.4)
      ThemeFX.set("light", store: store)
    case "tabs":
      go(1); await wait(1.4); go(2); await wait(2.2); go(0)
    case "picker":
      store.route = .picker(store.active?.id)
    default: break
    }
  }

  func sheet(_ r: Route) -> some View {
    SheetHost(route: r)
      .environment(store)
      .presentationDragIndicator(.visible)
      .presentationCornerRadius(34)
  }

  // MARK: floating bottom bar

  var bottomBar: some View {
    HStack(alignment: .center, spacing: 10) {
      barCapsule
      Spacer(minLength: 0)
      barCircle("magnifyingglass", label: "搜索") { store.route = .search }
    }
    .padding(.horizontal, 16)
    .padding(.bottom, 8)
  }

  // Four tabs in one capsule （卡包 / 全部 App / 关系图 / 设置）; the glass pill under
  // the selected tab slides via matchedGeometryEffect, and one drag gesture drives
  // the whole capsule: a tap is a drag that never moved, sliding a finger across
  // moves the selection segment by segment (RootView's sensoryFeedback on `tab`
  // gives the light haptic per hop).
  var barCapsule: some View {
    HStack(spacing: 2) {
      barTab(0, "卡包", "rectangle.stack.fill")
      barTab(1, "全部 App", "square.grid.2x2.fill")
      barTab(2, "关系图", "point.3.connected.trianglepath.dotted")
      barTab(3, "设置", "gearshape.fill")
    }
    .padding(4)
    .background { glassCapsule }
    .contentShape(Capsule())
    .animation(Motion.snappy, value: tab)
    .gesture(barDrag)
  }

  var barDrag: some Gesture {
    DragGesture(minimumDistance: 0, coordinateSpace: .local)
      .onChanged { v in selectBar(at: v.location.x) }
      .onEnded { v in selectBar(at: v.location.x) }
  }
  func selectBar(at x: CGFloat) {
    // capsule geometry: 4pt padding, then 64pt cells with 2pt gaps (66pt step)
    let t = min(3, max(0, Int((x - 4) / 66)))
    if t != tab { go(t) }
  }

  // Liquid glass （第三轮细化）: iOS 17 has no system glass API, so the bar is
  // layered by hand — the material pass runs at reduced opacity so page
  // content visibly drifts underneath while scrolling, a vertical sheen
  // fakes light falling through the slab (bright at the top, a whisper of
  // shade at the bottom edge), and the stroke is a specular rim: bright
  // where light catches the top edge, fading down the sides. Readability
  // comes from the material's own backdrop blur, not from opacity.
  // 第九轮： on iOS 26 the base layer is the real system glass
  // (.glassEffect, gated in Components.swift) and the hand-rolled sheen +
  // specular rim stay on top as a whisper of extra light; pre-26 the
  // stack below is unchanged.
  @ViewBuilder func glassBarBase<S: InsettableShape>(_ shape: S) -> some View {
    #if compiler(>=6.2)
    if #available(iOS 26, *) {
      GlassEffectSurface(shape: shape)
    } else {
      shape.fill(.ultraThinMaterial).opacity(0.72)
    }
    #else
    shape.fill(.ultraThinMaterial).opacity(0.72)
    #endif
  }
  func glassFill<S: InsettableShape>(_ shape: S) -> some View {
    ZStack {
      glassBarBase(shape)
      shape.fill(LinearGradient(stops: [
        .init(color: .white.opacity(0.20), location: 0),
        .init(color: .white.opacity(0.05), location: 0.45),
        .init(color: .clear, location: 0.7),
        .init(color: .black.opacity(0.05), location: 1),
      ], startPoint: .top, endPoint: .bottom))
      shape.strokeBorder(LinearGradient(colors: [.white.opacity(0.75), .white.opacity(0.22), .white.opacity(0.10)],
                                        startPoint: .top, endPoint: .bottom), lineWidth: 1)
    }
  }
  var glassCapsule: some View {
    glassFill(Capsule()).shadow(color: .black.opacity(0.18), radius: 18, x: 0, y: 8)
  }
  var glassCircle: some View {
    glassFill(Circle()).shadow(color: .black.opacity(0.18), radius: 18, x: 0, y: 8)
  }
  // The selected tab's thumb is a glass lens, not a solid pill （第三轮细化）:
  // translucent bright frost with its own specular rim and a soft lift
  // shadow, floating over the capsule's thinner glass; in dark mode the
  // frost thins out so the lens stays black glass, never a grey slab. The
  // accent tint stays on the icon and label, as before.
  var glassThumb: some View {
    ZStack {
      Capsule().fill(.white.opacity(scheme == .dark ? 0.20 : 0.50))
      Capsule().fill(LinearGradient(stops: [
        .init(color: .white.opacity(0.30), location: 0),
        .init(color: .clear, location: 0.55),
      ], startPoint: .top, endPoint: .bottom))
      Capsule().strokeBorder(LinearGradient(colors: [.white.opacity(0.85), .white.opacity(0.30)],
                                            startPoint: .top, endPoint: .bottom), lineWidth: 0.8)
    }
    .shadow(color: .black.opacity(0.16), radius: 7, x: 0, y: 2.5)
  }

  // Tabs follow the reference layout （第二轮细化）: big icon over the label.
  // The selected tab sits on the glass lens （glassThumb — translucent frost，
  // 第三轮细化） with its icon and label tinted the app accent; unselected
  // tabs keep the adaptive primary colour.
  func barTab(_ t: Int, _ name: String, _ icon: String) -> some View {
    let on = tab == t
    return VStack(spacing: 3) {
      Image(systemName: icon).font(.system(size: 27, weight: .semibold))
        .symbolEffect(.bounce, value: on)
      Text(name).font(.system(size: 11, weight: .semibold)).lineLimit(1)
    }
    .foregroundStyle(on ? Color.accentColor : Color.primary)
    .frame(width: 64, height: 58)
    .background {
      if on {
        glassThumb.matchedGeometryEffect(id: "barThumb", in: barNS)
      }
    }
    .contentShape(Capsule())
    .accessibilityLabel(name)
    .accessibilityAddTraits(on ? [.isSelected] : [])
  }

  func barCircle(_ icon: String, label: String, _ fn: @escaping () -> Void) -> some View {
    Button(action: fn) {
      Image(systemName: icon).font(.system(size: 23, weight: .semibold)).foregroundStyle(.primary)
        .frame(width: 60, height: 60)
        .background { glassCircle }
        .contentShape(Circle())
    }
    .buttonStyle(PressStyle(scale: 0.92))
    .accessibilityLabel(label)
  }
}

/// Global search (opened from the floating bar's search button): the same matching as
/// 全部 App (name / domain / handle / notes / bound identity values), over every account.
struct SearchView: View {
  @Environment(Store.self) var store
  @Environment(\.dismiss) var dismiss
  @State private var query = ""
  @State private var searchActive = false

  var results: [Account] {
    let q = query.trimmingCharacters(in: .whitespaces).lowercased()
    guard !q.isEmpty else { return store.index.byName }
    return store.index.byName.filter { matches($0, q) }
  }
  func matches(_ a: Account, _ q: String) -> Bool {
    a.name.lowercased().contains(q) || a.domain.lowercased().contains(q) || (a.handle ?? "").lowercased().contains(q) || a.notes.lowercased().contains(q)
      || a.identityIds.compactMap { store.identity($0) }.contains { $0.value.lowercased().contains(q) || $0.label.lowercased().contains(q) }
  }

  var body: some View {
    NavigationStack {
      List {
        if results.isEmpty {
          Text("没有匹配的服务。").foregroundStyle(.secondary)
        }
        ForEach(results) { a in
          Button { store.route = .account(a.id) } label: { ReelRow(account: a) }
            .buttonStyle(PressStyle(scale: 0.98))
            .accountSwipeActions(a)
            .contextMenu { AccountMenu(account: a) }
            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        }
      }
      .listStyle(.plain)
      .scrollContentBackground(.hidden)
      .background(Glow().ignoresSafeArea())
      .searchable(text: $query, isPresented: $searchActive, prompt: "搜索名称、域名、账号名")
      .onAppear {
        // Pull the keyboard up with the sheet (patch batch): flipping search active
        // a beat after the presentation settles — setting it in the same frame races
        // the sheet animation and the focus request is silently dropped.
        Task { try? await Task.sleep(for: .milliseconds(350)); searchActive = true }
      }
      .onChange(of: searchActive) { _, on in if !on { dismiss() } }
      .navigationTitle("搜索").navigationBarTitleDisplayMode(.inline)
      .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { dismiss() } label: { Image(systemName: "xmark") } } }
    }
  }
}

struct SheetHost: View {
  @Environment(Store.self) var store
  let route: Route
  var body: some View {
    switch route {
    case .identity(let id): IdentityDetail(id: id)
    case .account(let id): AccountDetail(id: id)
    case .newIdentity(let t): IdentityForm(existing: nil, type: t, defaultColor: COLORS[store.data.identities.count % COLORS.count])
    case .editIdentity(let id): IdentityForm(existing: store.identity(id), type: "email", defaultColor: COLORS[0])
    case .editAccount(let id): AccountFormHost(id: id)
    case .picker(let pre): PickerSheet(presetIdentity: pre)
    case .settings: SettingsSheet()
    case .search: SearchView()
    }
  }
}

struct AccountFormHost: View {
  @Environment(Store.self) var store
  let id: String
  var body: some View {
    if let a = store.account(id) { AccountForm(existing: a) }
  }
}

struct ToastView: View {
  @Environment(Store.self) var store
  var body: some View {
    if let t = store.toast {
      HStack(spacing: 12) {
        Image(uiImage: UIImage(named: "AppIcon60x60") ?? UIImage(systemName: "rectangle.stack.fill")!)
          .resizable().frame(width: 38, height: 38).clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        VStack(alignment: .leading, spacing: 1) {
          Text("绑哪儿").font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary)
          Text(t.text).font(.system(size: 15, weight: .semibold))
        }
        Spacer(minLength: 8)
        if let a = t.action {
          Button(a) { store.toastAction?(); withAnimation(Motion.snappy) { store.toast = nil } }.font(.system(size: 15, weight: .semibold))
        }
      }
      .padding(.horizontal, 14).padding(.vertical, 11)
      .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
      .bakedShadow(RoundedRectangle(cornerRadius: 24, style: .continuous), key: "toast", color: .black.opacity(0.25), radius: 20, y: 8)
      .padding(.horizontal, 14)
      .transition(.move(edge: .top).combined(with: .opacity))
      .id(t.id)
      .gesture(DragGesture().onEnded { v in if v.translation.height < -10 { withAnimation(Motion.snappy) { store.toast = nil } } })
      .sensoryFeedback(.success, trigger: t.id)
    }
  }
}

// MARK: - Motion

private struct SelectedTabKey: EnvironmentKey { static let defaultValue = 0 }
extension EnvironmentValues {
  var selectedTab: Int { get { self[SelectedTabKey.self] } set { self[SelectedTabKey.self] = newValue } }
}

/// The page you switch to slides in a little from the side you came from and settles with a
/// critically-damped spring, like a navigation push but lighter. Hidden state is set while the
/// page is off screen, so it never flashes before animating.
struct TabEnter: ViewModifier {
  let index: Int, tab: Int, dir: CGFloat
  @State private var shown: Bool
  @State private var selected: Bool
  init(index: Int, tab: Int, dir: CGFloat) {
    self.index = index; self.tab = tab; self.dir = dir
    _shown = State(initialValue: index == tab); _selected = State(initialValue: index == tab)
  }
  func body(content: Content) -> some View {
    // Scoped animation: only the opacity/offset animate. The page's own layout (large title,
    // scroll insets) is never pulled into the spring, so the title doesn't slide around.
    content
      .animation(Motion.tab) {
        $0.opacity(shown ? 1 : 0.35).offset(x: shown ? 0 : dir * 28)
      }
      .onChange(of: tab) { old, t in
        selected = t == index
        if t == index { shown = true }
        else if old == index {
          // The tab bar cross-fades the outgoing page for a moment; dimming it right away showed
          // as a flicker. Re-arm the entrance only once it's fully off screen.
          DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            guard !selected else { return }
            var tr = Transaction(); tr.disablesAnimations = true
            withTransaction(tr) { shown = false }
          }
        }
      }
  }
}
extension View {
  func tabEnter(_ index: Int, tab: Int, dir: CGFloat) -> some View { modifier(TabEnter(index: index, tab: tab, dir: dir)) }
}

/// Theme switch, done outside SwiftUI so it can't stutter:
/// 1. `snapshotView(afterScreenUpdates: false)` of the screen — a render-server copy of what's on
///    screen right now (no CPU redraw, unlike drawHierarchy/UIGraphicsImageRenderer, which cost a
///    full-screen render on the main thread before anything moved).
/// 2. It goes into an overlay window above the app, and in the same CA transaction the app windows'
///    interface style flips once (the store change runs with animations disabled; there's no
///    preferredColorScheme, so SwiftUI doesn't run a second implicit cross-fade).
/// 3. A circular hole opens in the overlay with a CAShapeLayer path animation. Path animations run
///    in the render server at the display's refresh rate (120 Hz on ProMotion), and because the
///    animation is committed in the same transaction as the re-rendered UI, the first revealed
///    pixels are already the new theme. The haptic fires from animationDidStart, i.e. on the frame
///    the circle starts moving.
@MainActor enum ThemeFX {
  static var origin: CGPoint? = nil
  static var overlay: UIWindow? = nil
  static func style(_ t: String) -> UIUserInterfaceStyle { t == "light" ? .light : t == "system" ? .unspecified : .dark }
  static func appWindows() -> [UIWindow] {
    UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows).filter { $0 !== overlay }
  }
  private static func commit(_ theme: String, store: Store, _ wins: [UIWindow]) {
    var tx = Transaction(); tx.disablesAnimations = true
    withTransaction(tx) { store.theme = theme }
    let st = style(theme)
    wins.forEach { if $0.overrideUserInterfaceStyle != st { $0.overrideUserInterfaceStyle = st } }
  }
  /// Entry point for user actions: snapshot BEFORE any state changes.
  static func set(_ theme: String, store: Store, from point: CGPoint? = nil) {
    guard store.theme != theme else { return }
    let wins = appWindows()
    let key = wins.first(where: \.isKeyWindow) ?? wins.first
    let screenSnap: UIView? = key?.windowScene?.screen.snapshotView(afterScreenUpdates: false)
    let snapOpt: UIView? = screenSnap ?? key?.snapshotView(afterScreenUpdates: false)
    let haptic = UIImpactFeedbackGenerator(style: .light)
    haptic.prepare()
    guard let win = key, let scene = win.windowScene,
          !UIAccessibility.isReduceMotionEnabled, overlay == nil, let snap = snapOpt else {
      commit(theme, store: store, wins); haptic.impactOccurred(); return
    }
    let b = scene.screen.bounds
    let ov = UIWindow(windowScene: scene)
    ov.frame = b; ov.windowLevel = .statusBar + 1; ov.isUserInteractionEnabled = false
    ov.backgroundColor = .clear
    let holder = UIView(frame: b)
    holder.isUserInteractionEnabled = false
    snap.frame = b
    holder.addSubview(snap)
    ov.addSubview(holder)

    let c = point ?? origin ?? CGPoint(x: b.maxX - 40, y: b.minY + 70)
    let r = hypot(max(c.x, b.width - c.x), max(c.y, b.height - c.y)) + 4
    func hole(_ rad: CGFloat) -> CGPath {
      let p = UIBezierPath(rect: b)
      p.append(UIBezierPath(arcCenter: c, radius: rad, startAngle: 0, endAngle: .pi * 2, clockwise: true))
      return p.cgPath
    }
    let mask = CAShapeLayer(); mask.fillRule = .evenOdd; mask.frame = b
    holder.layer.mask = mask

    CATransaction.begin()
    CATransaction.setDisableActions(true)
    mask.path = hole(r)
    ov.isHidden = false; overlay = ov
    commit(theme, store: store, wins)

    let a = CABasicAnimation(keyPath: "path")
    a.fromValue = hole(0.5); a.toValue = hole(r)
    a.duration = 0.52
    a.timingFunction = CAMediaTimingFunction(controlPoints: 0.32, 0.72, 0, 1)   // fast out, long settle
    a.fillMode = .backwards
    let d = RevealDelegate()
    d.started = { haptic.impactOccurred() }
    d.finished = { ov.isHidden = true; ov.subviews.forEach { $0.removeFromSuperview() }; if overlay === ov { overlay = nil } }
    a.delegate = d
    mask.add(a, forKey: "reveal")
    CATransaction.commit()
  }
  /// Keeps windows in sync with the stored theme (launch, external changes). No-op when equal.
  static func apply(_ theme: String) {
    let st = style(theme)
    appWindows().forEach { if $0.overrideUserInterfaceStyle != st { $0.overrideUserInterfaceStyle = st } }
  }
}

final class RevealDelegate: NSObject, CAAnimationDelegate {
  var started: (() -> Void)?
  var finished: (() -> Void)?
  func animationDidStart(_ anim: CAAnimation) { started?(); started = nil }
  func animationDidStop(_ anim: CAAnimation, finished flag: Bool) { finished?(); finished = nil }
}

/// Records where a control sits on screen, so the theme reveal starts from it.
struct ThemeOrigin: View {
  var body: some View {
    GeometryReader { g in
      Color.clear.preference(key: OriginKey.self, value: CGPoint(x: g.frame(in: .global).midX, y: g.frame(in: .global).midY))
    }
    .onPreferenceChange(OriginKey.self) { p in Task { @MainActor in ThemeFX.origin = p } }
  }
}
struct OriginKey: PreferenceKey {
  static var defaultValue: CGPoint = .zero
  static func reduce(value: inout CGPoint, nextValue: () -> CGPoint) { value = nextValue() }
}
