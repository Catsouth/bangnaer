import SwiftUI
import UniformTypeIdentifiers
import UIKit

// MARK: - 智能导入 （绑哪儿第二批：自动识别导入）
//
// Behaviour mirrors the web app's recognition engine (src/index.html:
// identityFor / addCandidate / parseVault / parseCsv / parseText):
// - Vaultwarden / Bitwarden 未加密导出 JSON:每条 login 的 uris + username 就是现成绑定。
// - 浏览器密码 CSV(Chrome / Edge / Safari / Firefox):按表头取 url + username 两列。
// - 粘贴文本 / 剪贴板：正则认邮箱、手机号，目录扫描认服务名与域名（低置信默认不勾）。
// 密码零接触：Vaultwarden 的 login.password 键、CSV 的 password 列从不读取、从不存储。
// 先预览后落库：候选逐条可勾选、可改服务名、可改绑定的身份；新身份要单独勾选确认才建卡。
// 去重口径：同域名 + 同身份已存在 → 「已绑定」默认不勾、导入时跳过；同域名换身份 →
// 「新增绑定」（往已有服务上加身份，handle 为空时才补）；没有同域名服务 → 「新服务」。

struct ProposedIdentity: Identifiable, Equatable {
  let id = UUID()
  var type: String            // email | phone | login
  var provider: String? = nil // login only（识别目前只会产生 qq)
  var value: String
  var checked = true
  var kindName: String { type == "login" ? LoginProviders.name(provider) : type == "phone" ? "手机号" : "邮箱" }
  var color: String { type == "login" ? loginDefaultColor(provider ?? "wechat") : type == "phone" ? "#30d158" : "#0a84ff" }
}

enum CandIdentity: Equatable, Hashable {
  case none, existing(String), proposed(UUID)
}

enum CandStatus { case bound, newBinding, newService }

struct SmartCandidate: Identifiable {
  let id = UUID()
  var key: String
  var name: String
  var domain: String
  var category: String
  var username: String
  var identity: CandIdentity
  var why: String
  var lowConfidence: Bool
  var checked: Bool
}

private struct SmartImportError: Error { let message: String }

/// 示例数据不算数：演示模式下识别与去重都对着空库算，导入时先清示例（与网页版一致）。
private func smartBase(_ store: Store) -> AtlasData { store.data.demo == true ? AtlasData() : store.data }

private func identityKey(_ c: CandIdentity, _ proposed: [ProposedIdentity]) -> String {
  switch c {
  case .none: return ""
  case .existing(let id): return id
  case .proposed(let pid): return "new:" + (proposed.first { $0.id == pid }?.value.lowercased() ?? pid.uuidString)
  }
}

private func findAccount(domain: String, name: String, in accounts: [Account]) -> Account? {
  if !domain.isEmpty { return accounts.first { cleanDomain($0.domain) == domain } }
  return accounts.first { $0.name == name }
}

private func status(of c: SmartCandidate, base: AtlasData) -> CandStatus {
  guard let acc = findAccount(domain: c.domain, name: c.name, in: base.accounts) else { return .newService }
  if case .existing(let id) = c.identity, acc.identityIds.contains(id) { return .bound }
  return .newBinding
}

/// 网页版 identityFor:从一个用户名认出它是什么身份。含 @ 是邮箱；1 开头 11 位是手机号
/// （先于 QQ 判断，避免误判）；纯数字且来源是 qq.com 才是 QQ；其余像号码的按手机号。
@discardableResult
private func resolveIdentity(username: String, sourceDomain: String, base: AtlasData, proposed: inout [ProposedIdentity]) -> CandIdentity {
  let u = username.trimmingCharacters(in: .whitespaces)
  if u.isEmpty { return .none }
  let digits = u.filter { !$0.isWhitespace && $0 != "-" }
  var type: String? = nil
  var provider: String? = nil
  if u.contains("@") { type = "email" }
  else if digits.range(of: "^1\\d{10}$", options: .regularExpression) != nil { type = "phone" }
  else if digits.range(of: "^\\d{5,11}$", options: .regularExpression) != nil, sourceDomain == "qq.com" || sourceDomain.hasSuffix(".qq.com") { type = "login"; provider = "qq" }
  else if u.range(of: "^\\+?[\\d\\s-]{7,}$", options: .regularExpression) != nil { type = "phone" }
  guard let t = type else { return .none }
  let hit = base.identities.first(where: { $0.value.lowercased() == u.lowercased() && $0.type == t && (t != "login" || $0.provider == provider) })
    ?? base.identities.first(where: { $0.value.lowercased() == u.lowercased() })
  if let hit { return .existing(hit.id) }
  if let p = proposed.first(where: { $0.value.lowercased() == u.lowercased() }) { return .proposed(p.id) }
  let p = ProposedIdentity(type: t, provider: provider, value: u)
  proposed.append(p)
  return .proposed(p.id)
}

