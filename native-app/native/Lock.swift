import SwiftUI
import Observation
import CryptoKit
import LocalAuthentication
import Security
import UIKit

// MARK: - PIN screen lock （绑哪儿移植自网页版屏幕锁；iOS 版加了面容 ID)
//
// - PIN 只存加盐 SHA256 哈希（盐随机 16 字节），连同 PIN 位数存 UserDefaults，明文不落盘。
// - 锁定时机：冷启动（enabled 时 AppLock 初始化即锁定，展示层先被锁屏盖住）；
//   切后台超过 60 秒返回前台时重新锁定。
// - 输错计数：连续错 5 次冷却 30 秒（冷却截止时间也落盘，杀掉 App 也不能绕过）。
// - 面容 ID 是可选的第二通道：LocalAuthentication 成功即解锁，失败回落 PIN。

@MainActor
@Observable
final class AppLock {
  private(set) var enabled: Bool
  var locked: Bool
  var bioOn: Bool { didSet { UserDefaults.standard.set(bioOn, forKey: "bind.lock.bio") } }
  @ObservationIgnored private var backgroundAt: Date? = nil
  @ObservationIgnored private var fails = 0

  init() {
    enabled = UserDefaults.standard.string(forKey: "bind.lock.hash") != nil
    locked = enabled
    bioOn = UserDefaults.standard.bool(forKey: "bind.lock.bio")
  }

  var pinLength: Int { UserDefaults.standard.integer(forKey: "bind.lock.len") }
  var coolUntil: Date? {
    let ms = UserDefaults.standard.double(forKey: "bind.lock.cool")
    return ms > 0 ? Date(timeIntervalSince1970: ms / 1000) : nil
  }
  var cooling: Bool { (coolUntil ?? .distantPast) > Date() }

  private func digest(_ pin: String, salt: String) -> String {
    SHA256.hash(data: Data((salt + ":" + pin).utf8)).map { String(format: "%02x", $0) }.joined()
  }

  func setPIN(_ pin: String) {
    var bytes = [UInt8](repeating: 0, count: 16)
    _ = SecRandomCopyBytes(kSecRandomDefault, 16, &bytes)
    let salt = Data(bytes).base64EncodedString()
    UserDefaults.standard.set(salt, forKey: "bind.lock.salt")
    UserDefaults.standard.set(digest(pin, salt: salt), forKey: "bind.lock.hash")
    UserDefaults.standard.set(pin.count, forKey: "bind.lock.len")
    enabled = true
    fails = 0
    UserDefaults.standard.removeObject(forKey: "bind.lock.cool")
  }

  /// also used by the settings screens to gate 修改 / 关闭 PIN
  func verify(_ pin: String) -> Bool {
    if cooling { return false }
    guard let salt = UserDefaults.standard.string(forKey: "bind.lock.salt"),
          let want = UserDefaults.standard.string(forKey: "bind.lock.hash") else { return false }
    if digest(pin, salt: salt) == want {
      fails = 0
      return true
    }
    fails += 1
    if fails >= 5 {
      UserDefaults.standard.set(nowMS() + 30_000, forKey: "bind.lock.cool")
      fails = 0
    }
    return false
  }

  func disable() {
    for k in ["bind.lock.hash", "bind.lock.salt", "bind.lock.len", "bind.lock.cool"] {
      UserDefaults.standard.removeObject(forKey: k)
    }
    bioOn = false
    enabled = false
    locked = false
    fails = 0
  }

  func unlock() { locked = false }

  func noteBackground() { backgroundAt = Date() }
  func noteForeground() {
    guard enabled, let b = backgroundAt else { backgroundAt = nil; return }
    backgroundAt = nil
    if Date().timeIntervalSince(b) > 60 { locked = true }
  }

  // MARK: biometrics
  var bioAvailable: Bool {
    LAContext().canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
  }
  var bioName: String {
    let ctx = LAContext()
    guard ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil) else { return "面容 ID" }
    return ctx.biometryType == .touchID ? "指纹" : "面容 ID"
  }
  func tryBiometrics() async -> Bool {
    let ctx = LAContext()
    guard ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil) else { return false }
    do {
      return try await ctx.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: "解锁绑哪儿")
    } catch { return false }
  }
}

