import SwiftUI
import UniformTypeIdentifiers

struct BackupDoc: FileDocument {
  static var readableContentTypes: [UTType] { [.json] }
  var data: Data
  init(data: Data) { self.data = data }
  init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
  func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

struct SettingsSheet: View {
  /// true when shown as the fourth bottom-bar tab instead of a sheet (patch batch):
  /// no 完成 button then — there is nothing to dismiss.
  var embedded = false
  @Environment(Store.self) var store
  @EnvironmentObject var sync: Sync
  @EnvironmentObject var dav: WebDAV
  @Environment(AppLock.self) var lock
  @Environment(\.dismiss) var dismiss
  @State private var exporting = false
  @State private var importing = false
  @State private var askWipe = false
  @State private var askDemo = false
  @State private var doc = BackupDoc(data: Data())

  var body: some View {
    NavigationStack {
      Form {
        Section {
          NavigationLink { SyncView() } label: {
            HStack {
              Label("加密同步", systemImage: "icloud")
              Spacer()
              Text(syncStatus).foregroundStyle(.secondary).font(.system(size: 14))
            }
          }
          NavigationLink { WebDAVView() } label: {
            HStack {
              Label("WebDAV 备份", systemImage: "externaldrive.badge.icloud")
              Spacer()
              Text(dav.summary).foregroundStyle(.secondary).font(.system(size: 14))
            }
          }
        } footer: { Text("加密同步是多设备逐条合并；WebDAV 是整份明文备份。两者可以同时开。") }
        Section {
          Toggle(isOn: Binding(get: { store.privacy }, set: { v in store.privacy = v }).animation(Motion.smooth)) { Label("隐藏号码", systemImage: "eye.slash") }
          Picker(selection: Binding(get: { store.theme }, set: { ThemeFX.set($0, store: store) })) {
            Text("深色").tag("dark")
            Text("浅色").tag("light")
            Text("跟随系统").tag("system")
          } label: { Label("外观", systemImage: "circle.lefthalf.filled") }
          NavigationLink { OrderView() } label: { Label("调整卡片顺序", systemImage: "arrow.up.arrow.down") }
        }
        Section {
          NavigationLink { LockSettingsView() } label: {
            HStack {
              Label("屏幕锁", systemImage: "lock")
              Spacer()
              Text(lock.enabled ? "已开启" : "未开启").foregroundStyle(.secondary).font(.system(size: 14))
            }
          }
        }
        Section {
          NavigationLink { RebindView() } label: { Label("换绑清单", systemImage: "arrow.left.arrow.right") }
          NavigationLink { HealthView() } label: { Label("账号体检", systemImage: "stethoscope") }
        } footer: { Text("换了手机号或邮箱时，用换绑清单逐个确认新绑定；账号体检帮你找出重复、遗漏和已失效的记录。") }
        Section {
          NavigationLink { TrashView() } label: {
            HStack {
              Label("回收站", systemImage: "trash")
              Spacer()
              if !store.data.trash.isEmpty {
                Text("\(store.data.trash.count) 项").foregroundStyle(.secondary).font(.system(size: 14))
              }
            }
          }
          NavigationLink { SmartImportView() } label: { Label("智能导入", systemImage: "sparkles") }
          Button { doc = BackupDoc(data: store.backupJSON()); exporting = true } label: { Label("导出备份", systemImage: "square.and.arrow.up") }
          Button { importing = true } label: { Label("导入备份", systemImage: "square.and.arrow.down") }
          if !sync.on {
            Button { askDemo = true } label: { Label("载入示例", systemImage: "text.badge.plus") }
          }
        } footer: { Text("备份是 JSON 文件，和网页版通用。智能导入从密码管理器导出、浏览器密码表或一段文字里认出服务和绑定关系，只读网址和账号名，不读密码。") }
        Section {
          Link(destination: URL(string: "https://github.com/Catsouth/bangnaer/releases/latest")!) {
            HStack {
              Label("下载新版本", systemImage: "arrow.up.forward.app")
              Spacer()
              Text((Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String).map { "当前 " + $0 } ?? "").foregroundStyle(.secondary)
            }
          }
        } footer: { Text("在 GitHub Releases 下载，直接覆盖安装，数据不会丢失。") }
        Section {
          Button(role: .destructive) { askWipe = true } label: { Label("清空全部数据", systemImage: "trash") }
        }
        Section {
          VStack(spacing: 6) {
            Text("绑哪儿").font(.system(size: 15, weight: .semibold))
            Text("不保存任何密码 · 数据只在本机、你自己的 WebDAV 和私有 Gist").font(.system(size: 12)).foregroundStyle(.secondary)
          }.frame(maxWidth: .infinity)
        }.listRowBackground(Color.clear)
      }
      .tint(.accentColor)
      // as a tab, the floating bar (taller since 第二轮细化） overlays the form's
      // tail — give the scroll content room to clear it; as a sheet there is no
      // bar, so no margin then
      .contentMargins(.bottom, embedded ? 88 : 0, for: .scrollContent)
      .navigationTitle("设置").navigationBarTitleDisplayMode(.inline)
      .toolbar {
        if !embedded {
          ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() }.bold() }
        }
      }
      .toolbar(.hidden, for: .tabBar)
      .fileExporter(isPresented: $exporting, document: doc, contentType: .json, defaultFilename: "账号备份-\(Date().formatted(.iso8601.year().month().day()))") { r in
        if case .success = r { store.show("备份已导出") }
      }
      // 第十四轮： .fileImporter 弃用（见 DocPicker.swift）——第十三轮
      // 类型修改已让文件不再置灰，但真机点中后选择器不关、回调不走，
      // 改走手写 UIDocumentPickerViewController（[UTType.item] + asCopy）。
      // 回调 URL 是沙盒内副本，直接 Data 读取，不再套 security-scoped；
      // 是不是备份仍由 importBackup 内容校验决定，口径不变。
      .docPickerSheet(isPresented: $importing) { url in
        guard let d = try? Data(contentsOf: url) else { store.show("读不到这个文件"); return }
        if store.importBackup(d) { dismiss() } else { store.show("这不是绑哪儿的备份文件") }
      }
      .confirmationDialog("清空全部数据？", isPresented: $askWipe, titleVisibility: .visible) {
        Button("清空全部数据", role: .destructive) {
          store.mutate("已清空") { s in s.identities = []; s.accounts = []; s.trash = [] }
          store.setKind(store.kind); dismiss()
        }
      } message: { Text(sync.on ? "所有邮箱、手机号和网站记录都会删除，开了同步的其他设备也会一起清空。建议先导出备份。" : "所有邮箱、手机号和网站记录都会从这台设备上删除。建议先导出备份。") }
      // Loading the demo replaces the whole data set (Store.demo()),
      // so it gets the same confirm-first treatment as wiping （第十三轮）:
      // one tap used to throw the user's real records away with no warning.
      .confirmationDialog("载入示例数据？", isPresented: $askDemo, titleVisibility: .visible) {
        Button("载入示例", role: .destructive) {
          store.mutate("已载入示例") { s in s = Store.demo() }; store.data.demo = true; store.persist(); store.setKind("email")
        }
        Button("取消", role: .cancel) {}
      } message: { Text("示例数据会替换当前全部记录，现在的邮箱、手机号和网站都会被覆盖。想保留的话，先导出一份备份。") }
    }
  }
  var syncStatus: String {
    switch sync.state {
    case "off": return "未开启"
    case "syncing": return "同步中…"
    case "error": return "出错了"
    default: return sync.at > 0 ? "已同步 " + Date(timeIntervalSince1970: sync.at / 1000).formatted(.relative(presentation: .named)) : "已开启"
    }
  }
}

