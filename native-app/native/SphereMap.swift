import SwiftUI
import UIKit
import SpriteKit

// MARK: - sphere galaxy （绑哪儿第三批：关系图整页三维球形星系，替换上游双列连线图）
//
// The whole tab is one sphere: every account is a bubble on a Fibonacci sphere.
// Rounds 3–8 drew it with a single SwiftUI Canvas; 第九轮 moves the drawing to
// a SpriteKit scene (SphereScene below): one SKSpriteNode per bubble whose
// texture is the 第八轮 SphereBaker bitmap, so the GPU composites the ball and
// the CPU only writes (position, size, alpha, z) per bubble per frame — Canvas
// is CPU-rasterised and still hitched on device with 150+ bitmaps + labels
// recomposited every frame. The maths is unchanged: quaternion trackball
// orientation + perspective projection are still computed in Swift
// (SphereMath), and the scene owns the orientation state, so a drag or a
// spin no longer re-renders any SwiftUI at all. Friction-tuned
// inertia, a tap pulse and a slow idle rotation give it physical-ball feel
// （第九轮's baked shading sprite — limb darkening + highlight — was
// removed again in 第十轮 at the user's request: no dark shadow on the
// ball, background transparent, bubbles alone define the sphere）。
// 第十轮 keeps the stage and the maths but rebuilds the catering behind it —
// disk-cached, batched, gesture-yielding bakes plus a launch warm-up (see
// SphereBaker): the remaining device hitch was bakes and texture uploads
// landing mid-gesture, not the engine.
// Drag rotates (quaternion trackball
// since 第六轮： no Euler angles, no pitch clamp, so the ball rolls 360° in every
// direction), pinch zooms, back-side bubbles fade/shrink and can't
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

/// Unit quaternion (w + xi + yj + zk): the sphere's orientation （第六轮）.
/// Euler yaw/pitch had a hard stop — pitch was clamped to ±1.25 rad, so the
/// ball dead-ended when rolled far enough vertically. A quaternion has no
/// such axis limit: drag increments compose as rotations about the
/// screen-space axis perpendicular to the drag, so the ball trackballs
/// freely through 360° in any direction, diagonals included.
struct Quat {
  var w: Double, x: Double, y: Double, z: Double
  static let identity = Quat(w: 1, x: 0, y: 0, z: 0)
  /// Rotation of `angle` rad about `axis` (need not be unit; zero axis or
  /// zero angle gives identity).
  static func axisAngle(_ axis: Vec3, _ angle: Double) -> Quat {
    let n = sqrt(axis.x * axis.x + axis.y * axis.y + axis.z * axis.z)
    guard n > 1e-12, angle != 0 else { return .identity }
    let s = sin(angle / 2) / n
    return Quat(w: cos(angle / 2), x: axis.x * s, y: axis.y * s, z: axis.z * s)
  }
  /// Hamilton product: `self.times(o)` applies `o` first, then `self`.
  /// Screen-space drag increments therefore pre-multiply the committed
  /// orientation: q = dq.times(q).
  func times(_ o: Quat) -> Quat {
    Quat(w: w * o.w - x * o.x - y * o.y - z * o.z,
         x: w * o.x + x * o.w + y * o.z - z * o.y,
         y: w * o.y - x * o.z + y * o.w + z * o.x,
         z: w * o.z + x * o.y - y * o.x + z * o.w)
  }
  /// Renormalise after long composition chains so float drift never
  /// scales the ball.
  func normalized() -> Quat {
    let n = sqrt(w * w + x * x + y * y + z * z)
    guard n > 1e-12 else { return .identity }
    return Quat(w: w / n, x: x / n, y: y / n, z: z / n)
  }
  /// Rotate a vector: v' = q v q*, in the expanded cross-product form.
  func rotate(_ v: Vec3) -> Vec3 {
    let tx = 2 * (y * v.z - z * v.y)
    let ty = 2 * (z * v.x - x * v.z)
    let tz = 2 * (x * v.y - y * v.x)
    return Vec3(x: v.x + w * tx + (y * tz - z * ty),
                y: v.y + w * ty + (z * tx - x * tz),
                z: v.z + w * tz + (x * ty - y * tx))
  }
}

struct SphereBubble {
  let account: Account
  let dir: Vec3
  let baseR: CGFloat
  let group: SphereGroup
  /// What the under-bubble label draws （第七轮）: precomputed once in
  /// computeBubbles so the per-frame canvas does zero string work, and
  /// never a raw URL — domain-shaped names are replaced by a friendly
  /// name derived from the registrable domain (see SphereLabel). Display
  /// only: the account data itself is never touched.
  let displayLabel: String
  /// Pre-rendered bubble face （第八轮）: the circular-clipped icon (or
  /// brand letter tile), favicon backing and group rim, baked offscreen
  /// once by SphereBaker at the largest size a bubble can reach. The
  /// per-frame canvas only drawImages this bitmap (GPU scales it) with
  /// the frame's opacity — no per-frame clip / stroke / decode of the
  /// up-to-288px source icon, which was the diagnosed hitch: ~150
  /// bubbles × clip+scale+stroke+Text at 120 Hz blew the frame budget
  /// and the drag stuttered periodically.
  let baked: UIImage
  /// Pre-rendered label bitmaps （第八轮）, one per colour scheme (the
  /// canvas picks at draw time): displayLabel typeset once at spec
  /// time, drawn per frame as an image instead of a Text layout.
  let labelLight: UIImage?
  let labelDark: UIImage?
}

/// Friendly sphere labels （第七轮）: a chunk of the library was imported
/// with the raw domain sitting in the name field (binance.com,
/// zhj.sccchina.net, xn--…), and the sphere used to draw that verbatim
/// under the bubble. The label now derives a name instead: a real name
/// passes through untouched; a domain-shaped name is replaced by the
/// registrable domain's main label, capitalised (binance.com → Binance,
/// zhj.sccchina.net → Sccchina), with xn-- labels punycode-decoded back
/// to Chinese. Only the sphere reads this — every other page keeps
/// showing account.name as stored.
enum SphereLabel {
  /// Two-part public suffixes: the registrable name sits one level
  /// higher than usual (example.com.cn → "example", not "com";
  /// online.immi.gov.au → "immi", not "gov").
  static let twoPartSuffixes: Set<String> = [
    "co.cn", "com.cn", "gov.cn", "org.cn", "net.cn", "edu.cn", "ac.cn",
    "com.au", "gov.au", "org.au", "net.au", "edu.au",
    "co.uk", "org.uk", "gov.uk", "ac.uk",
    "com.hk", "gov.hk", "org.hk", "net.hk", "edu.hk",
    "com.tw", "gov.tw", "org.tw", "net.tw", "edu.tw",
    "com.sg", "gov.sg", "org.sg", "net.sg",
    "co.jp", "or.jp", "go.jp", "ne.jp", "ac.jp",
    "co.kr", "or.kr", "go.kr", "ne.kr",
  ]

