import SwiftUI
import WebKit

struct MiMoConsoleConnectionSheet: View {
    @Binding var status: String
    let onConnected: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("连接 MiMo 控制台")
                    .font(.headline)
                Spacer()
                Text(status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("关闭") { dismiss() }
                    .font(.caption)
            }

            MiMoConsoleConnectionView(status: $status, onConnected: onConnected)
                .frame(width: 980, height: 680)
        }
        .padding(14)
        .frame(width: 1008, height: 730)
    }
}

private struct MiMoConsoleConnectionView: NSViewRepresentable {
    @Binding var status: String
    let onConnected: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(status: $status, onConnected: onConnected)
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        context.coordinator.webView = webView

        if let url = URL(string: "https://platform.xiaomimimo.com/console/plan-manage") {
            webView.load(URLRequest(url: url))
        }
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate {
        @Binding private var status: String
        private let onConnected: (String) -> Void
        weak var webView: WKWebView?
        private var didConnect = false
        private var isChecking = false
        private nonisolated(unsafe) var pollTimer: Timer?

        init(status: Binding<String>, onConnected: @escaping (String) -> Void) {
            self._status = status
            self.onConnected = onConnected
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                self?.checkConnection()
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            status = "页面加载失败：\(error.localizedDescription)"
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            status = "页面加载失败：\(error.localizedDescription)"
        }

        func stopPolling() {
            pollTimer?.invalidate()
            pollTimer = nil
        }

        deinit {
            let timer = pollTimer
            Task { @MainActor in timer?.invalidate() }
        }

        private func startPolling() {
            guard pollTimer == nil else { return }
            pollTimer = Timer.scheduledTimer(withTimeInterval: 4, repeats: true) { [weak self] _ in
                DispatchQueue.main.async { self?.checkConnection() }
            }
        }

        private func checkConnection() {
            guard !didConnect, !isChecking, let webView else { return }
            isChecking = true
            status = "正在检测 MiMo 登录状态..."

            webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { [weak self] cookies in
                guard let self else { return }

                let usageURL = URL(string: "https://platform.xiaomimimo.com/api/v1/tokenPlan/usage")!
                let cookieHeader = MiMoCookieHeaderBuilder.header(from: cookies, for: usageURL)

                guard !cookieHeader.isEmpty else {
                    self.isChecking = false
                    self.status = "请登录 MiMo 控制台，登录后会自动获取。"
                    self.startPolling()
                    return
                }

                var request = URLRequest(url: usageURL)
                request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
                request.setValue("application/json", forHTTPHeaderField: "Accept")
                request.timeoutInterval = 12

                URLSession.shared.dataTask(with: request) { data, response, _ in
                    DispatchQueue.main.async {
                        self.isChecking = false

                        guard
                            let data,
                            let httpResponse = response as? HTTPURLResponse,
                            (200..<300).contains(httpResponse.statusCode),
                            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                            (json["code"] as? Int) == 0
                        else {
                            self.status = "请登录 MiMo 控制台，登录后会自动获取。"
                            self.startPolling()
                            return
                        }

                        self.stopPolling()
                        self.didConnect = true
                        self.status = "已连接 MiMo 控制台。"
                        self.onConnected(cookieHeader)
                    }
                }.resume()
            }
        }
    }
}