struct OrderView: View {
  @Environment(Store.self) var store
  var body: some View {
    List {
      group("邮箱") { $0.type == "email" }
      group("手机号") { $0.type == "phone" }
      ForEach(LoginProviders.all, id: \.key) { p in
        group(p.name) { $0.isLogin && $0.provider == p.key }
      }
      group("登录账号") { $0.isLogin && LoginProviders.info($0.provider) == nil }
    }
    .environment(\.editMode, .constant(.active))
    .navigationTitle("卡片顺序").navigationBarTitleDisplayMode(.inline)
  }
  @ViewBuilder func group(_ title: String, match: @escaping (Identity) -> Bool) -> some View {
    let list = store.data.identities.filter(match)
    if !list.isEmpty {
      Section {
        ForEach(list) { i in
          HStack(spacing: 12) {
            IdentityGlyph(identity: i, size: 13).foregroundStyle(.white).frame(width: 46, height: 30)
              .background(skinGradient(i.color), in: CardShape(sim: i.isPhone))
              .shadow(color: Color(hex: i.color).opacity(0.35), radius: 5, y: 2)
            VStack(alignment: .leading, spacing: 1) {
              Text(store.title(i)).font(.system(size: 16, weight: .medium))
              if !i.label.isEmpty { Text(store.display(i)).font(.system(size: 13)).foregroundStyle(.secondary) }
            }
          }.padding(.vertical, 2)
        }
        .onMove { from, to in move(match, from, to) }
      } header: { Text(title) } footer: { if title == lastTitle { Text("拖动右侧把手排序，排在第一位的卡会在卡包里最先出现。") } }
    }
  }
  /// the footer hint goes under the last group shown
  var lastTitle: String {
    var titles: [String] = []
    if store.data.identities.contains(where: { $0.type == "email" }) { titles.append("邮箱") }
    if store.data.identities.contains(where: { $0.type == "phone" }) { titles.append("手机号") }
    for p in LoginProviders.all where store.data.identities.contains(where: { $0.isLogin && $0.provider == p.key }) { titles.append(p.name) }
    if store.data.identities.contains(where: { $0.isLogin && LoginProviders.info($0.provider) == nil }) { titles.append("登录账号") }
    return titles.last ?? "邮箱"
  }
  /// reorder only the slots this group occupies, so other groups keep their places
  func move(_ match: @escaping (Identity) -> Bool, _ from: IndexSet, _ to: Int) {
    store.mutate(nil) { s in
      let slots = s.identities.indices.filter { match(s.identities[$0]) }
      var list = slots.map { s.identities[$0] }
      list.move(fromOffsets: from, toOffset: to)
      for k in list.indices { list[k].order = Double(k) }
      for (slot, el) in zip(slots, list) { s.identities[slot] = el }
    }
  }
}