private func addCandidate(domain rawDomain: String, name rawName: String, username: String, why: String, low: Bool = false, base: AtlasData, candidates: inout [SmartCandidate], proposed: inout [ProposedIdentity]) {
  let preset = presetFor(name: "", domain: rawDomain)
  let domain = preset?.domain ?? cleanDomain(rawDomain)
  let name = preset?.name ?? (rawName.isEmpty ? domain : rawName)
  let idn = resolveIdentity(username: username, sourceDomain: domain, base: base, proposed: &proposed)
  let key = domain + "|" + identityKey(idn, proposed) + "|" + username
  if candidates.contains(where: { $0.key == key }) { return }
  var cand = SmartCandidate(key: key, name: name, domain: domain, category: preset?.category ?? "其他",
                            username: username, identity: idn, why: why, lowConfidence: low, checked: true)
  cand.checked = !low && status(of: cand, base: base) != .bound
  candidates.append(cand)
}

private func urlHost(_ uri: String) -> String {
  let s = uri.contains("://") ? uri : "https://" + uri
  guard let h = URL(string: s)?.host else { return "" }
  return cleanDomain(h)
}

// MARK: - parsers

/// Vaultwarden / Bitwarden 未加密导出。只读 login.username 与 login.uris,password 键不碰。
private func parseVaultJSON(_ data: Data, base: AtlasData, candidates: inout [SmartCandidate], proposed: inout [ProposedIdentity]) throws -> Int {
  let obj: Any
  do { obj = try JSONSerialization.jsonObject(with: data) } catch { throw SmartImportError(message: "这个文件不是有效的 JSON。") }
  if let dict = obj as? [String: Any] {
    if (dict["encrypted"] as? Bool) == true {
      throw SmartImportError(message: "这是加密导出，读不了。请在 Vaultwarden / Bitwarden 里重新导出，格式选「未加密 JSON」再试。")
    }
    if dict["identities"] != nil || dict["accounts"] != nil || dict["links"] != nil {
      throw SmartImportError(message: "这是绑哪儿自己的备份文件，请回设置用「导入备份」。")
    }
  }
  let items: [Any]
  if let dict = obj as? [String: Any], let arr = dict["items"] as? [Any] { items = arr }
  else if let arr = obj as? [Any] { items = arr }
  else { throw SmartImportError(message: "没找到 items，这不像 Vaultwarden / Bitwarden 的导出文件。") }
  let before = candidates.count
  for raw in items {
    guard let item = raw as? [String: Any], let login = item["login"] as? [String: Any] else { continue }
    let user = (login["username"] as? String) ?? ""
    let itemName = (item["name"] as? String) ?? ""
    var uris: [String] = []
    if let arr = login["uris"] as? [Any] {
      for u in arr {
        if let s = u as? String { uris.append(s) }
        else if let d = u as? [String: Any], let s = (d["uri"] as? String) ?? (d["url"] as? String) { uris.append(s) }
      }
    } else if let arr = login["urls"] as? [Any] {
      for u in arr { if let s = u as? String { uris.append(s) } }
    }
    for uri in uris {
      let host = urlHost(uri)
      if host.isEmpty { continue }
      addCandidate(domain: host, name: itemName, username: user,
                   why: "Vaultwarden 条目「\(itemName.isEmpty ? host : itemName)」",
                   base: base, candidates: &candidates, proposed: &proposed)
    }
  }
  return candidates.count - before
}