  static func make(name rawName: String, domain rawDomain: String) -> String {
    let name = rawName.trimmingCharacters(in: .whitespaces)
    let domain = rawDomain.trimmingCharacters(in: .whitespaces).lowercased()
    guard isDomainLike(name, domain: domain) else { return name }
    if let friendly = friendlyName(fromHost: domain.isEmpty ? name.lowercased() : domain) {
      return friendly
    }
    // derivation gave up (empty host, numeric IP label, undecodable
    // punycode): fall back to the stored name, truncated
    return String(name.prefix(16))
  }

  /// A name counts as domain-shaped when it equals / ends with the
  /// account's domain, or is a pure-ASCII dotted host string. Real names
  /// — anything with a space or a non-ASCII character — never qualify.
  static func isDomainLike(_ name: String, domain: String) -> Bool {
    if name.isEmpty { return !domain.isEmpty }
    if name.contains(" ") { return false }
    if name.unicodeScalars.contains(where: { $0.value > 127 }) { return false }
    let lower = name.lowercased()
    if !domain.isEmpty && (lower == domain || lower.hasSuffix("." + domain)) { return true }
    let labels = lower.split(separator: ".", omittingEmptySubsequences: false)
    guard labels.count >= 2,
          labels.allSatisfy({ !$0.isEmpty && $0.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" }) })
    else { return false }
    let tld = labels.last!
    return tld.count >= 2 && tld.allSatisfy({ $0.isLetter })
  }

  /// The registrable label of a host, capitalised: walk past the public
  /// suffix (two-part suffixes consume one extra label), take the label
  /// just above it — subdomains in front of it are ignored by
  /// construction (zhj.sccchina.net → sccchina). An xn-- label is
  /// punycode-decoded instead of capitalised. A purely numeric main
  /// label (yun.139.com → "139") falls back to the leftmost label
  /// instead of giving up （第八轮）: yun.139.com → Yun. Nil when there
  /// is no usable label at all (too few labels, numeric everywhere).
  static func friendlyName(fromHost host: String) -> String? {
    let labels = host.split(separator: ".", omittingEmptySubsequences: true).map(String.init)
    guard labels.count >= 2 else { return nil }
    let lastTwo = labels.suffix(2).joined(separator: ".")
    let mainIdx = twoPartSuffixes.contains(lastTwo) ? labels.count - 3 : labels.count - 2
    guard mainIdx >= 0 else { return nil }
    if let s = friendlyLabel(labels[mainIdx]) { return s }
    // numeric main label: derive from the leftmost label instead of
    // falling back to the raw domain string
    guard mainIdx > 0 else { return nil }
    let left = labels[0]
    guard left != "www" else { return nil }
    return friendlyLabel(left)
  }

  /// One host label as a display name: xn-- punycode-decoded, anything
  /// else capitalised; nil for an empty or purely numeric label.
  static func friendlyLabel(_ label: String) -> String? {
    if label.hasPrefix("xn--") {
      guard let decoded = Punycode.decode(String(label.dropFirst(4))), !decoded.isEmpty else { return nil }
      return decoded
    }
    guard !label.isEmpty, !label.allSatisfy({ $0.isNumber }) else { return nil }
    return String(label.prefix(1)).uppercased() + String(label.dropFirst())
  }
}

/// Minimal RFC 3492 punycode decoder for one "xn--" label payload (the
/// part after the prefix); nil on malformed input. Self-check vectors
/// (verified against the reference codec):
///   decode("fiqs8s")    == "中国"    (xn--fiqs8s)
///   decode("bcher-kva") == "bücher"  (xn--bcher-kva)
///   decode("fiq228c")   == "中文"    (xn--fiq228c)
enum Punycode {
  static func decode(_ payload: String) -> String? {
    let base = 36, tmin = 1, tmax = 26, skew = 38, damp = 700
    let initialBias = 72, initialN = 128
    func digit(_ ch: Character) -> Int? {
      guard let v = ch.asciiValue else { return nil }
      switch v {
      case 97...122: return Int(v - 97)      // a-z → 0-25
      case 65...90: return Int(v - 65)       // A-Z → 0-25
      case 48...57: return Int(v - 48) + 26  // 0-9 → 26-35
      default: return nil
      }
    }
    func adapt(_ delta0: Int, _ numPoints: Int, _ firstTime: Bool) -> Int {
      var delta = firstTime ? delta0 / damp : delta0 / 2
      delta += delta / numPoints
      var k = 0
      while delta > (base - tmin) * tmax / 2 {
        delta /= base - tmin
        k += base
      }
      return k + (base - tmin + 1) * delta / (delta + skew)
    }
    let chars = Array(payload)
    var output: [UInt32] = []
    var read = 0
    // basic code points ahead of the last delimiter are copied verbatim
    if let lastDash = chars.lastIndex(of: "-") {
      for ch in chars[..<lastDash] {
        guard let v = ch.asciiValue, v < 128 else { return nil }
        output.append(UInt32(v))
      }
      read = lastDash + 1
    }
    var n = initialN, i = 0, bias = initialBias
    while read < chars.count {
      let oldi = i
      var w = 1, k = base
      while true {
        guard read < chars.count, let d = digit(chars[read]) else { return nil }
        read += 1
        i += d * w
        guard i < (1 << 30) else { return nil }   // overflow guard
        let t = k <= bias ? tmin : (k >= bias + tmax ? tmax : k - bias)
        if d < t { break }
        guard w <= (1 << 30) / (base - t) else { return nil }
        w *= base - t
        k += base
      }
      let outLen = output.count + 1
      bias = adapt(i - oldi, outLen, oldi == 0)
      n += i / outLen
      i %= outLen
      guard n >= 0, n <= 0x10FFFF, !(0xD800...0xDFFF).contains(n) else { return nil }
      output.insert(UInt32(n), at: i)
      i += 1
    }
    var result = ""
    for cp in output {
      guard let s = Unicode.Scalar(cp) else { return nil }
      result.unicodeScalars.append(s)
    }
    return result
  }
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
  /// Orient a point by the quaternion. Viewer sits at +Z: z > 0 faces the user.
  static func rotate(_ p: Vec3, q: Quat) -> Vec3 { q.rotate(p) }
  static let focal = 3.2
  static func project(_ p: Vec3, q: Quat, radius R: Double) -> (x: Double, y: Double, z: Double, scale: Double) {
    let r = rotate(p, q: q)
    let s = focal / (focal - r.z)
    return (r.x * R * s, -r.y * R * s, r.z, s)
  }
}

/// Inertia after a flick （第六轮）: the ball keeps turning about the flick's
/// fixed screen-space axis, the angular speed decaying exponentially until
/// commitSpin folds the final orientation back into the committed quaternion.
/// 第九轮 retunes the decay 1.8 → 1.7: a typical flick (ω ≈ 2–4 rad/s) now
/// glides for ~2–3 s before the speed falls under the scene's 0.05 rad/s
/// stop threshold — the friction tail of a real ball, not a brake.
struct SphereSpin {
  var q0: Quat        // committed orientation when the flick started
  var axis: Vec3      // unit axis, screen space
  var omega: Double   // initial angular speed, rad/s
  var start: Date
  static let decay = 1.7
  func orientation(at date: Date) -> Quat {
    let t = max(0, date.timeIntervalSince(start))
    let angle = omega * (1 - exp(-Self.decay * t)) / Self.decay
    return Quat.axisAngle(axis, angle).times(q0).normalized()
  }
  func speed(at date: Date) -> Double {
    let t = max(0, date.timeIntervalSince(start))
    return omega * exp(-Self.decay * t)
  }
}

/// The sphere's face at bake size, rendered offscreen once per bubble
/// by SphereBaker （第八轮）. Mirrors what the canvas used to draw every
/// frame: favicon bubbles sit on a white disc with the icon inset,
/// bundled/custom icons fill the circle, icon-less accounts get the
/// brand-colour letter tile, and the group rim is baked in (inside the
/// bounds via strokeBorder). Everything is baked at full opacity; the
/// per-frame depth / focus alpha is applied by the canvas through
/// GraphicsContext.opacity, so one bake serves every frame.
struct BubbleFace: View {
  let entry: IconEntry?
  let brand: Color
  let letter: String
  let rim: Color
  /// Bake diameter in points: the largest a bubble can be drawn is
  /// 2 × baseR(≤24) × projection scale(≤ focal/(focal−1) ≈ 1.45) ≈ 70pt,
  /// so 80pt at scale 2 (160px) covers it — the GPU upscales the last
  /// few percent on @3x screens, far cheaper than re-clipping the
  /// up-to-288px source every frame.
  static let diameter: CGFloat = 80
  var body: some View {
    ZStack {
      if let entry {
        if entry.favicon {
          Circle().fill(.white)
          Image(uiImage: entry.image).resizable()
            .padding(Self.diameter * 0.14)   // = the old r × 0.28 inset, as a fraction of the diameter
        } else {
          Image(uiImage: entry.image).resizable()
        }
      } else {
        Circle().fill(brand)
        Text(letter).font(.system(size: Self.diameter / 2 * 0.92, weight: .semibold, design: .rounded))
          .foregroundStyle(.white)
      }
    }
    .frame(width: Self.diameter, height: Self.diameter)
    .clipShape(Circle())
    .overlay { Circle().strokeBorder(rim, lineWidth: 2.5) }
  }
}

/// Offscreen pre-rendering for the sphere （第八轮）, production
/// pipeline rebuilt in 第十轮. Bakes bubble faces and label bitmaps at
/// spec time (computeBubbles) and caches them, so the per-frame stage
/// work is reduced to node transforms over ready textures. Icons that
/// are still in flight when specs are computed are baked as letter
/// tiles first; computeBubbles registers the IconStore load through
/// ensureLoad, and when the icon lands the baker coalesces the burst
/// into one revision bump, which the view turns into a spec refresh
/// that re-bakes just the new faces (the caches make every
/// already-baked face a hit).
///
/// 第十轮 — why the pipeline changed: the baker was @MainActor and
/// baked synchronously inside computeBubbles, so an icon landing
/// mid-drag triggered refreshBubbles → a burst of ImageRenderer work
/// plus fresh SKTexture uploads on the main thread, in the middle of
/// the user's gesture (device video: letter tiles morphing into icons
/// while sliding, spin speed stuttering). The SpriteKit stage itself
/// was never the bottleneck — the catering was. Now:
/// - bakes are also persisted to Caches/sphere-bake as PNGs, keyed by
///   an FNV-1a hash of the full input key, so a cold launch reads
///   files instead of re-rendering (decode restores the bake scale:
///   faces 2×, labels 3× — SKTexture label sizing reads points);
/// - a cache miss no longer bakes inline: it enqueues a job and the
///   letter tile stands in. Jobs run in batches of ≤6 with a runloop
///   yield between batches, and the whole queue pauses while the
///   scene reports a live drag / pinch / spin (setBusy), as do spec
///   refreshes on the view side — nothing competes with a gesture;
/// - completions bump the same coalesced revision as icon loads, and
///   prewarm() runs a full spec pass the moment store data lands, so
///   the sphere tab is usually all cache hits on first open.
@MainActor final class SphereBaker: ObservableObject {
  static let shared = SphereBaker()
  @Published private(set) var revision = 0
  /// Bumped when the scene reports the ball has gone idle after being
  /// busy: the view flushes the spec refresh it deferred meanwhile.
  @Published private(set) var settledTick = 0

  private var bubbleCache: [String: UIImage] = [:]
  private var labelCache: [String: UIImage] = [:]
  private var loadRegistered = Set<String>()

  private static let faceScale: CGFloat = 2    // BubbleFace bake scale (renderer + disk decode)
  private static let labelScale: CGFloat = 3   // label bake scale (renderer + disk decode)
  private static let batchSize = 6

  // MARK: disk cache (Caches/sphere-bake)

  private let diskDir: URL = {
    let u = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("sphere-bake", isDirectory: true)
    try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
    return u
  }()
  private let io = DispatchQueue(label: "atlas.spherebake", qos: .utility)
  private var pruneStarted = false

  init() { pruneDiskIfNeeded() }

  /// FNV-1a over the key string: String.hashValue is per-process
  /// randomised, so it can never name a file that must survive a
  /// relaunch — this hash can, and collisions just cost a re-bake.
  private static func fnv(_ s: String) -> String {
    var h: UInt64 = 0xcbf29ce484222325
    for b in s.utf8 { h = (h ^ UInt64(b)) &* 0x100000001b3 }
    return String(h, radix: 16)
  }

  private func diskImage(fileKey: String, scale: CGFloat) -> UIImage? {
    guard let data = try? Data(contentsOf: diskDir.appendingPathComponent(fileKey + ".png"))
    else { return nil }
    // PNG data carries pixels only; the bake scale must be restored or
    // a label texture reports 3× the points and draws 3× too large.
    return UIImage(data: data, scale: scale)
  }

  private func writeDisk(_ img: UIImage, fileKey: String) {
    let url = diskDir.appendingPathComponent(fileKey + ".png")
    io.async { if let d = img.pngData() { try? d.write(to: url, options: .atomic) } }
  }

  /// Once per launch, off the main thread: if the bake directory has
  /// grown past ~80 MB, delete oldest-first until it fits. Normal use
  /// sits far below this (one ~160px PNG per account state); the cap
  /// only guards against years of renamed accounts piling up.
  private func pruneDiskIfNeeded() {
    guard !pruneStarted else { return }
    pruneStarted = true
    let dir = diskDir
    io.async {
      let fm = FileManager.default
      guard let items = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey])
      else { return }
      var total = 0
      var sized: [(url: URL, size: Int, date: Date)] = []
      for u in items {
        let v = try? u.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        let s = v?.fileSize ?? 0
        total += s
        sized.append((u, s, v?.contentModificationDate ?? .distantPast))
      }
      let limit = 80 * 1024 * 1024
      guard total > limit else { return }
      for item in sized.sorted(by: { $0.date < $1.date }) {
        if total <= limit { break }
        try? fm.removeItem(at: item.url)
        total -= item.size
      }
    }
  }

