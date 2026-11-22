import SwiftUI

// MARK: - recycle bin （绑哪儿移植自网页版；上游只有墓碑 + 单步撤销 toast)
//
// Two entry shapes, mirroring the web app:
// - account: a single deleted website/App record, kept as a full snapshot.
// - identity: a deleted identity card plus snapshots of the accounts that referenced it
//   ("links") and the ids of login cards whose `via` pointed at it, so a restore can
//   re-link everything. The accounts themselves are NOT deleted with the card (upstream
//   semantics: they stay and just lose the binding), so restore mostly re-links.
// Deleting writes the tombstone as before (Store.stamp sees the id disappear), so the
// Gist merge keeps treating the object as deleted until a restore makes it live again.

struct TrashEntry: Codable, Identifiable, Hashable {
  var id: String
  var kind: String                 // "account" | "identity"
  var name: String                 // display name captured at deletion time
  var deletedAt: Double            // ms since epoch
  var account: Account? = nil      // kind == "account"
  var identity: Identity? = nil    // kind == "identity"
  var links: [Account] = []        // kind == "identity": accounts that referenced it
  var viaFrom: [String] = []       // kind == "identity": login card ids whose via pointed here

  init(id: String = newID(), kind: String, name: String, deletedAt: Double = nowMS(),
       account: Account? = nil, identity: Identity? = nil, links: [Account] = [], viaFrom: [String] = []) {
    self.id = id; self.kind = kind; self.name = name; self.deletedAt = deletedAt
    self.account = account; self.identity = identity; self.links = links; self.viaFrom = viaFrom
  }
  init(from d: Decoder) throws {
    let c = try d.container(keyedBy: CodingKeys.self)
    id = try c.decode(String.self, forKey: .id)
    kind = (try? c.decode(String.self, forKey: .kind)) ?? "account"
    name = (try? c.decode(String.self, forKey: .name)) ?? ""
    deletedAt = (try? c.decode(Double.self, forKey: .deletedAt)) ?? 0
    account = try? c.decode(Account.self, forKey: .account)
    identity = try? c.decode(Identity.self, forKey: .identity)
    links = (try? c.decode([Account].self, forKey: .links)) ?? []
    viaFrom = (try? c.decode([String].self, forKey: .viaFrom)) ?? []
  }
}

extension Store {
  /// All account deletions go through here: snapshot into the trash, then remove.
  /// The undo toast is NOT offered for deletions anymore — the trash is the one
  /// recovery path (the web app made the same choice; two tracks would conflict:
  /// undo restores a whole-data snapshot and would resurrect unrelated changes).
  func deleteAccountToTrash(_ a: Account) {
    mutate("已删除 · 已移到回收站", undo: false) { s in
      s.accounts.removeAll { $0.id == a.id }
      s.trash.append(TrashEntry(kind: "account", name: a.name, account: a))
    }
  }

  /// Identity deletion keeps upstream semantics (accounts stay, bindings are stripped,
  /// login cards lose their via) and snapshots everything needed to re-link on restore.
  func deleteIdentityToTrash(_ i: Identity) {
    let displayName = i.label.isEmpty ? i.value : i.label
    mutate("已删除 · 已移到回收站", undo: false) { s in
      let links = s.accounts.filter { $0.identityIds.contains(i.id) }
      let viaFrom = s.identities.filter { $0.via == i.id }.map(\.id)
      s.identities.removeAll { $0.id == i.id }
      for k in s.accounts.indices { s.accounts[k].identityIds.removeAll { $0 == i.id } }
      for k in s.identities.indices where s.identities[k].via == i.id { s.identities[k].via = nil }
      s.trash.append(TrashEntry(kind: "identity", name: displayName, identity: i, links: links, viaFrom: viaFrom))
    }
  }