/// 规范 CSV 分词：处理引号字段、字段内逗号与 "" 转义、CRLF。
private func csvRows(_ text: String) -> [[String]] {
  var rows: [[String]] = []
  var row: [String] = []
  var field = ""
  var inQuotes = false
  let chars = Array(text)
  var i = 0
  while i < chars.count {
    let ch = chars[i]
    if inQuotes {
      if ch == "\"" {
        if i + 1 < chars.count && chars[i + 1] == "\"" { field.append("\""); i += 1 } else { inQuotes = false }
      } else { field.append(ch) }
    } else if ch == "\"" { inQuotes = true }
    else if ch == "," { row.append(field); field = "" }
    else if ch == "\n" || ch == "\r" {
      if ch == "\r" && i + 1 < chars.count && chars[i + 1] == "\n" { i += 1 }
      row.append(field); field = ""; rows.append(row); row = []
    } else { field.append(ch) }
    i += 1
  }
  if !field.isEmpty || !row.isEmpty { row.append(field); rows.append(row) }
  return rows.filter { !$0.allSatisfy { $0.trimmingCharacters(in: .whitespaces).isEmpty } }
}

/// 浏览器密码 CSV：有表头按表头取 url/username 列（password 列不取），没表头退回网页版的列猜测。
private func parseCSVText(_ text: String, base: AtlasData, candidates: inout [SmartCandidate], proposed: inout [ProposedIdentity]) throws -> Int {
  let rows = csvRows(text)
  guard rows.count >= 2 else { throw SmartImportError(message: "这个 CSV 里没认出数据行。") }
  let header = rows[0].map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
  func col(_ names: [String], contains needle: String? = nil) -> Int? {
    if let i = header.firstIndex(where: { names.contains($0) }) { return i }
    if let needle { return header.firstIndex { $0.contains(needle) } }
    return nil
  }
  let urlI = col(["url", "website", "site", "uri", "login url", "web site"], contains: "url")
  let userI = col(["username", "user", "login", "account", "login name", "email"], contains: "user")
  let nameI = col(["name", "title", "site name"])
  let before = candidates.count
  var sawURL = false
  for row in rows.dropFirst() {
    let url: String, user: String, nm: String
    if let ui = urlI {
      url = ui < row.count ? row[ui] : ""
      user = (userI.flatMap { $0 < row.count ? row[$0] : nil }) ?? ""
      nm = (nameI.flatMap { $0 < row.count ? row[$0] : nil }) ?? ""
    } else {
      url = row.first(where: { $0.range(of: "\\S+\\.\\S+", options: .regularExpression) != nil && ($0.contains(":") || $0.contains("/")) }) ?? (row.count > 1 ? row[1] : "")
      user = row.first(where: { $0.contains("@") }) ?? row.first(where: { $0.range(of: "^\\+?[\\d-]{7,}$", options: .regularExpression) != nil }) ?? ""
      nm = ""
    }
    let host = urlHost(url)
    if host.isEmpty { continue }
    sawURL = true
    addCandidate(domain: host, name: nm, username: user, why: "密码 CSV", base: base, candidates: &candidates, proposed: &proposed)
  }
  if !sawURL { throw SmartImportError(message: "没在这个 CSV 里找到网址，确认是浏览器导出的密码表？") }
  return candidates.count - before
}

private func regexFind(_ pattern: String, in text: String, caseInsensitive: Bool = false) -> [String] {
  guard let re = try? NSRegularExpression(pattern: pattern, options: caseInsensitive ? [.caseInsensitive] : []) else { return [] }
  let range = NSRange(text.startIndex..., in: text)
  return re.matches(in: text, range: range).compactMap { m in Range(m.range, in: text).map { String(text[$0]) } }
}

