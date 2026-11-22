import Foundation
import SwiftUI
import CryptoKit
import Security

// MARK: - Keychain (tiny wrapper, used for the WebDAV password)

enum Keychain {
  private static func query(_ service: String, _ account: String) -> [String: Any] {
    [kSecClass as String: kSecClassGenericPassword,
     kSecAttrService as String: service,
     kSecAttrAccount as String: account]
  }
  static func get(service: String, account: String) -> String? {
    var q = query(service, account)
    q[kSecReturnData as String] = true
    q[kSecMatchLimit as String] = kSecMatchLimitOne
    var out: CFTypeRef?
    guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess,
          let d = out as? Data else { return nil }
    return String(data: d, encoding: .utf8)
  }
  static func set(_ value: String, service: String, account: String) {
    let d = Data(value.utf8)
    let status = SecItemUpdate(query(service, account) as CFDictionary,
                               [kSecValueData as String: d] as CFDictionary)
    if status == errSecItemNotFound {
      var q = query(service, account)
      q[kSecValueData as String] = d
      q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
      SecItemAdd(q as CFDictionary, nil)
    }
  }
  static func remove(service: String, account: String) {
    SecItemDelete(query(service, account) as CFDictionary)
  }
}

// MARK: - WebDAV backup （绑哪儿移植自网页版；与加密 Gist 同步并存，分工不同)
//
// - WebDAV 是「整份备份」：把本机 atlas.json 的同一份数据明文 PUT 到你自己的服务器，
//   恢复时整表替换（替换前自动给本机数据留一份快照文件，防误覆盖）。
// - 加密同步（Sync.swift）是逐条合并 + 端到端加密。两者互不干扰，可以同时开。
// - 策略与网页版一致：零轮询。上传只由数据变更触发（Store.onSaved -> schedule，
//   2 秒防抖 + 内容哈希比对，没变不发请求）；拉取只在手动点「从云端恢复」时。
// - 网络失败只记状态，绝不阻塞或丢本地数据；下次变更再试。

enum DAVError: LocalizedError {
  case msg(String)
  var errorDescription: String? { if case .msg(let s) = self { return s }; return nil }
}

@MainActor
final class WebDAV: ObservableObject {
  @Published var status = ""
  @Published var busy = false
  @Published var lastAt: Double = UserDefaults.standard.double(forKey: "atlas.webdav.at")
  weak var store: Store?
  private var timer: DispatchWorkItem?

  private static let kcService = "xyz.465871.bind.webdav"
  private static let kcAccount = "webdav"

  // MARK: config (url/user/path in UserDefaults; password only in Keychain)
  var base: String { UserDefaults.standard.string(forKey: "atlas.webdav.url") ?? "" }
  var user: String { UserDefaults.standard.string(forKey: "atlas.webdav.user") ?? "" }
  var path: String {
    let p = UserDefaults.standard.string(forKey: "atlas.webdav.path") ?? ""
    return p.isEmpty ? "account-atlas/atlas.json" : p
  }
  var password: String { Keychain.get(service: Self.kcService, account: Self.kcAccount) ?? "" }
  var configured: Bool { !base.trimmingCharacters(in: .whitespaces).isEmpty && !user.trimmingCharacters(in: .whitespaces).isEmpty }
  private var lastHash: String {
    get { UserDefaults.standard.string(forKey: "atlas.webdav.hash") ?? "" }
    set { UserDefaults.standard.set(newValue, forKey: "atlas.webdav.hash") }
  }

  func saveConfig(base: String, user: String, path: String, password: String) {
    UserDefaults.standard.set(base.trimmingCharacters(in: .whitespaces), forKey: "atlas.webdav.url")
    UserDefaults.standard.set(user.trimmingCharacters(in: .whitespaces), forKey: "atlas.webdav.user")
    UserDefaults.standard.set(path.trimmingCharacters(in: .whitespaces), forKey: "atlas.webdav.path")
    if password.isEmpty { Keychain.remove(service: Self.kcService, account: Self.kcAccount) }
    else { Keychain.set(password, service: Self.kcService, account: Self.kcAccount) }
    status = configured ? "已保存" : ""
  }

  var fileURL: URL? {
    let b = base.trimmingCharacters(in: .whitespaces)
    guard !b.isEmpty else { return nil }
    let joined = b.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/" + path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    return URL(string: joined)
  }
  private var dirURL: URL? { fileURL?.deletingLastPathComponent() }

