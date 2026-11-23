import SwiftUI

// MARK: - 账号体检 （绑哪儿第三批，检查项对齐网页版并按原生数据模型扩展）
//
// Read-only report over a data snapshot: nothing here mutates. Each check lists its
// offenders; tapping one opens the filtered list, and tapping an item there jumps to
// its detail sheet. The computation is a pure function of AtlasData (no Store access),
// so it can run anywhere without actor-isolation concerns.

struct HealthReport {
  var dupBindings: [Account] = []      // same identity listed twice (or more) on one service
  var unboundAccounts: [Account] = []  // services bound to nothing
  var idleIdentities: [Identity] = []  // identity cards no service uses
  var inactiveAccounts: [Account] = [] // status stopped / cancelled
  var noDomainAccounts: [Account] = [] // no domain (前往登录 has nowhere to go)
  var dupIdentities: [Identity] = []   // cards sharing a value (same type, login also same provider)

  var issueCount: Int {
    dupBindings.count + unboundAccounts.count + idleIdentities.count
      + inactiveAccounts.count + noDomainAccounts.count + dupIdentities.count
  }

  static func build(_ d: AtlasData) -> HealthReport {
    var r = HealthReport()
    let usedIDs = Set(d.accounts.flatMap(\.identityIds))
    for a in d.accounts {
      if Set(a.identityIds).count != a.identityIds.count { r.dupBindings.append(a) }
      if a.identityIds.isEmpty { r.unboundAccounts.append(a) }
      if a.bindStatusKey != "active" { r.inactiveAccounts.append(a) }
      if cleanDomain(a.domain).isEmpty { r.noDomainAccounts.append(a) }
    }
    for i in d.identities where !usedIDs.contains(i.id) { r.idleIdentities.append(i) }
    var groups: [String: [Identity]] = [:]
    for i in d.identities {
      let v = i.value.trimmingCharacters(in: .whitespaces).lowercased()
      let key = i.isLogin ? "login|" + (i.provider ?? "") + "|" + v : i.type + "|" + v
      groups[key, default: []].append(i)
    }
    r.dupIdentities = groups.values.filter { $0.count > 1 }
      .flatMap { $0 }
      .sorted { $0.value.localizedStandardCompare($1.value) == .orderedAscending }
    let byName: (Account, Account) -> Bool = { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    r.dupBindings.sort(by: byName); r.unboundAccounts.sort(by: byName)
    r.inactiveAccounts.sort(by: byName); r.noDomainAccounts.sort(by: byName)
    return r
  }
}

enum HealthKind: String, CaseIterable {
  case dupBindings, unboundAccounts, idleIdentities, inactiveAccounts, noDomainAccounts, dupIdentities
  var title: String {
    switch self {
    case .dupBindings: return "重复绑定同一身份的服务"
    case .unboundAccounts: return "没有绑定任何身份的服务"
    case .idleIdentities: return "没有绑任何服务的身份卡"
    case .inactiveAccounts: return "已停用 / 已注销的服务"
    case .noDomainAccounts: return "缺少域名的服务"
    case .dupIdentities: return "值重复的身份卡"
    }
  }
  var icon: String {
    switch self {
    case .dupBindings: return "square.on.square"
    case .unboundAccounts: return "app.dashed"
    case .idleIdentities: return "person.crop.rectangle"
    case .inactiveAccounts: return "pause.circle"
    case .noDomainAccounts: return "globe"
    case .dupIdentities: return "person.2"
    }
  }
  func count(_ r: HealthReport) -> Int {
    switch self {
    case .dupBindings: return r.dupBindings.count
    case .unboundAccounts: return r.unboundAccounts.count
    case .idleIdentities: return r.idleIdentities.count
    case .inactiveAccounts: return r.inactiveAccounts.count
    case .noDomainAccounts: return r.noDomainAccounts.count
    case .dupIdentities: return r.dupIdentities.count
    }
  }
}

struct HealthView: View {
  @Environment(Store.self) var store
  var body: some View {
    let report = HealthReport.build(store.data)
    List {
      Section {
        if report.issueCount == 0 {
          Label("一切正常", systemImage: "checkmark.circle.fill")
            .font(.system(size: 16, weight: .semibold)).foregroundStyle(.green)
          Text("没有重复绑定、没有空卡，服务状态也都正常。")
            .font(.system(size: 13)).foregroundStyle(.secondary)
        } else {
          Text("发现 \(report.issueCount) 处可以收拾一下")
            .font(.system(size: 16, weight: .semibold))
          Text("点任意一项看明细，再点条目直接跳到它。体检只看不动，不会自动改你的数据。")
            .font(.system(size: 13)).foregroundStyle(.secondary)
        }
      }
      Section {
        ForEach(HealthKind.allCases, id: \.rawValue) { k in
          let n = k.count(report)
          NavigationLink { HealthListView(kind: k) } label: {
            HStack(spacing: 12) {
              Image(systemName: k.icon).font(.system(size: 17)).foregroundStyle(.secondary).frame(width: 26)
              Text(k.title).font(.system(size: 15, weight: .medium))
              Spacer()
              if n > 0 {
                Text("\(n)").font(.system(size: 15, weight: .bold)).foregroundStyle(.orange)
              } else {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
              }
            }
          }
          .disabled(n == 0)
        }
      }
    }
    .navigationTitle("账号体检").navigationBarTitleDisplayMode(.inline)
  }
}

struct HealthListView: View {
  @Environment(Store.self) var store
  let kind: HealthKind
  var body: some View {
    let report = HealthReport.build(store.data)
    List {
      switch kind {
      case .dupBindings: accountRows(report.dupBindings)
      case .unboundAccounts: accountRows(report.unboundAccounts)
      case .inactiveAccounts: accountRows(report.inactiveAccounts)
      case .noDomainAccounts: accountRows(report.noDomainAccounts)
      case .idleIdentities: identityRows(report.idleIdentities)
      case .dupIdentities: identityRows(report.dupIdentities)
      }
    }
    .listStyle(.plain)
    .navigationTitle(kind.title).navigationBarTitleDisplayMode(.inline)
  }

  @ViewBuilder func accountRows(_ list: [Account]) -> some View {
    if list.isEmpty { Text("这一项没有问题。").foregroundStyle(.secondary) }
    ForEach(list) { a in
      Button { store.route = .account(a.id) } label: { ReelRow(account: a) }
        .buttonStyle(PressStyle(scale: 0.98))
        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }
  }
  @ViewBuilder func identityRows(_ list: [Identity]) -> some View {
    if list.isEmpty { Text("这一项没有问题。").foregroundStyle(.secondary) }
    ForEach(list) { i in
      Button { store.route = .identity(i.id) } label: {
        HStack(spacing: 12) {
          IdentityGlyph(identity: i, size: 13).foregroundStyle(.white).frame(width: 40, height: 28)
            .background(skinGradient(i.color), in: CardShape(sim: i.isPhone))
          VStack(alignment: .leading, spacing: 2) {
            Text(store.title(i)).font(.system(size: 16, weight: .semibold)).lineLimit(1)
            Text(i.kindName + (i.label.isEmpty ? "" : " · " + store.display(i)))
              .font(.system(size: 13)).foregroundStyle(.secondary).lineLimit(1)
          }
          Spacer()
          Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(.tertiary)
        }
        .padding(12)
        .background(.glass, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .foregroundStyle(.primary)
      }
      .buttonStyle(PressStyle(scale: 0.98))
      .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
      .listRowBackground(Color.clear)
      .listRowSeparator(.hidden)
    }
  }
}