/// 网页版 parseText：邮箱/手机号先进身份候选；服务名与域名命中只算低置信线索。
private func parseFreeText(_ text: String, base: AtlasData, candidates: inout [SmartCandidate], proposed: inout [ProposedIdentity]) -> Int {
  let before = candidates.count
  for e in regexFind("[\\w.+-]+@[\\w-]+(?:\\.[\\w-]+)*\\.(?:com|cn|net|org|io|ai|dev|so|tv|cc|co|me|info|xyz|top|vip|club|site|online|gov\\.cn|edu\\.cn|com\\.cn|net\\.cn|org\\.cn)", in: text, caseInsensitive: true) {
    resolveIdentity(username: e, sourceDomain: "", base: base, proposed: &proposed)
  }
  for p in regexFind("(?:\\+86)?1[3-9]\\d{9}", in: text) {
    resolveIdentity(username: p.hasPrefix("+86") ? String(p.dropFirst(3)) : p, sourceDomain: "", base: base, proposed: &proposed)
  }
  let lower = text.lowercased()
  for p in Presets.all where lower.contains(p.domain) || (p.name.count >= 2 && text.contains(p.name)) {
    addCandidate(domain: p.domain, name: p.name, username: "", why: "文本里出现了「\(p.name)」", low: true, base: base, candidates: &candidates, proposed: &proposed)
  }
  for d0 in regexFind("(?:[a-z0-9-]+\\.)+(?:com|cn|net|org|io|ai|dev|so|tv|cc)", in: text, caseInsensitive: true) {
    let d = cleanDomain(d0)
    if presetFor(name: "", domain: d) == nil {
      addCandidate(domain: d, name: d, username: "", why: "文本里的域名", low: true, base: base, candidates: &candidates, proposed: &proposed)
    }
  }
  return candidates.count - before
}

// MARK: - view

struct SmartImportView: View {
  @Environment(Store.self) var store
  @State private var candidates: [SmartCandidate] = []
  @State private var proposed: [ProposedIdentity] = []
  @State private var pasteText = ""
  @State private var picking = false
  @State private var feedback = ""
  @State private var feedbackBad = false
  @State private var hasClip = false

  var base: AtlasData { smartBase(store) }
  var checkedCount: Int { candidates.filter(\.checked).count + proposed.filter(\.checked).count }