  // MARK: http
  private func request(_ method: String, url: URL, body: Data? = nil) -> URLRequest {
    var r = URLRequest(url: url)
    r.httpMethod = method
    r.cachePolicy = .reloadIgnoringLocalCacheData
    r.timeoutInterval = 25
    let auth = Data((user + ":" + password).utf8).base64EncodedString()
    r.setValue("Basic " + auth, forHTTPHeaderField: "Authorization")
    if let body {
      r.httpBody = body
      r.setValue("application/json", forHTTPHeaderField: "Content-Type")
    }
    return r
  }

  /// sends and returns (data, statusCode); transport errors become human-readable DAVError
  private func send(_ req: URLRequest) async throws -> (Data, Int) {
    do {
      let (d, resp) = try await URLSession.shared.data(for: req)
      return (d, (resp as? HTTPURLResponse)?.statusCode ?? 0)
    } catch {
      throw DAVError.msg("连不上服务器——检查网络、地址是否写对（要以 https:// 开头）")
    }
  }

  private func human(_ code: Int, forWrite: Bool = false) -> String {
    switch code {
    case 401, 403: return "账号或密码不对（HTTP \(code)）——检查 WebDAV 的用户名密码；坚果云要用「应用密码」不是登录密码"
    case 404: return forWrite ? "地址不对或文件夹不存在（HTTP 404）——检查地址拼写，文件夹要先建好" : "云端还没有备份（HTTP 404）"
    case 405: return "这家 WebDAV 不让这么写文件（HTTP 405）——换个支持 PUT 的服务或目录"
    default: return "服务器返回 HTTP \(code)"
    }
  }

  // MARK: encode / hash (sorted keys so the hash is stable across runs)
  private func encode(_ d: AtlasData) throws -> Data {
    let e = JSONEncoder(); e.outputFormatting = [.sortedKeys]
    return try e.encode(d)
  }
  private func hash(_ d: Data) -> String {
    SHA256.hash(data: d).map { String(format: "%02x", $0) }.joined()
  }

  // MARK: operations
  func backupNow() async {
    guard let store else { return }
    guard configured else { status = "先填服务器地址和用户名"; return }
    guard store.data.demo != true else { status = "示例数据不备份"; return }
    guard !busy else { return }
    busy = true; status = "正在备份…"
    defer { busy = false }
    do {
      guard let url = fileURL else { throw DAVError.msg("服务器地址不对") }
      let payload = try encode(store.data)
      var (_, code) = try await send(request("PUT", url: url, body: payload))
      if code == 404 || code == 409 {
        // parent folder missing on some servers: create it, then retry once
        if let dir = dirURL { _ = try? await send(request("MKCOL", url: dir)) }
        (_, code) = try await send(request("PUT", url: url, body: payload))
      }
      guard (200..<300).contains(code) else { throw DAVError.msg(human(code, forWrite: true)) }
      lastHash = hash(payload)
      lastAt = nowMS()
      UserDefaults.standard.set(lastAt, forKey: "atlas.webdav.at")
      status = "已备份 " + Date(timeIntervalSince1970: lastAt / 1000).formatted(date: .omitted, time: .shortened)
    } catch {
      status = "备份失败：" + ((error as? DAVError)?.errorDescription ?? error.localizedDescription) + "（本地数据还在，没丢）"
    }
  }

  func restoreNow() async {
    guard let store else { return }
    guard configured else { status = "先填服务器地址和用户名"; return }
    guard !busy else { return }
    busy = true; status = "正在从云端恢复…"
    defer { busy = false }
    do {
      guard let url = fileURL else { throw DAVError.msg("服务器地址不对") }
      let (data, code) = try await send(request("GET", url: url))
      if code == 404 { status = "云端还没有备份"; return }
      guard (200..<300).contains(code) else { throw DAVError.msg(human(code)) }
      guard let remote = try? JSONDecoder().decode(AtlasData.self, from: data) else {
        throw DAVError.msg("云端文件不是有效的绑哪儿备份")
      }
      // snapshot the current local data first, so a wrong restore is recoverable
      if let cur = try? encode(store.data) {
        let snap = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
          .appendingPathComponent("atlas-before-restore.json")
        try? cur.write(to: snap, options: .atomic)
      }
      store.adopt(remote)
      store.setKind(store.kind)
      if let p = try? encode(store.data) { lastHash = hash(p) }
      status = "已从云端恢复（恢复前的本机数据已留在本机快照里）"
    } catch {
      status = "恢复失败：" + ((error as? DAVError)?.errorDescription ?? error.localizedDescription)
    }
  }

