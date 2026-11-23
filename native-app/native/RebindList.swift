import SwiftUI

// MARK: - 换绑清单 （绑哪儿第三批，行为对齐网页版）
//
// When a phone number or email is replaced, every service bound to it has to be re-bound.
// Pick an identity, get its services as a checklist, tick them off; progress is
// AtlasData.rebindDone ("accountId|identityId" pairs) so it persists and sync-merges
// by union — not UserDefaults. The web app stored the flag per link; the converter
// carried it as Account.extra.bindRebindDone (a blanket per-account flag), which reads
// as "done for every identity of that account" until the first uncheck materializes
// the other pairs into rebindDone and clears the flag.

extension Store {
  static func rebindKey(_ accountID: String, _ identityID: String) -> String { accountID + "|" + identityID }

  func isRebindDone(_ a: Account, _ identityID: String) -> Bool {
    data.rebindDone.contains(Store.rebindKey(a.id, identityID)) || a.legacyRebindDone
  }

  func setRebindDone(_ a: Account, _ identityID: String, _ done: Bool) {
    let key = Store.rebindKey(a.id, identityID)
    guard isRebindDone(a, identityID) != done else { return }
    mutate(nil) { s in
      if done {
        if !s.rebindDone.contains(key) { s.rebindDone.append(key) }
      } else {
        s.rebindDone.removeAll { $0 == key }
        if let k = s.accounts.firstIndex(where: { $0.id == a.id }), s.accounts[k].legacyRebindDone {
          for other in s.accounts[k].identityIds where other != identityID {
            let ok = Store.rebindKey(a.id, other)
            if !s.rebindDone.contains(ok) { s.rebindDone.append(ok) }
          }
          s.accounts[k].extra.removeValue(forKey: "bindRebindDone")
        }
      }
    }
  }
}

struct RebindView: View {
  @Environment(Store.self) var store
  @State private var identityID: String? = nil

  /// phones and emails first (that's what gets replaced), login cards after
  var pickerIdentities: [Identity] { store.index.phones + store.index.emails + store.index.logins }
  var selected: Identity? {
    if let id = identityID, let i = store.identity(id) { return i }
    return pickerIdentities.first
  }

  var body: some View {
    List {
      if pickerIdentities.isEmpty {
        Text("先添加一个邮箱或手机号。").foregroundStyle(.secondary)
      } else if let sel = selected {
        Section {
          Picker("选择身份", selection: Binding(get: { sel.id }, set: { identityID = $0 })) {
            ForEach(pickerIdentities) { i in
              Text("\(store.title(i)) · \(i.kindName)").tag(i.id)
            }
          }
        } footer: { Text("换绑对象：要换掉的旧手机号 / 邮箱。下面是绑着它的全部服务，换好一个勾一个。") }
        let accs = store.accounts(of: sel.id)
        let done = accs.filter { store.isRebindDone($0, sel.id) }.count
        Section {
          HStack {
            Text("进度").font(.system(size: 15, weight: .medium))
            Spacer()
            Text("\(done) / \(accs.count)").font(.system(size: 15, weight: .semibold)).foregroundStyle(.secondary)
          }
          if !accs.isEmpty {
            ProgressView(value: Double(done), total: Double(accs.count)).tint(.green)
          }
          if !accs.isEmpty && done == accs.count {
            Label("全部换绑完成", systemImage: "checkmark.circle.fill")
              .font(.system(size: 15, weight: .semibold)).foregroundStyle(.green)
          }
        }
        Section {
          if accs.isEmpty {
            Text("这个身份还没有绑定的服务。").foregroundStyle(.secondary)
          }
          ForEach(accs) { a in
            rebindRow(a, identityID: sel.id)
          }
        }
      }
    }
    .navigationTitle("换绑清单").navigationBarTitleDisplayMode(.inline)
  }

  func rebindRow(_ a: Account, identityID: String) -> some View {
    let done = store.isRebindDone(a, identityID)
    let sub = [a.bindMethodLabel, a.bindStatusLabel, a.handle.map { store.handleText($0) }]
      .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
    return HStack(spacing: 12) {
      Button { store.setRebindDone(a, identityID, !done) } label: {
        Image(systemName: done ? "checkmark.circle.fill" : "circle")
          .font(.system(size: 24))
          .foregroundStyle(done ? Color.green : Color.secondary.opacity(0.45))
      }
      .buttonStyle(.plain)
      Button { store.route = .account(a.id) } label: {
        HStack(spacing: 12) {
          AppIcon(name: a.name, domain: a.domain, icon: a.icon, size: 40)
          VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
              Text(a.name).font(.system(size: 16, weight: .semibold)).lineLimit(1)
                .strikethrough(done, color: .secondary)
              if a.bindStatusKey != "active" { StatusBadge(status: a.bindStatusKey) }
            }
            if !sub.isEmpty { Text(sub).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1) }
          }
          Spacer(minLength: 0)
          Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
      }
      .buttonStyle(PressStyle(scale: 0.98))
      .foregroundStyle(done ? .secondary : .primary)
    }
    .padding(.vertical, 2)
    .sensoryFeedback(.success, trigger: done)
  }
}
