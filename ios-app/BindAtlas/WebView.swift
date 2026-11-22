import SwiftUI
import WebKit

/// 全屏 WKWebView 壳：加载打包在 App 内的本地网页（Web/index.html）。
///
/// 做四件事：
/// 1. 打开 JavaScript 与 DOM 存储（localStorage）——网页的数据层全靠它。
/// 2. 外链（网页里「前往登录」用 window.open 打开的 https 链接）交给
///    SFSafariViewController，不困在 WebView 里。
/// 3. 注入 ExportBridge.js，把 blob 导出转成原生分享面板（见 ExportBridge.js 注释）。
/// 4. 文件导入（<input type=file>）由 WKWebView 系统文件选择器原生支持，无需额外代码。
struct WebView: UIViewRepresentable {
    var onOpenExternal: (URL) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onOpenExternal: onOpenExternal)
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default() // localStorage 持久化
        if let prefs = config.defaultWebpagePreferences {
            prefs.allowsContentJavaScript = true
        }

        // 导出桥：消息处理器 + document start 注入脚本
        let controller = config.userContentController
        controller.add(context.coordinator, name: "exportFile")
        if let scriptURL = Bundle.main.url(forResource: "ExportBridge", withExtension: "js"),
           let source = try? String(contentsOf: scriptURL, encoding: .utf8) {
            let userScript = WKUserScript(source: source, injectionTime: .atDocumentStart, forMainFrameOnly: false)
            controller.addUserScript(userScript)
        }

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = false
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        if #available(iOS 16.4, *) {
            webView.isInspectable = true // 方便用 Mac Safari 远程调试网页
        }

        if let indexURL = Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: "Web") {
            let readAccess = indexURL.deletingLastPathComponent()
            webView.loadFileURL(indexURL, allowingReadAccessTo: readAccess)
        }
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    // MARK: - Coordinator

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
        private let onOpenExternal: (URL) -> Void

        init(onOpenExternal: @escaping (URL) -> Void) {
            self.onOpenExternal = onOpenExternal
        }

        // window.open / target=_blank：不开新 WebView，改走 SFSafariViewController
        func webView(_ webView: WKWebView,
                     createWebViewWith configuration: WKWebViewConfiguration,
                     for navigationAction: WKNavigationAction,
                     windowFeatures: WKWindowFeatures) -> WKWebView? {
            if let url = navigationAction.request.url, Self.isExternalWebURL(url) {
                onOpenExternal(url)
            }
            return nil
        }

        // 主 frame 直接跳 http(s)（普通 <a href> 外链）：同样拦下走 Safari
        func webView(_ webView: WKWebView,
                     decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if let url = navigationAction.request.url,
               navigationAction.targetFrame?.isMainFrame == true,
               Self.isExternalWebURL(url) {
                onOpenExternal(url)
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }

        // 导出桥消息：{name, base64} → 写临时文件 → 系统分享面板
        func userContentController(_ userContentController: WKUserContentController,
                                   didReceive message: WKScriptMessage) {
            guard message.name == "exportFile",
                  let body = message.body as? [String: Any],
                  let name = body["name"] as? String,
                  let base64 = body["base64"] as? String,
                  let data = Data(base64Encoded: base64) else { return }

            let safeName = name.isEmpty ? "bind-backup.json" : name
            let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(safeName)
            do {
                try data.write(to: fileURL, options: .atomic)
            } catch {
                return
            }
            DispatchQueue.main.async {
                guard let presenter = Self.topViewController() else { return }
                let share = UIActivityViewController(activityItems: [fileURL], applicationActivities: nil)
                // iPad 上分享面板必须有锚点
                if let popover = share.popoverPresentationController {
                    popover.sourceView = presenter.view
                    popover.sourceRect = CGRect(x: presenter.view.bounds.midX, y: presenter.view.bounds.midY, width: 0, height: 0)
                    popover.permittedArrowDirections = []
                }
                presenter.present(share, animated: true)
            }
        }

        private static func isExternalWebURL(_ url: URL) -> Bool {
            guard let scheme = url.scheme?.lowercased() else { return false }
            return scheme == "http" || scheme == "https"
        }

        private static func topViewController() -> UIViewController? {
            let keyWindow = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap { $0.windows }
                .first { $0.isKeyWindow }
            var top = keyWindow?.rootViewController
            while let presented = top?.presentedViewController {
                top = presented
            }
            return top
        }
    }
}
