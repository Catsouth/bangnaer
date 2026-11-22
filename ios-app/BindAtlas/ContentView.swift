import SwiftUI
import SafariServices

struct ContentView: View {
    @State private var safariLink: SafariLink?

    var body: some View {
        WebView(onOpenExternal: { url in
            safariLink = SafariLink(url: url)
        })
        .ignoresSafeArea()
        .sheet(item: $safariLink) { link in
            SafariView(url: link.url)
                .ignoresSafeArea()
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