  var body: some View {
    Form {
      Section {
        Button { picking = true } label: { Label("选择导出文件", systemImage: "doc.badge.plus") }
      } header: { Text("从文件导入") } footer: {
        Text("Vaultwarden / Bitwarden 选「未加密 JSON」导出；浏览器密码表是 CSV。只读网址和账号名，密码一律不读、不用、不存在这里。")
      }
      Section {
        TextEditor(text: $pasteText).frame(minHeight: 90)
        Button("扫描这段文本") { scan(pasteText) }.disabled(pasteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        if hasClip {
          Button { loadClipboard() } label: { Label("载入剪贴板并识别", systemImage: "doc.on.clipboard") }
        }
      } header: { Text("粘贴文本") } footer: {
        Text("把注册邮件、短信或任何一段文字贴进来，自动认出邮箱、手机号和服务。靠文本猜的会标「不太确定」，默认不勾。")
      }
      if !feedback.isEmpty {
        Section { Text(feedback).foregroundStyle(feedbackBad ? Color.red : Color.secondary) }
      }
      if !proposed.isEmpty {
        Section {
          ForEach($proposed) { $p in proposedRow($p) }
        } header: { Text("新身份卡") } footer: { Text("从导入数据里的用户名认出来的。勾选后才会建卡；不勾的话，用到它的绑定会被跳过。") }
      }
      if !candidates.isEmpty {
        Section {
          HStack {
            Button("全选") { setAll(true) }
            Spacer()
            Button("只选高置信") { setHighOnly() }
            Spacer()
            Button("全不选") { setAll(false) }
          }.font(.system(size: 14))
        }
        Section {
          ForEach($candidates) { $c in candidateRow($c) }
        } header: { Text("服务与绑定") }
        Section {
          Button { applyImport() } label: {
            HStack { Spacer(); Text("把勾选的加进来（\(checkedCount)）").bold(); Spacer() }
          }.disabled(checkedCount == 0)
          Button("清空候选", role: .destructive) { candidates = []; proposed = []; feedback = "" }
        }
      }
    }
    .navigationTitle("智能导入").navigationBarTitleDisplayMode(.inline)
    .onAppear { hasClip = UIPasteboard.general.hasStrings }
    .fileImporter(isPresented: $picking, allowedContentTypes: [.json, .commaSeparatedText, .plainText, .text, .data]) { r in
      guard case .success(let url) = r else { return }
      let scoped = url.startAccessingSecurityScopedResource()
      defer { if scoped { url.stopAccessingSecurityScopedResource() } }
      guard let data = try? Data(contentsOf: url) else { setFeedback("读不到这个文件。", bad: true); return }
      loadFile(data: data, filename: url.lastPathComponent)
    }
  }

  // MARK: rows

  @ViewBuilder func proposedRow(_ p: Binding<ProposedIdentity>) -> some View {
    let v = p.wrappedValue
    HStack(spacing: 10) {
      checkButton(on: v.checked) { p.wrappedValue.checked.toggle() }
      IdentityGlyph(identity: Identity(type: v.type, value: v.value, label: "", color: v.color, provider: v.provider), size: 12)
        .foregroundStyle(.white).frame(width: 36, height: 24)
        .background(skinGradient(v.color), in: CardShape(sim: v.type == "phone"))
      VStack(alignment: .leading, spacing: 1) {
        Text(v.value).font(.system(size: 15, weight: .semibold)).lineLimit(1)
        Text("新\(v.kindName)卡 · 从导入数据里的用户名识别").font(.system(size: 12)).foregroundStyle(.secondary)
      }
    }.padding(.vertical, 2)
  }

  @ViewBuilder func candidateRow(_ c: Binding<SmartCandidate>) -> some View {
    let v = c.wrappedValue
    let st = status(of: v, base: base)
    HStack(alignment: .top, spacing: 10) {
      checkButton(on: v.checked) { c.wrappedValue.checked.toggle() }.padding(.top, 2)
      VStack(alignment: .leading, spacing: 4) {
        HStack(spacing: 8) {
          AppIcon(name: v.name, domain: v.domain, size: 30)
          TextField("服务名", text: c.name).font(.system(size: 15, weight: .semibold))
          statusBadge(st)
        }
        if !v.domain.isEmpty { Text(v.domain).font(.system(size: 12)).foregroundStyle(.secondary) }
        if !v.username.isEmpty { Text("账号 \(v.username)").font(.system(size: 12)).foregroundStyle(.secondary) }
        Text(v.why).font(.system(size: 12)).foregroundStyle(.secondary)
        if v.lowConfidence { Text("不太确定").font(.system(size: 12, weight: .medium)).foregroundStyle(.orange) }
        HStack(spacing: 6) {
          Text("绑到").font(.system(size: 12)).foregroundStyle(.secondary)
          Picker("绑到哪个身份", selection: c.identity) {
            Text("先不绑").tag(CandIdentity.none)
            ForEach(base.identities) { i in Text(store.title(i)).tag(CandIdentity.existing(i.id)) }
            ForEach(proposed) { p in Text(p.value + "（新）").tag(CandIdentity.proposed(p.id)) }
          }.pickerStyle(.menu).labelsHidden()
        }
      }
    }.padding(.vertical, 2)
  }

  @ViewBuilder func statusBadge(_ st: CandStatus) -> some View {
    switch st {
    case .bound:
      Text("已绑定").font(.system(size: 11, weight: .medium)).padding(.horizontal, 6).padding(.vertical, 2)
        .background(Color.secondary.opacity(0.15), in: Capsule()).foregroundStyle(.secondary)
    case .newBinding:
      Text("新增绑定").font(.system(size: 11, weight: .medium)).padding(.horizontal, 6).padding(.vertical, 2)
        .background(Color.blue.opacity(0.15), in: Capsule()).foregroundStyle(.blue)
    case .newService:
      Text("新服务").font(.system(size: 11, weight: .medium)).padding(.horizontal, 6).padding(.vertical, 2)
        .background(Color.green.opacity(0.15), in: Capsule()).foregroundStyle(.green)
    }
  }

  func checkButton(on: Bool, _ fn: @escaping () -> Void) -> some View {
    Button(action: fn) {
      Image(systemName: on ? "checkmark.circle.fill" : "circle")
        .font(.system(size: 22))
        .foregroundStyle(on ? Color.accentColor : Color.secondary.opacity(0.5))
    }.buttonStyle(.plain)
  }

  // MARK: actions

  func setFeedback(_ s: String, bad: Bool) { feedback = s; feedbackBad = bad }

  func setAll(_ on: Bool) {
    for k in candidates.indices { candidates[k].checked = on && status(of: candidates[k], base: base) != .bound }
    for k in proposed.indices { proposed[k].checked = on }
  }
  func setHighOnly() {
    for k in candidates.indices { candidates[k].checked = !candidates[k].lowConfidence && status(of: candidates[k], base: base) != .bound }
    for k in proposed.indices { proposed[k].checked = true }
  }

  func loadFile(data: Data, filename: String) {
    let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .utf16) ?? ""
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    do {
      let n: Int
      if filename.lowercased().hasSuffix(".csv") || (!trimmed.hasPrefix("{") && !trimmed.hasPrefix("[")) {
        n = try parseCSVText(text, base: base, candidates: &candidates, proposed: &proposed)
      } else {
        n = try parseVaultJSON(data, base: base, candidates: &candidates, proposed: &proposed)
      }
      setFeedback(n > 0 ? "识别到 \(n) 条候选，核对后点最下面导入。" : "没识别到新东西，可能都已经记录过了。", bad: false)
    } catch let e as SmartImportError {
      setFeedback(e.message, bad: true)
    } catch {
      setFeedback("解析失败：\(error.localizedDescription)", bad: true)
    }
  }