  /// Puts a trash entry back. Objects whose id already exists are skipped (counted),
  /// never duplicated. Making an object live again clears its tombstone via stamp().
  func restoreTrash(_ entry: TrashEntry) {
    var skipped = 0
    mutate(nil, undo: false) { s in
      s.trash.removeAll { $0.id == entry.id }
      if entry.kind == "account", let a = entry.account {
        if s.accounts.contains(where: { $0.id == a.id }) { skipped += 1 } else { s.accounts.append(a) }
      } else if entry.kind == "identity", let i = entry.identity {
        if s.identities.contains(where: { $0.id == i.id }) { skipped += 1 } else { s.identities.append(i) }
        for snap in entry.links {
          if let k = s.accounts.firstIndex(where: { $0.id == snap.id }) {
            if !s.accounts[k].identityIds.contains(i.id) { s.accounts[k].identityIds.append(i.id) }
          } else {
            s.accounts.append(snap)
          }
        }
        for vid in entry.viaFrom {
          if let k = s.identities.firstIndex(where: { $0.id == vid }), s.identities[k].via == nil {
            s.identities[k].via = i.id
          }
        }
      }
    }
    setKind(kind)
    show(skipped > 0 ? "已恢复（\(skipped) 项已存在，跳过）" : "已恢复")
  }

  /// Drops only the trash entry; the tombstone in `deleted` stays, so sync keeps the
  /// object deleted on other devices too.
  func purgeTrash(_ entry: TrashEntry) {
    mutate(nil, undo: false) { s in s.trash.removeAll { $0.id == entry.id } }
    show("已彻底删除")
  }

  func emptyTrash() {
    mutate(nil, undo: false) { s in s.trash.removeAll() }
    show("回收站已清空")
  }
}

// MARK: - trash UI

struct TrashView: View {
  @Environment(Store.self) var store
  @State private var askPurge: TrashEntry? = nil
  @State private var askEmpty = false

  var entries: [TrashEntry] { store.data.trash.sorted { $0.deletedAt > $1.deletedAt } }

  var body: some View {
    List {
      if entries.isEmpty {
        Text("回收站是空的。删掉的身份卡和网站会先来这儿躺着，能恢复。")
          .foregroundStyle(.secondary)
      } else {
        ForEach(entries) { e in
          HStack(spacing: 12) {
            Image(systemName: e.kind == "identity" ? "person.crop.rectangle" : "app.badge")
              .font(.system(size: 20)).foregroundStyle(.secondary).frame(width: 30)
            VStack(alignment: .leading, spacing: 2) {
              Text(e.name.isEmpty ? "（未命名）" : e.name).font(.system(size: 16, weight: .medium)).lineLimit(1)
              Text(subtitle(e)).font(.system(size: 13)).foregroundStyle(.secondary)
            }
            Spacer()
            Button("恢复") { store.restoreTrash(e) }.buttonStyle(.borderless)
            Button("彻底删除", role: .destructive) { askPurge = e }.buttonStyle(.borderless)
          }.padding(.vertical, 3)
        }
      }
    }
    .navigationTitle("回收站").navigationBarTitleDisplayMode(.inline)
    .toolbar {
      if !entries.isEmpty {
        ToolbarItem(placement: .topBarTrailing) {
          Button("清空", role: .destructive) { askEmpty = true }
        }
      }
    }
    .confirmationDialog("彻底删除「\(askPurge?.name ?? "")」？", isPresented: Binding(get: { askPurge != nil }, set: { if !$0 { askPurge = nil } }), titleVisibility: .visible) {
      Button("彻底删除", role: .destructive) { if let e = askPurge { store.purgeTrash(e) }; askPurge = nil }
      Button("取消", role: .cancel) { askPurge = nil }
    } message: { Text("这一步不能撤销。") }
    .confirmationDialog("清空回收站？", isPresented: $askEmpty, titleVisibility: .visible) {
      Button("清空回收站", role: .destructive) { store.emptyTrash() }
      Button("取消", role: .cancel) {}
    } message: { Text("里面 \(entries.count) 项都会被彻底删除，不能撤销。") }
  }

  func subtitle(_ e: TrashEntry) -> String {
    let when = Date(timeIntervalSince1970: e.deletedAt / 1000).formatted(date: .abbreviated, time: .shortened)
    if e.kind == "identity" {
      return "身份卡 · 含 \(e.links.count) 条绑定 · \(when) 删除"
    }
    return "网站与 App · \(when) 删除"
  }
}
