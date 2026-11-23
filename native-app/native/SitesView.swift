import SwiftUI

struct SitesView: View {
  @Environment(Store.self) var store
  @State private var cat = "全部"
  @State private var statusFilter = "all"   // all | active | stopped | cancelled (BindInfo keys)
  @State private var query = ""

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 0) {
          if store.data.accounts.isEmpty { empty } else {
            chips.padding(.top, 4)
            statusChips.padding(.top, 10)
            let groups = sections
            LazyVStack(alignment: .leading, spacing: 8, pinnedViews: []) {
              ForEach(groups, id: \.self) { c in
                let list = sectionItems(c)
                if !list.isEmpty {
                  HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(c).font(.system(size: 20, weight: .bold))
                    Text("\(list.count)").font(.system(size: 14, weight: .medium)).foregroundStyle(.secondary)
                  }.padding(.top, 18).padding(.leading, 4)
                  ForEach(list) { a in
                    AccountRow(account: a) { store.route = .account(a.id) }
                  }
                }
              }
            }
            .padding(.horizontal, 16)
            .animation(Motion.smooth, value: cat)
            .animation(Motion.smooth, value: statusFilter)
          }
          Color.clear.frame(height: 96)   // clearance for the floating bottom bar
        }
      }
      .scrollIndicators(.hidden)
      .navigationTitle("网站与 App")
      .searchable(text: $query, prompt: "搜索名称、域名、账号名")
      .toolbar { TopButtons() }
      .toolbar(.hidden, for: .tabBar)
      .background(Glow().ignoresSafeArea())
    }
  }

  // Sections come straight from the store's prebuilt per-category lists (already name-sorted);
  // only a search query does any filtering, once per keystroke instead of once per category.
  var query_: String { query.trimmingCharacters(in: .whitespaces).lowercased() }
  func matches(_ a: Account, _ q: String) -> Bool {
    a.name.lowercased().contains(q) || a.domain.lowercased().contains(q) || (a.handle ?? "").lowercased().contains(q) || a.notes.lowercased().contains(q)
      || a.identityIds.compactMap { store.identity($0) }.contains { $0.value.lowercased().contains(q) || $0.label.lowercased().contains(q) }
  }
  func sectionItems(_ c: String) -> [Account] {
    var all = store.index.byCategory[c] ?? []
    if statusFilter != "all" { all = all.filter { $0.bindStatusKey == statusFilter } }
    let q = query_
    return q.isEmpty ? all : all.filter { matches($0, q) }
  }
  var cats: [String] { store.index.categories }
  var sections: [String] { cat == "全部" || !cats.contains(cat) ? cats : [cat] }

  var chips: some View {
    ScrollView(.horizontal) {
      HStack(spacing: 8) {
        ForEach(["全部"] + cats, id: \.self) { c in
          let n = c == "全部" ? store.data.accounts.count : (store.index.categoryCount[c] ?? 0)
          Button { withAnimation(Motion.snappy) { cat = c } } label: {
            HStack(spacing: 4) { Text(c); Text("\(n)").foregroundStyle(cat == c ? Color.white.opacity(0.75) : Color.secondary) }
              .font(.system(size: 14, weight: .semibold))
              .padding(.horizontal, 13).frame(height: 32)
              .foregroundStyle(cat == c ? Color.white : Color.primary)
              .background(cat == c ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.glass), in: Capsule())
          }.buttonStyle(PressStyle(scale: 0.94))
        }
      }.padding(.horizontal, 16)
    }
    .scrollIndicators(.hidden)
    .sensoryFeedback(.selection, trigger: cat)
  }

  // status filter row: 全部 / 正常 / 停用 / 已注销， counts over every account
  var statusChips: some View {
    let counts: [String: Int] = [
      "active": store.data.accounts.filter { $0.bindStatusKey == "active" }.count,
      "stopped": store.data.accounts.filter { $0.bindStatusKey == "stopped" }.count,
      "cancelled": store.data.accounts.filter { $0.bindStatusKey == "cancelled" }.count,
    ]
    return ScrollView(.horizontal) {
      HStack(spacing: 8) {
        ForEach([("all", "全部", store.data.accounts.count)] + BindInfo.statuses.map { ($0.key, $0.label, counts[$0.key] ?? 0) }, id: \.0) { o in
          let on = statusFilter == o.0
          Button { withAnimation(Motion.snappy) { statusFilter = o.0 } } label: {
            HStack(spacing: 4) {
              if o.0 == "stopped" || o.0 == "cancelled" { Circle().fill(o.0 == "cancelled" ? Color.red : Color.orange).frame(width: 7, height: 7) }
              Text(o.1)
              Text("\(o.2)").foregroundStyle(on ? Color.white.opacity(0.75) : Color.secondary)
            }
            .font(.system(size: 13, weight: .semibold))
            .padding(.horizontal, 11).frame(height: 28)
            .foregroundStyle(on ? Color.white : Color.primary)
            .background(on ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.glass), in: Capsule())
          }.buttonStyle(PressStyle(scale: 0.94))
        }
      }.padding(.horizontal, 16)
    }
    .scrollIndicators(.hidden)
    .sensoryFeedback(.selection, trigger: statusFilter)
  }

  var empty: some View {
    VStack(spacing: 12) {
      Image(systemName: "square.grid.2x2").font(.system(size: 44, weight: .light)).foregroundStyle(.secondary)
      Text("还没有网站").font(.system(size: 20, weight: .bold))
      Text("记下一个网站或 App，选上它用的是哪个邮箱、哪个手机号。").font(.system(size: 15)).foregroundStyle(.secondary).multilineTextAlignment(.center)
      Button("添加网站或 App") { store.route = .picker(nil) }.buttonStyle(.borderedProminent).buttonBorderShape(.capsule).padding(.top, 6)
    }
    .padding(40).frame(maxWidth: .infinity).padding(.top, 60)
  }
}
