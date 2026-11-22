import SwiftUI
import SafariServices

struct ContentView: View {
    @State private var safariLink: SafariLink?
    @State private var showProto = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            // 网页模式：原有行为一字不改（WebView 仍在底层保活，切原型不重载网页）
            WebView(onOpenExternal: { url in
                safariLink = SafariLink(url: url)
            })
            .ignoresSafeArea()
            .sheet(item: $safariLink) { link in
                SafariView(url: link.url)
                    .ignoresSafeArea()
            }

            if showProto {
                // 原型模式：原生页整页盖住网页，顶部「回网页版」退出
                ProtoRootView(onExit: { showProto = false })
            } else {
                // 网页模式右上角悬浮入口（安全区内，不挡网页底栏）
                Button {
                    showProto = true
                } label: {
                    Text("原生原型")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(Capsule().fill(Color(white: 0.1).opacity(0.92)))
                        .overlay(Capsule().stroke(Color.white.opacity(0.25), lineWidth: 1))
                }
                .padding(.top, 10)
                .padding(.trailing, 12)
            }
        }
    }
}

private struct SafariLink: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let vc = SFSafariViewController(url: url)
        vc.dismissButtonStyle = .close
        return vc
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}