  // MARK: bake queue (batched, gesture-yielding)

  private struct Job {
    let key: String
    let produce: () -> UIImage?
    let apply: (UIImage?) -> Void
  }
  private var queue: [Job] = []
  private var queuedKeys = Set<String>()
  private var pumpScheduled = false
  private var retryScheduled = false
  private var busy = false

  /// Live re-check of the scene's interaction state, wired by the
  /// sphere host at scene creation. The pushed busy flag (setBusy)
  /// can go stale if the scene stops being presented mid-spin — no
  /// update loop runs to report the settle — so the pump reconciles
  /// against this provider, whose spin term is wall-clock based and
  /// decays on its own.
  var busyProvider: (() -> Bool)?
  private var isBusyNow: Bool {
    if let busyProvider { return busyProvider() }
    return busy
  }

  private func enqueue(key: String, produce: @escaping () -> UIImage?,
                       apply: @escaping (UIImage?) -> Void) {
    guard queuedKeys.insert(key).inserted else { return }
    queue.append(Job(key: key, produce: produce, apply: apply))
    schedulePump()
  }

  private func schedulePump() {
    guard !pumpScheduled else { return }
    pumpScheduled = true
    Task { @MainActor in
      self.pumpScheduled = false
      self.pumpBatch()
    }
  }