func pinValid(_ s: String) -> Bool {
  (4...6).contains(s.count) && s.allSatisfy(\.isNumber)
}

// MARK: - lock screen

private struct ShakeEffect: GeometryEffect {
  var amount: CGFloat = 9
  var shakes = 3
  var animatableData: CGFloat
  func effectValue(size: CGSize) -> ProjectionTransform {
    ProjectionTransform(CGAffineTransform(translationX: amount * sin(animatableData * .pi * CGFloat(shakes)), y: 0))
  }
}

struct LockView: View {
  @Environment(AppLock.self) var lock
  @State private var entered = ""
  @State private var shake = 0
  @State private var bioTried = false

  var body: some View {
    ZStack {
      Color(UIColor.systemBackground).ignoresSafeArea()
      VStack(spacing: 0) {
        Spacer()
        Image(systemName: "lock.fill").font(.system(size: 40)).foregroundStyle(.secondary)
        Text("绑哪儿已锁定").font(.system(size: 20, weight: .semibold)).padding(.top, 14)
        TimelineView(.periodic(from: Date(), by: 0.5)) { _ in
          if lock.cooling, let until = lock.coolUntil {
            Text("输错太多次，请 \(max(1, Int(until.timeIntervalSinceNow.rounded(.up)))) 秒后再试")
              .font(.system(size: 14)).foregroundStyle(.orange).padding(.top, 8)
          } else {
            Text("输入 \(lock.pinLength) 位 PIN 解锁").font(.system(size: 14)).foregroundStyle(.secondary).padding(.top, 8)
          }
        }
        HStack(spacing: 16) {
          ForEach(0..<max(lock.pinLength, 1), id: \.self) { i in
            Circle()
              .fill(i < entered.count ? Color.primary : Color.clear)
              .frame(width: 14, height: 14)
              .overlay(Circle().stroke(Color.secondary, lineWidth: 1.5))
          }
        }
        .padding(.top, 26)
        .modifier(ShakeEffect(animatableData: CGFloat(shake)))
        .animation(.easeInOut(duration: 0.35), value: shake)
        keypad.padding(.top, 34)
        Spacer()
      }
      .padding(.horizontal, 40)
    }
    .sensoryFeedback(.error, trigger: shake)
    .onAppear {
      if lock.bioOn && !bioTried {
        bioTried = true
        Task { if await lock.tryBiometrics() { lock.unlock() } }
      }
    }
  }

  var keypad: some View {
    VStack(spacing: 14) {
      ForEach([["1", "2", "3"], ["4", "5", "6"], ["7", "8", "9"]], id: \.self) { row in
        HStack(spacing: 22) {
          ForEach(row, id: \.self) { d in key(d) { tap(d) } }
        }
      }
      HStack(spacing: 22) {
        if lock.bioOn && lock.bioAvailable {
          key(lock.bioName == "指纹" ? "touchid" : "faceid", system: true) { Task { if await lock.tryBiometrics() { lock.unlock() } } }
        } else {
          Color.clear.frame(width: 72, height: 72)
        }
        key("0") { tap("0") }
        key("delete.left", system: true) { if !entered.isEmpty { entered.removeLast() } }
      }
    }
  }

  func key(_ label: String, system: Bool = false, _ fn: @escaping () -> Void) -> some View {
    Button(action: fn) {
      Group {
        if system { Image(systemName: label).font(.system(size: 26)) }
        else { Text(label).font(.system(size: 30, weight: .medium)) }
      }
      .frame(width: 72, height: 72)
      .background(Color.secondary.opacity(0.12), in: Circle())
    }
    .buttonStyle(PressStyle(scale: 0.92))
    .foregroundStyle(.primary)
  }