  func scan(_ text: String) {
    let beforeC = candidates.count, beforeP = proposed.count
    _ = parseFreeText(text, base: base, candidates: &candidates, proposed: &proposed)
    if candidates.count > beforeC || proposed.count > beforeP {
      setFeedback("识别完成，往下核对候选。", bad: false)
    } else {
      setFeedback("没从这段文本里认出新东西。", bad: false)
    }
  }

  func loadClipboard() {
    guard let s = UIPasteboard.general.string, !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      setFeedback("剪贴板是空的，先复制一段再点。", bad: true)
      return
    }
    pasteText = s
    scan(s)
  }

  /// One mutate for the whole batch: undo, stamps and tombstones keep their semantics.
  /// New identities are created only from checked proposals; a checked link whose
  /// identity proposal was unchecked (or never picked) is skipped and counted.
  func applyImport() {
    var created: [UUID: String] = [:]
    var newIds: [Identity] = []
    for p in proposed where p.checked {
      if let hit = base.identities.first(where: { $0.value.lowercased() == p.value.lowercased() })
        ?? newIds.first(where: { $0.value.lowercased() == p.value.lowercased() }) {
        created[p.id] = hit.id
      } else {
        let i = Identity(type: p.type, value: p.value, label: "自动识别", color: p.color, provider: p.provider)
        newIds.append(i)
        created[p.id] = i.id
      }
    }
    var accs = base.accounts
    var addedSvc = 0, addedBind = 0, skipBound = 0, skipNoIdn = 0
    for c in candidates where c.checked {
      if status(of: c, base: base) == .bound { skipBound += 1; continue }
      let iid: String?
      switch c.identity {
      case .none: iid = nil
      case .existing(let id): iid = id
      case .proposed(let pid): iid = created[pid]
      }
      guard let iid else { skipNoIdn += 1; continue }
      if let k = accs.firstIndex(where: { !c.domain.isEmpty ? cleanDomain($0.domain) == c.domain : $0.name == c.name }) {
        if accs[k].identityIds.contains(iid) { skipBound += 1; continue }
        accs[k].identityIds.append(iid)
        if (accs[k].handle ?? "").isEmpty && !c.username.isEmpty { accs[k].handle = c.username }
        addedBind += 1
      } else {
        accs.append(Account(name: c.name, domain: c.domain, category: c.category, identityIds: [iid], handle: c.username.isEmpty ? nil : c.username))
        addedSvc += 1
      }
    }
    var parts: [String] = []
    if addedSvc > 0 { parts.append("新增 \(addedSvc) 个服务") }
    if addedBind > 0 { parts.append("新增 \(addedBind) 条绑定") }
    if !newIds.isEmpty { parts.append("新建 \(newIds.count) 张身份卡") }
    var msg = parts.isEmpty ? "没有新增" : "已导入：" + parts.joined(separator: "、")
    if skipBound > 0 { msg += "；跳过已绑定 \(skipBound) 条" }
    if skipNoIdn > 0 { msg += "；\(skipNoIdn) 条没选身份、已跳过" }
    if !newIds.isEmpty || addedSvc > 0 || addedBind > 0 {
      let idsToAdd = newIds, finalAccs = accs
      store.mutate(msg) { s in
        if s.demo == true { s.identities = []; s.accounts = [] }
        s.identities.append(contentsOf: idsToAdd)
        s.accounts = finalAccs
      }
    }
    setFeedback(msg, bad: false)
    candidates = []
    proposed = []
  }
}