  /// One batch per runloop turn: ≤6 ImageRenderer bakes, then the rest
  /// of the queue waits for a later turn — a 150-face cold start warms
  /// up over a second or two of idle slices instead of one long hitch.
  private func pumpBatch() {
    guard !isBusyNow else { scheduleRetry(); return }
    var n = 0
    while n < Self.batchSize, !queue.isEmpty {
      let job = queue.removeFirst()
      let img = job.produce()
      queuedKeys.remove(job.key)
      job.apply(img)
      n += 1
    }
    if !queue.isEmpty { schedulePump() }
  }

  private func scheduleRetry() {
    guard !retryScheduled else { return }
    retryScheduled = true
    Task { @MainActor in
      try? await Task.sleep(for: .milliseconds(200))
      self.retryScheduled = false
      // the pushed flag went stale (scene unpresented mid-spin): fire
      // the settle the view's deferred refresh is waiting on
      if self.busy && !self.isBusyNow { self.setBusy(false) }
      if !self.queue.isEmpty { self.schedulePump() }
    }
  }

  /// The scene's interaction report （第十轮）: while the ball is being
  /// dragged / pinched / spun, baking pauses outright. When it settles,
  /// the queue resumes and settledTick tells the view to flush the
  /// spec refresh it deferred during the gesture.
  func setBusy(_ b: Bool) {
    guard b != busy else { return }
    busy = b
    if !b {
      settledTick &+= 1
      schedulePump()
    }
  }

  // MARK: faces & labels

  /// The baked face for one bubble spec. Lookup order: memory → disk →
  /// queue. The cache key carries every input the bake reads (account,
  /// icon key + presence, name/domain for the brand colour, group for
  /// the rim), so an edit that changes any of them bakes fresh instead
  /// of serving the stale face — and because the disk file is named by
  /// a hash of that same key, any input change also misses on disk and
  /// re-bakes. Until a queued face lands, the letter tile stands in.
  func bubbleImage(account: Account, iconKey: String, entry: IconEntry?,
                   brand: Color, letter: String, group: SphereGroup) -> UIImage {
    let ck = [account.id, iconKey, entry != nil ? "i" : "t", account.name, account.domain,
              String(group.rawValue), letter].joined(separator: "|")
    if let img = bubbleCache[ck] { return img }
    let fk = "f-" + Self.fnv(ck)
    if let img = diskImage(fileKey: fk, scale: Self.faceScale) {
      bubbleCache[ck] = img
      return img
    }
    // No icon yet: the letter tile IS the face until the icon lands
    // (its arrival changes this key through the presence flag above).
    guard let entry else {
      return letterTile(name: account.name, domain: account.domain,
                        brand: brand, letter: letter, group: group)
    }
    enqueue(key: ck) {
      let renderer = ImageRenderer(content: BubbleFace(entry: entry, brand: brand, letter: letter, rim: group.color))
      renderer.scale = Self.faceScale
      return renderer.uiImage
    } apply: { [weak self] img in
      guard let self, let img else { return }
      self.bubbleCache[ck] = img
      self.writeDisk(img, fileKey: fk)
      self.noteReady()
    }
    return letterTile(name: account.name, domain: account.domain,
                      brand: brand, letter: letter, group: group)
  }

  /// The letter-tile face: placeholder while a real face waits in the
  /// queue, and the final face for icon-less bubbles. Keyed by
  /// everything that determines it (the brand colour derives from
  /// name+domain), memory- and disk-cached like real faces. Baked
  /// synchronously on a total miss — distinct tiles are few (an
  /// initial × a brand × a group), and spec refreshes never run
  /// mid-gesture anymore, so the burst the queue exists to prevent
  /// cannot come from here.
  private func letterTile(name: String, domain: String, brand: Color,
                          letter: String, group: SphereGroup) -> UIImage {
    let ck = ["tile", name, domain, letter, String(group.rawValue)].joined(separator: "|")
    if let img = bubbleCache[ck] { return img }
    let fk = "t-" + Self.fnv(ck)
    if let img = diskImage(fileKey: fk, scale: Self.faceScale) {
      bubbleCache[ck] = img
      return img
    }
    let renderer = ImageRenderer(content: BubbleFace(entry: nil, brand: brand, letter: letter, rim: group.color))
    renderer.scale = Self.faceScale
    let img = renderer.uiImage ?? UIImage()
    bubbleCache[ck] = img
    writeDisk(img, fileKey: fk)
    return img
  }