  func testConnection() async {
    guard configured else { status = "先填服务器地址和用户名"; return }
    guard !busy else { return }
    busy = true; status = "正在测试连接…"
    defer { busy = false }
    do {
      guard let url = fileURL else { throw DAVError.msg("服务器地址不对") }
      var req = request("PROPFIND", url: url)
      req.setValue("0", forHTTPHeaderField: "Depth")
      let (_, code) = try await send(req)
      switch code {
      case 200, 207: status = "连接正常（PROPFIND \(code)），云端已有备份文件"
      case 404: status = "连接正常（PROPFIND 404），云端还没有备份文件，立即备份即可创建"
      case 401, 403: status = human(code)
      default: status = "服务器有回应（PROPFIND \(code)）"
      }
    } catch {
      status = "测试失败：" + ((error as? DAVError)?.errorDescription ?? error.localizedDescription)
    }
  }

  // MARK: auto backup (debounced, hash-checked; never polls)
  func schedule() {
    guard configured, let store, store.data.demo != true else { return }
    timer?.cancel()
    let w = DispatchWorkItem { [weak self] in Task { await self?.autoBackup() } }
    timer = w
    DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: w)
  }
  private func autoBackup() async {
    guard configured, let store, store.data.demo != true, !busy else { return }
    guard let payload = try? encode(store.data), hash(payload) != lastHash else { return }
    await backupNow()
  }

  var summary: String {
    if !configured { return "未开启" }
    if lastAt > 0 { return "已备份 " + Date(timeIntervalSince1970: lastAt / 1000).formatted(.relative(presentation: .named)) }
    return "已开启"
  }
}

// MARK: - settings UI

struct WebDAVView: View {
  @EnvironmentObject var dav: WebDAV
  @State private var base = ""
  @State private var user = ""
  @State private var pass = ""
  @State private var path = ""
  @State private var loaded = false
  @State private var askRestore = false

  var body: some View {
    Form {
      Section {
        TextField("服务器地址", text: $base).textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
        TextField("用户名", text: $user).textInputAutocapitalization(.never).autocorrectionDisabled()
        SecureField("密码", text: $pass)
        TextField("文件路径", text: $path).textInputAutocapitalization(.never).autocorrectionDisabled()
        Button("填入 465871.xyz 预设") {
          base = "https://dav.465871.xyz/dav"
          path = "account-atlas/atlas.json"
        }
        Button("保存设置") {
          dav.saveConfig(base: base, user: user, path: path, password: pass)
        }
      } header: { Text("配置") } footer: {
        Text("密码只存在这台设备的钥匙串里，不进备份文件。地址填 WebDAV 根地址，文件路径是备份 JSON 在服务器上的位置。")
      }
      Section {
        if !dav.status.isEmpty {
          Text(dav.status).font(.system(size: 14)).foregroundStyle(.secondary)
        }
        Button {
          Task { await dav.backupNow() }
        } label: { Label("立即备份", systemImage: "arrow.up.circle") }.disabled(dav.busy)
        Button {
          Task { await dav.testConnection() }
        } label: { Label("测试连接", systemImage: "antenna.radiowaves.left.and.right") }.disabled(dav.busy)
        Button(role: .destructive) {
          askRestore = true
        } label: { Label("从云端恢复", systemImage: "arrow.down.circle") }.disabled(dav.busy)
      } header: { Text("备份与恢复") } footer: {
        Text("每次改动后约 2 秒自动备份（内容没变就不传）。恢复是整表替换：会先把当前本机数据自动存一份快照，再用云端那份覆盖本机。")
      }
      Section {
        Text("和「加密同步」的区别：WebDAV 是整份数据的明文备份，适合换机和防丢；加密同步是逐条合并、端到端加密，适合多台设备同时用。两者可以同时开，互不影响。")
          .font(.system(size: 13)).foregroundStyle(.secondary)
      }
    }
    .navigationTitle("WebDAV 备份").navigationBarTitleDisplayMode(.inline)
    .onAppear {
      if !loaded {
        base = dav.base; user = dav.user; pass = dav.password; path = dav.path
        loaded = true
      }
    }
    .confirmationDialog("从云端恢复？", isPresented: $askRestore, titleVisibility: .visible) {
      Button("用云端备份覆盖本机", role: .destructive) { Task { await dav.restoreNow() } }
      Button("取消", role: .cancel) {}
    } message: { Text("本机当前数据会先自动存一份快照，然后被云端备份整表替换。") }
  }
}