struct SyncView: View {
  @Environment(Store.self) var store
  @EnvironmentObject var sync: Sync
  @State private var prov = "gitee"
  @State private var token = ""
  @State private var pass = ""
  @State private var busy = false
  @State private var error = ""
  @State private var askOff = false

  var body: some View {
    Form {
      if sync.on {
        Section {
          HStack {
            Image(systemName: sync.state == "error" ? "exclamationmark.icloud.fill" : sync.state == "syncing" ? "arrow.triangle.2.circlepath.icloud.fill" : "checkmark.icloud.fill")
              .font(.system(size: 30)).foregroundStyle(sync.state == "error" ? Color.orange : Color.accentColor)
              .symbolEffect(.pulse, isActive: sync.state == "syncing")
            VStack(alignment: .leading, spacing: 2) {
              Text(sync.state == "error" ? sync.err : sync.state == "syncing" ? "正在同步…" : "已开启加密同步").font(.system(size: 16, weight: .semibold))
              Text("存放在 " + (sync.provider == "gitee" ? "Gitee" : "GitHub") + " 私有 Gist" + (sync.at > 0 ? " · " + Date(timeIntervalSince1970: sync.at / 1000).formatted(date: .omitted, time: .shortened) : ""))
                .font(.system(size: 13)).foregroundStyle(.secondary)
            }
          }.padding(.vertical, 4)
          Button("立即同步") { Task { await sync.run() } }.disabled(sync.state == "syncing")
        }
        Section { Button("关闭同步", role: .destructive) { askOff = true } } footer: { Text("关闭后这台设备不再同步，云端和本机的数据都会保留。") }
      } else {
        Section {
          Picker("存放在", selection: $prov) {
            Text("Gitee · 国内直连").tag("gitee")
            Text("GitHub").tag("github")
          }.pickerStyle(.inline).labelsHidden()
        } header: { Text("存放在") }
        Section {
          SecureField(prov == "gitee" ? "Gitee 私人令牌（勾选 gists）" : "GitHub 令牌（gist 权限）", text: $token).textInputAutocapitalization(.never).autocorrectionDisabled()
          SecureField("同步密码", text: $pass)
          Link(prov == "gitee" ? "去 Gitee 创建令牌" : "去 GitHub 创建令牌", destination: URL(string: prov == "gitee" ? "https://gitee.com/profile/personal_access_tokens/new" : "https://github.com/settings/tokens/new?scopes=gist&description=绑哪儿")!)
        } footer: { Text("数据先用同步密码加密，再存进你自己的私有 Gist，别人看不到内容。每台设备填同一个令牌和同步密码即可。同步密码忘了就解不开。") }
        if !error.isEmpty { Section { Text(error).foregroundStyle(.red) } }
        Section {
          Button {
            busy = true; error = ""
            Task {
              do {
                let found = try await sync.enable(token: token, pass: pass, prov: prov)
                store.setKind(store.kind)
                store.show(found ? "已连接，云端数据已合并" : "同步已开启")
              } catch { self.error = (error as? SyncError)?.errorDescription ?? error.localizedDescription }
              busy = false
            }
          } label: {
            HStack {
              Spacer()
              if busy { ProgressView() } else { Text("开启同步").bold() }
              Spacer()
            }
          }.disabled(busy || token.trimmingCharacters(in: .whitespaces).isEmpty || pass.count < 4)
        }
      }
    }
    .navigationTitle("加密同步").navigationBarTitleDisplayMode(.inline)
    .confirmationDialog("关闭同步？", isPresented: $askOff, titleVisibility: .visible) {
      Button("关闭同步", role: .destructive) { sync.disable() }
    }
  }
}