  /// displayLabel typeset once, as a transparent bitmap (black text for
  /// light mode, white for dark — the canvas's .primary at 9pt). Same
  /// lookup order as faces; a queued label reads as nil for now (the
  /// bubble simply has no label this refresh) and the completion's
  /// revision bump re-reads it as a hit. Nil for an empty label too.
  func labelImage(_ text: String, scheme: ColorScheme) -> UIImage? {
    guard !text.isEmpty else { return nil }
    let ck = (scheme == .dark ? "d|" : "l|") + text
    if let img = labelCache[ck] { return img }
    let fk = "l-" + Self.fnv(ck)
    if let img = diskImage(fileKey: fk, scale: Self.labelScale) {
      labelCache[ck] = img
      return img
    }
    enqueue(key: ck) {
      let renderer = ImageRenderer(content:
        Text(text).font(.system(size: 9, weight: .medium))
          .foregroundStyle(scheme == .dark ? Color.white : Color.black))
      renderer.scale = Self.labelScale
      return renderer.uiImage
    } apply: { [weak self] img in
      guard let self, let img else { return }
      self.labelCache[ck] = img
      self.writeDisk(img, fileKey: fk)
      self.noteReady()
    }
    return nil
  }

  // MARK: icon-load plumbing & warm-up

  /// Register an IconStore load for a key whose icon was missing at
  /// spec time (once per key — IconStore itself coalesces waiters, this
  /// set keeps spec refreshes from stacking duplicate callbacks). When
  /// the load finishes, one coalesced revision bump asks the view to
  /// refresh specs so the bubble re-bakes with its real icon.
  func ensureLoad(key: String) {
    guard !key.isEmpty, loadRegistered.insert(key).inserted else { return }
    IconStore.shared.load(key) { _ in
      Task { @MainActor in SphereBaker.shared.loadFinished(key) }
    }
  }

  private func loadFinished(_ key: String) {
    loadRegistered.remove(key)
    noteReady(reprewarm: true)
  }

  /// One coalesced "something landed" signal for both icon loads and
  /// bake completions: bursts collapse into a single revision bump per
  /// ~150 ms window. An icon landing also re-runs the warm-up pass, so
  /// the real faces get queued even if the sphere tab was never opened.
  private var readyScheduled = false
  private var reprewarmPending = false
  private func noteReady(reprewarm: Bool = false) {
    if reprewarm { reprewarmPending = true }
    guard !readyScheduled else { return }
    readyScheduled = true
    Task { @MainActor in
      try? await Task.sleep(for: .milliseconds(150))
      self.readyScheduled = false
      self.revision &+= 1
      if self.reprewarmPending {
        self.reprewarmPending = false
        if let idx = self.prewarmIndex { _ = MapView.computeBubbles(idx) }
      }
    }
  }

  /// Warm-up （第十轮）: called the moment store data lands (launch /
  /// sync adopt), right after the icon prefetch starts. A full spec
  /// pass resolves every bubble against the caches — hits are free,
  /// misses enqueue queue jobs and register icon loads — so by the
  /// time the user opens the sphere tab the faces are baked (or
  /// already on disk from last launch) instead of being made to order
  /// under their first drag.
  private var prewarmIndex: AtlasIndex?
  func prewarm(_ index: AtlasIndex) {
    prewarmIndex = index
    _ = MapView.computeBubbles(index)
  }
}

// MARK: - SpriteKit sphere stage （第九轮）

/// The GPU stage for the sphere. One SKSpriteNode per bubble (texture =
/// the SphereBaker face bitmap) plus one per label, and a pooled set of
/// SKShapeNodes for the identity-focus threads. （第九轮 had a faint
/// body disc and a baked shading sprite on top — limb darkening +
/// top-left highlight for the "real ball" read; 第十轮 removed both at
/// the user's request: no grey bed, no darkened limb, the background
/// stays transparent and the bubbles alone define the ball。）The scene
/// owns the orientation state (committed
/// quaternion, friction spin, idle rotation), so gestures write straight
/// into it and a frame of rotation touches no SwiftUI state at all;
/// SwiftUI only pushes (specs, focus, scheme) through configure() when
/// they change, and reads currentOrientation()/currentZoom back for tap
/// hit-testing. Nodes and textures are pooled by account id: a spec
/// refresh reconciles the pool (create / remove / re-texture only when
/// the baked UIImage instance actually changed), never per frame.
final class SphereScene: SKScene {
  // pushed configuration (configure)
  private var specs: [SphereBubble] = []
  private var focus: SphereFocus? = nil
  private var scheme: ColorScheme = .light
  private var threadID: String? = nil
  private var threadColor: Color = .gray
  // orientation state — the single source of truth （第九轮）
  private(set) var q = Quat.axisAngle(Vec3(x: 1, y: 0, z: 0), -0.3)
    .times(Quat.axisAngle(Vec3(x: 0, y: 1, z: 0), 0.6)).normalized()
  private var spin: SphereSpin? = nil
  private(set) var currentZoom: CGFloat = 1
  private var dragging = false
  private var pinching = false
  // Interaction reporting for the bake pipeline （第十轮）: the baker
  // pauses its queue and the view defers spec refreshes while this is
  // true, so no ImageRenderer work or texture upload ever lands in
  // the middle of a gesture. Idle display rotation is NOT interaction
  // — baking proceeds underneath it.
  var onBusyChange: ((Bool) -> Void)? = nil
  private var lastBusy = false
  var isInteracting: Bool {
    dragging || pinching || (spin.map { $0.speed(at: Date()) >= 0.05 } ?? false)
  }
  private func reportBusy() {
    let b = isInteracting
    guard b != lastBusy else { return }
    lastBusy = b
    onBusyChange?(b)
  }
  // frame bookkeeping
  private var lastTime: TimeInterval = 0
  private var lastInteraction: TimeInterval = 0
  private var pulses: [String: TimeInterval] = [:]
  // node pool
  private var faceNodes: [String: SKSpriteNode] = [:]
  private var labelNodes: [String: SKSpriteNode] = [:]
  private var faceImage: [String: UIImage] = [:]
  private var labelImage: [String: UIImage?] = [:]
  private var threadNodes: [SKShapeNode] = []

  override init(size: CGSize) {
    super.init(size: size)
    backgroundColor = .clear
    // No body disc and no shading overlay （第十轮， 用户 2026-11-24
    // 追加）: the 第九轮 limb-darkening disc and grey ball bed are
    // gone — the sphere's background is fully transparent and the
    // bubbles alone define the ball.
  }
  required init?(coder aDecoder: NSCoder) { fatalError("SphereScene is created in code only") }

  // MARK: configuration