  func tap(_ d: String) {
    guard !lock.cooling else { return }
    UIImpactFeedbackGenerator(style: .light).impactOccurred()
    entered += d
    if entered.count >= lock.pinLength {
      let pin = entered
      entered = ""
      if lock.verify(pin) { lock.unlock() } else { shake += 1 }
    }
  }
}

// MARK: - settings

struct LockSettingsView: View {
  @Environment(AppLock.self) var lock
  @Environment(Store.self) var store
  @State private var sheet: PinSheetMode? = nil

  var body: some View {
    Form {
      if !lock.enabled {
        Section {
          Button("设置 PIN") { sheet = .setup }
        } footer: {
          Text("开启后，打开绑哪儿、或切回超过 1 分钟时要输 PIN 才能看数据。PIN 只存本机（加盐哈希），忘了无法找回，只能删掉 App 重装——开启前请先导出一份备份。")
        }
      } else {
        Section {
          Toggle(isOn: Binding(get: { lock.bioOn }, set: { v in lock.bioOn = v })) {
            Label("\(lock.bioName)解锁", systemImage: lock.bioName == "指纹" ? "touchid" : "faceid")
          }.disabled(!lock.bioAvailable)
          Button("修改 PIN") { sheet = .change }
          Button("关闭 PIN", role: .destructive) { sheet = .disable }
        } footer: {
          Text(lock.bioAvailable ? "关掉 PIN 需要先输一次当前 PIN。" : "这台设备不能用生物识别，只能用 PIN。关掉 PIN 需要先输一次当前 PIN。")
        }
      }
    }
    .navigationTitle("屏幕锁").navigationBarTitleDisplayMode(.inline)
    .sheet(item: $sheet) { m in PinSetupView(mode: m) }
  }
}

enum PinSheetMode: Identifiable {
  case setup, change, disable
  var id: Int { switch self { case .setup: return 0; case .change: return 1; case .disable: return 2 } }
  var title: String { switch self { case .setup: return "设置 PIN"; case .change: return "修改 PIN"; case .disable: return "关闭 PIN" } }
}

struct PinSetupView: View {
  @Environment(AppLock.self) var lock
  @Environment(Store.self) var store
  @Environment(\.dismiss) var dismiss
  let mode: PinSheetMode
  @State private var oldPin = ""
  @State private var newPin = ""
  @State private var again = ""
  @State private var error = ""

  var body: some View {
    NavigationStack {
      Form {
        if mode != .setup {
          Section {
            SecureField("当前 PIN", text: $oldPin).keyboardType(.numberPad)
          }
        }
        if mode != .disable {
          Section {
            SecureField("新 PIN（4–6 位数字）", text: $newPin).keyboardType(.numberPad)
            SecureField("再输一次新 PIN", text: $again).keyboardType(.numberPad)
          }
        }
        if !error.isEmpty { Section { Text(error).foregroundStyle(.red) } }
        Section {
          Button {
            submit()
          } label: {
            HStack { Spacer(); Text(mode == .disable ? "验证并关闭" : "保存").bold(); Spacer() }
          }
        }
      }
      .navigationTitle(mode.title).navigationBarTitleDisplayMode(.inline)
      .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } } }
    }
  }

  func submit() {
    switch mode {
    case .setup:
      guard pinValid(newPin) else { error = "PIN 要是 4–6 位数字"; return }
      guard newPin == again else { error = "两次输入的 PIN 不一样"; return }
      lock.setPIN(newPin)
      store.show("屏幕锁已开启")
      dismiss()
    case .change:
      guard lock.verify(oldPin) else { error = lock.cooling ? "输错太多次，先等冷却结束" : "当前 PIN 不对"; return }
      guard pinValid(newPin) else { error = "新 PIN 要是 4–6 位数字"; return }
      guard newPin == again else { error = "两次输入的新 PIN 不一样"; return }
      lock.setPIN(newPin)
      store.show("PIN 已修改")
      dismiss()
    case .disable:
      guard lock.verify(oldPin) else { error = lock.cooling ? "输错太多次，先等冷却结束" : "当前 PIN 不对"; return }
      lock.disable()
      store.show("屏幕锁已关闭")
      dismiss()
    }
  }
}