  func configure(specs: [SphereBubble], focus: SphereFocus?, scheme: ColorScheme,
                 threadID: String?, threadColor: Color) {
    if focus != self.focus { lastInteraction = lastTime }   // a focus change is an interaction: idle rotation restarts its countdown
    self.focus = focus
    self.threadID = threadID
    self.threadColor = threadColor
    self.scheme = scheme
    self.specs = specs
    // Textures created or swapped by this reconcile are collected and
    // bulk-preloaded below （第十轮）: the GPU gets the whole set in
    // one go instead of uploading each on its first drawn frame.
    var freshTextures: [SKTexture] = []
    // reconcile the node pool with the spec set
    let ids = Set(specs.map { $0.account.id })
    for id in Array(faceNodes.keys) where !ids.contains(id) {
      faceNodes[id]?.removeFromParent()
      labelNodes[id]?.removeFromParent()
      faceNodes[id] = nil; labelNodes[id] = nil
      faceImage[id] = nil; labelImage[id] = nil
    }
    for b in specs {
      let id = b.account.id
      if faceNodes[id] == nil {
        let tex = SKTexture(image: b.baked)
        freshTextures.append(tex)
        let face = SKSpriteNode(texture: tex)
        let label = SKSpriteNode()
        label.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        addChild(face)
        addChild(label)
        faceNodes[id] = face
        labelNodes[id] = label
        faceImage[id] = b.baked
      } else if faceImage[id] !== b.baked {
        let tex = SKTexture(image: b.baked)
        freshTextures.append(tex)
        faceNodes[id]?.texture = tex
        faceImage[id] = b.baked
      }
      let want: UIImage? = scheme == .dark ? b.labelDark : b.labelLight
      let stored: UIImage? = labelImage[id] ?? nil
      if stored !== want, let label = labelNodes[id] {
        if let want {
          let tex = SKTexture(image: want)
          freshTextures.append(tex)
          label.texture = tex
          label.size = tex.size()
        } else {
          label.texture = nil
        }
        labelImage[id] = want
      }
    }
    if !freshTextures.isEmpty {
      SKTexture.preloadTextures(freshTextures) {}
    }
  }

  // MARK: gesture entry points (called from MapView's SwiftUI gestures)

  func beginDrag() {
    commitSpin()
    dragging = true
    lastInteraction = lastTime
    reportBusy()
  }
  /// UIKit-space drag deltas, exactly the convention the Canvas code used:
  /// the axis is (dy, dx) because the projection works in y-up space.
  func dragBy(dx: Double, dy: Double) {
    let dq = Quat.axisAngle(Vec3(x: dy, y: dx, z: 0), hypot(dx, dy) * MapView.radPerPoint)
    q = dq.times(q).normalized()
    lastInteraction = lastTime
  }
  func endDrag(vx: Double, vy: Double) {
    dragging = false
    lastInteraction = lastTime
    // Flick → inertia about a fixed axis, same component caps and start
    // threshold the Canvas spin had; the friction tail lives in SphereSpin.
    let wy = min(max(vx * MapView.radPerPoint, -9), 9)
    let wx = min(max(vy * MapView.radPerPoint, -9), 9)
    let omega = hypot(wx, wy)
    if omega > 0.25 {
      spin = SphereSpin(q0: q, axis: Vec3(x: wx / omega, y: wy / omega, z: 0), omega: omega, start: Date())
    }
    reportBusy()
  }
  func beginPinch() { commitSpin(); pinching = true; lastInteraction = lastTime; reportBusy() }
  func endPinch() { pinching = false; lastInteraction = lastTime; reportBusy() }
  func setZoom(_ z: CGFloat) { currentZoom = z; lastInteraction = lastTime }
  func noteInteraction() { lastInteraction = lastTime }
  /// Tap feedback: the hit bubble pulses once (evaluated in layout, so
  /// it composes with the per-frame size instead of fighting an SKAction).
  func pulse(_ id: String) { pulses[id] = lastTime; lastInteraction = lastTime }
  func currentOrientation() -> Quat { spin?.orientation(at: Date()) ?? q }
  private func commitSpin() {
    guard let s = spin else { return }
    q = s.orientation(at: Date())
    spin = nil
    reportBusy()
  }

  // MARK: per-frame layout

  override func update(_ currentTime: TimeInterval) {
    if lastTime == 0 {
      lastTime = currentTime
      lastInteraction = currentTime
    }
    let dt = min(currentTime - lastTime, 0.05)
    lastTime = currentTime
    // orientation: an active friction spin wins; otherwise, after ~4 s
    // untouched and unfocused, the ball display-rotates very slowly
    // about a tilted axis (0.06 rad/s ≈ a full turn in ~105 s) — any
    // gesture or focus change re-arms the countdown via lastInteraction.
    if let s = spin {
      q = s.orientation(at: Date())
      if s.speed(at: Date()) < 0.05 { spin = nil }
    } else if !dragging, focus == nil, !specs.isEmpty, currentTime - lastInteraction > 4 {
      let dq = Quat.axisAngle(Vec3(x: 0.30, y: 1, z: 0), 0.06 * dt)
      q = dq.times(q).normalized()
    }
    reportBusy()   // a spin expiring here is the settle the baker waits for
    layout(now: currentTime)
  }

  private func layout(now: TimeInterval) {
    let size = self.size
    guard size.width > 1, size.height > 1, !specs.isEmpty else { return }
    // Scene space is y-up; the SwiftUI layout centre (w/2, h/2 − 24 in
    // top-left space) is (w/2, h/2 + 24) here, and a projected point's
    // y flips sign at plot time — all rotation maths stays untouched.
    let center = CGPoint(x: size.width / 2, y: size.height / 2 + 24)
    let R = Double(min(size.width, size.height)) * 0.40 * Double(currentZoom)
    let iconScale = min(1.0, Double(currentZoom))   // pinch-in never blows icons past normal size (patch batch)

    struct P {
      let b: SphereBubble; let x: CGFloat; let y: CGFloat; let r: CGFloat
      let z: Double; let alpha: CGFloat; let hidden: Bool
    }
    var ps: [P] = []
    ps.reserveCapacity(specs.count)
    for b in specs {
      let p = SphereMath.project(b.dir, q: q, radius: R)
      let t = (p.z + 1) / 2
      let r = b.baseR * CGFloat(p.scale) * CGFloat(0.7 + 0.3 * t) * CGFloat(iconScale)
      var alpha = 0.10 + 0.90 * pow(t, 1.4)
      var hidden = false
      switch focus {
      case .identity(let fid):
        // Identity focus （第五轮）: only the bound bubbles exist at all.
        hidden = !b.account.identityIds.contains(fid)
      case .group(let g):
        if b.group != g { alpha *= 0.22 }
      case nil:
        break
      }
      ps.append(P(b: b, x: center.x + CGFloat(p.x), y: center.y - CGFloat(p.y),
                  r: r, z: p.z, alpha: CGFloat(alpha), hidden: hidden))
    }
    // Label budget （第七轮）: labels are always on, capped at the
    // front-most 48 bubbles past the usual gate (r >= 16, z > 0.1).
    var labelIDs = Set<String>()
    var budget = 48
    for p in ps.sorted(by: { $0.z > $1.z }) where !p.hidden && p.r >= 16 && p.z > 0.1 {
      if budget == 0 { break }
      labelIDs.insert(p.b.account.id)
      budget -= 1
    }
    // focus threads （第三轮细化）: centre → each bound bubble, in the
    // identity's colour, depth-faded like the bubbles, under them.
    let threaded = threadID.map { tid in ps.filter { !$0.hidden && $0.b.account.identityIds.contains(tid) } } ?? []
    while threadNodes.count < threaded.count {
      let n = SKShapeNode()
      n.lineWidth = 1
      n.fillColor = .clear
      addChild(n)
      threadNodes.append(n)
    }
    for (i, node) in threadNodes.enumerated() {
      guard i < threaded.count else { node.isHidden = true; continue }
      let p = threaded[i]
      node.isHidden = false
      let path = CGMutablePath()
      path.move(to: center)
      path.addLine(to: CGPoint(x: p.x, y: p.y))
      node.path = path
      node.strokeColor = UIColor(threadColor).withAlphaComponent(p.alpha * 0.55)
      node.zPosition = CGFloat(p.z) * 0.5 - 2
    }
    // bubbles + labels
    for p in ps {
      let id = p.b.account.id
      guard let face = faceNodes[id], let label = labelNodes[id] else { continue }
      if p.hidden {
        face.isHidden = true
        label.isHidden = true
        continue
      }
      face.isHidden = false
      var d = p.r * 2
      if let t0 = pulses[id] {
        let t = now - t0
        if t >= 0.38 { pulses[id] = nil } else { d *= 1 + 0.20 * CGFloat(sin(.pi * t / 0.38)) }
      }
      face.position = CGPoint(x: p.x, y: p.y)
      face.size = CGSize(width: d, height: d)
      face.alpha = p.alpha
      face.zPosition = CGFloat(p.z)
      if labelIDs.contains(id), label.texture != nil {
        label.isHidden = false
        label.position = CGPoint(x: p.x, y: p.y - p.r - 8)
        label.alpha = p.alpha
        label.zPosition = CGFloat(p.z) + 2
      } else {
        label.isHidden = true
      }
    }
  }

}

/// SwiftUI host for the sphere's SKView. A representable (not SpriteView)
/// so configure() lands on every SwiftUI update — specs / focus / scheme
/// changes reach the scene without the scene observing the store itself.
/// The view is transparent: the Glow backdrop stays SwiftUI's.
struct SphereSKView: UIViewRepresentable {
  let scene: SphereScene
  let specs: [SphereBubble]
  let focus: SphereFocus?
  let scheme: ColorScheme
  let threadID: String?
  let threadColor: Color

  func makeUIView(context: Context) -> SKView {
    let v = SKView()
    v.allowsTransparency = true
    v.backgroundColor = .clear
    v.preferredFramesPerSecond = 120   // ProMotion where the hardware has it; clamped elsewhere
    scene.scaleMode = .resizeFill
    // The baker yields to live gestures （第十轮）: the scene reports
    // its interaction transitions, the baker pauses / resumes its
    // queue and ticks the view's deferred-refresh flush.
    scene.onBusyChange = { busy in
      Task { @MainActor in SphereBaker.shared.setBusy(busy) }
    }
    Task { @MainActor in
      SphereBaker.shared.busyProvider = { [weak scene] in scene?.isInteracting ?? false }
    }
    v.presentScene(scene)
    return v
  }
  func updateUIView(_ v: SKView, context: Context) {
    scene.configure(specs: specs, focus: focus, scheme: scheme, threadID: threadID, threadColor: threadColor)
  }
}

struct MapView: View {
  @Environment(Store.self) var store
  @Environment(\.colorScheme) private var colorScheme
  // Pre-rendering （第八轮；第十轮加避让）: when icons that were missing
  // at spec time land — or queued bakes complete — the baker bumps its
  // revision and the specs refresh (below). A refresh that would land
  // mid-gesture defers instead (see scheduleRefresh): baking and
  // texture uploads no longer fight the user's drag.
  @ObservedObject private var baker = SphereBaker.shared
  // The SpriteKit stage （第九轮）: orientation, spin, zoom and idle
  // rotation all live in the scene now, so SwiftUI keeps only the
  // gesture sampling bookkeeping (velocity needs the gesture's own
  // timestamps) and the interaction state (focus, sheets, haptics).
  @State private var scene = SphereScene(size: CGSize(width: 320, height: 320))
  // gesture bookkeeping
  @State private var dragStarted = false
  @State private var dragLast: (date: Date, t: CGSize)? = nil
  @State private var dragVel: CGSize = .zero
  @State private var pinchBase: CGFloat? = nil
  // Bubble specs are computed once and cached （第六轮）: body re-evaluates on
  // every drag frame, and rebuilding 150+ specs (plus groupCounts re-deriving
  // them) each time was a standing per-frame cost. The cache refreshes when
  // the store's accounts/identities actually change (see the onChange hooks
  // in body); before the first refresh lands, reads fall back to computing.
  @State private var cachedBubbles: [SphereBubble]? = nil
  // A spec refresh deferred because the ball was mid-gesture （第十轮）;
  // flushed once when the baker reports the scene has settled.
  @State private var pendingRefresh = false
  // interaction feedback / menus
  @State private var focus: SphereFocus? = nil
  @State private var groupSheet: SphereGroup? = nil
  @State private var pendingAdd: String? = nil
  @State private var tapTick = 0
  @State private var pressTick = 0
  @Namespace private var segNS

  static let radPerPoint = 0.0055

  var bubbles: [SphereBubble] { cachedBubbles ?? Self.computeBubbles(store.index) }
  static func computeBubbles(_ index: AtlasIndex) -> [SphereBubble] {
    let accs = index.byName
    let dirs = SphereMath.directions(accs.count)
    return accs.enumerated().map { k, a in
      let first = a.identityIds.lazy.compactMap { index.identityByID[$0] }.first
      let r = min(24, 13 + 4.5 * sqrt(Double(a.identityIds.count)))
      let group = SphereGroup.of(first)
      let label = SphereLabel.make(name: a.name, domain: a.domain)
      // Pre-rendering （第八轮）: everything the frame used to recompute
      // or re-draw per bubble is resolved here, once — the icon key,
      // the decoded entry, the baked face and the label bitmaps. An
      // icon still in flight bakes as a letter tile for now; the load
      // registered with the baker re-bakes it when it lands (revision
      // bump → spec refresh), riding IconStore's existing pipeline.
      let key = IconStore.shared.key(name: a.name, domain: a.domain, icon: a.icon)
      let entry = key.isEmpty ? nil : IconStore.shared.cached(key)
      if entry == nil && !key.isEmpty && !IconStore.shared.hasFailed(key) {
        SphereBaker.shared.ensureLoad(key: key)
      }
      // the tile letter follows the label （第七轮）: a domain-named
      // account shows its friendly initial (or decoded Chinese),
      // never the raw host's first letter
      let letter = String(label.trimmingCharacters(in: .whitespaces).prefix(1)).uppercased()
      let baked = SphereBaker.shared.bubbleImage(account: a, iconKey: key, entry: entry,
                                                 brand: brandColor(name: a.name, domain: a.domain),
                                                 letter: letter, group: group)
      return SphereBubble(account: a, dir: dirs[k], baseR: r, group: group,
                          displayLabel: label, baked: baked,
                          labelLight: SphereBaker.shared.labelImage(label, scheme: .light),
                          labelDark: SphereBaker.shared.labelImage(label, scheme: .dark))
    }
  }
  func refreshBubbles() { cachedBubbles = Self.computeBubbles(store.index) }
  /// Every spec-refresh trigger routes through here （第十轮）: while
  /// the scene is being dragged / pinched / spun, refreshing would
  /// enqueue bakes and swap textures under the gesture — the diagnosed
  /// hitch — so the refresh parks in pendingRefresh and the settled
  /// tick flushes it exactly once. Multiple triggers during one
  /// gesture still cost one refresh.
  func scheduleRefresh() {
    if scene.isInteracting { pendingRefresh = true }
    else { pendingRefresh = false; refreshBubbles() }
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
            // stage for recognition — that fight was the long-press flicker.
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
    .onAppear { scheduleRefresh() }
    .onChange(of: store.demoFocus) { _, f in
      withAnimation(Motion.smooth) { focus = (f == nil || f == "none") ? nil : .identity(f!) }
    }
    // Bubble-spec cache invalidation （第六轮）: the index rebuilds inside
    // data's didSet, so when these fire the fresh index is already in place.
    // Accounts + identities cover everything computeBubbles reads (account
    // order, bindings, identity types); an unrelated edit may refresh the
    // cache once extra — a rare spare rebuild, never a stale ball.
    // 第十轮： all of them route through scheduleRefresh, so an edit
    // landing mid-gesture defers like everything else.
    .onChange(of: store.data.accounts) { _, _ in scheduleRefresh() }
    .onChange(of: store.data.identities) { _, _ in scheduleRefresh() }
    // Icons landing after spec time （第八轮）: the baker's coalesced
    // revision bump refreshes the specs so those bubbles re-bake with
    // their real icons (faces already baked stay cache hits). Bake
    // completions bump the same revision （第十轮）.
    .onChange(of: baker.revision) { _, _ in scheduleRefresh() }
    // The gesture settled （第十轮）: flush the one deferred refresh.
    .onChange(of: baker.settledTick) { _, _ in
      if pendingRefresh { pendingRefresh = false; refreshBubbles() }
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

  // MARK: stage

  /// The focused identity, when the focus is one （第三轮细化 threads):
  /// its id and colour are pushed to the scene with the specs.
  var focusIdentity: Identity? {
    if case .identity(let fid) = focus { return store.identity(fid) }
    return nil
  }

  /// The sphere itself is the SpriteKit stage now （第九轮）: SwiftUI
  /// hands it the specs / focus / scheme and keeps the gestures — the
  /// scene owns orientation, spin, zoom and the per-frame layout.
  func sphere(in size: CGSize) -> some View {
    SphereSKView(scene: scene, specs: bubbles, focus: focus, scheme: colorScheme,
                 threadID: focusIdentity?.id, threadColor: focusIdentity.map { Color(hex: $0.color) } ?? .gray)
      .frame(width: size.width, height: size.height)
  }

  // MARK: gestures

  var dragGesture: some Gesture {
    DragGesture(minimumDistance: 4)
      .onChanged { v in
        if !dragStarted {
          scene.beginDrag()
          dragStarted = true
          // The drag only starts past its minimum distance; swallowing that
          // first sample (no rotation, just the baseline) keeps the ball
          // from jumping when rotation kicks in (patch batch).
          dragVel = .zero
          dragLast = (v.time, v.translation)
          return
        }
        let last = dragLast!
        let dx = Double(v.translation.width - last.t.width)
        let dy = Double(v.translation.height - last.t.height)
        if dx != 0 || dy != 0 {
          // Trackball increment （第六轮）: the scene rotates about the
          // screen-space axis perpendicular to this step's drag direction,
          // so the front of the ball follows the finger 1:1 and the roll
          // is unlimited — see SphereScene.dragBy.
          scene.dragBy(dx: dx, dy: dy)
        }
        let dt = v.time.timeIntervalSince(last.date)
        if dt > 0.016 {
          dragVel = CGSize(width: (v.translation.width - last.t.width) / CGFloat(dt),
                           height: (v.translation.height - last.t.height) / CGFloat(dt))
        }
        dragLast = (v.time, v.translation)
      }
      .onEnded { _ in
        dragStarted = false
        dragLast = nil
        // Flick → the scene's friction spin (no haptic on spin start
        // （第五轮）: sliding the ball stays silent; pressTick belongs
        // only to the segment long-press).
        scene.endDrag(vx: Double(dragVel.width), vy: Double(dragVel.height))
      }
  }

  var pinchGesture: some Gesture {
    MagnificationGesture()
      .onChanged { s in
        if pinchBase == nil { scene.beginPinch(); pinchBase = scene.currentZoom }
        scene.setZoom(min(2.4, max(0.55, (pinchBase ?? 1) * s)))
      }
      .onEnded { _ in
        pinchBase = nil
        scene.endPinch()
      }
  }

  func tap(at loc: CGPoint, in size: CGSize) {
    // hit-testing projects through the very same quaternion the scene is
    // showing (the live spin orientation while a flick is still decaying)
    let qNow = scene.currentOrientation()
    let zoom = scene.currentZoom
    let center = CGPoint(x: size.width / 2, y: size.height / 2 - 24)
    let R = Double(min(size.width, size.height)) * 0.40 * Double(zoom)
    var best: (id: String, z: Double)? = nil
    for b in bubbles {
      // identity focus （第五轮）: hidden bubbles are not tappable either
      if let f = focus, case .identity(let fid) = f, !b.account.identityIds.contains(fid) { continue }
      let p = SphereMath.project(b.dir, q: qNow, radius: R)
      guard p.z > -0.05 else { continue }   // back side can't be tapped
      let t = (p.z + 1) / 2
      // same radius the scene draws with (incl. the min(1, zoom) icon cap), + slack
      let r = Double(b.baseR) * p.scale * (0.7 + 0.3 * t) * min(1.0, Double(zoom)) + 6
      let d = hypot(Double(loc.x - center.x) - p.x, Double(loc.y - center.y) - p.y)
      if d <= r && (best == nil || p.z > best!.z) { best = (b.account.id, p.z) }
    }
    if let best {
      scene.pulse(best.id)   // elastic pop on the hit bubble （第九轮）, under the route change
      tapTick &+= 1
      store.route = .account(best.id)
    } else if focus != nil {
      // tapping empty sphere clears a chip / demo focus (patch batch)
      withAnimation(Motion.smooth) { focus = nil }
      scene.noteInteraction()
      tapTick &+= 1
    }
  }

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
      .glassSurface(Capsule(), interactive: true)
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
        .symbolEffect(.bounce, value: on)
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
