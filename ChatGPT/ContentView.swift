import SwiftUI
import WebKit

struct ContentView: View {
    @State private var webView: WKWebView?

    var body: some View {
        ChatGPTWebView(webView: $webView)
            .background(Color(red: 0.07, green: 0.07, blue: 0.07))
            .ignoresSafeArea(.container, edges: [.top, .bottom])
    }
}

private struct ChatGPTWebView: UIViewRepresentable {
    @Binding var webView: WKWebView?

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> WKWebView {
        let contentController = WKUserContentController()

        let script = WKUserScript(
            source: Self.hideScrollbarsScript,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: false
        )

        contentController.addUserScript(script)

        let configuration = WKWebViewConfiguration()
        configuration.userContentController = contentController
        configuration.allowsInlineMediaPlayback = true

        let view = WKWebView(
            frame: .zero,
            configuration: configuration
        )

        view.navigationDelegate = context.coordinator
        view.uiDelegate = context.coordinator

        view.allowsBackForwardNavigationGestures = true

        // Ẩn thanh cuộn nhưng vẫn cho phép cuộn bằng cảm ứng.
        view.scrollView.showsVerticalScrollIndicator = false
        view.scrollView.showsHorizontalScrollIndicator = false

        // Cho phép bàn phím hoạt động bình thường trong trang ChatGPT.
        view.scrollView.keyboardDismissMode = .interactive

        view.isOpaque = false
        view.backgroundColor = UIColor(
            red: 0.07,
            green: 0.07,
            blue: 0.07,
            alpha: 1
        )
        view.scrollView.backgroundColor = view.backgroundColor

        context.coordinator.webView = view
        webView = view

        if let url = URL(string: "https://chatgpt.com/") {
            view.load(URLRequest(url: url))
        }

        return view
    }

    func updateUIView(
        _ uiView: WKWebView,
        context: Context
    ) {
        uiView.scrollView.showsVerticalScrollIndicator = false
        uiView.scrollView.showsHorizontalScrollIndicator = false
    }

    private static let hideScrollbarsScript = """
    (() => {
        const styleID = 'chatgpt-ios-hide-scrollbars';

        function applyStyle() {
            if (document.getElementById(styleID)) {
                return;
            }

            const style = document.createElement('style');
            style.id = styleID;

            style.textContent = `
                html, body, * {
                    scrollbar-width: none !important;
                    -ms-overflow-style: none !important;
                }

                ::-webkit-scrollbar {
                    display: none !important;
                    width: 0 !important;
                    height: 0 !important;
                }
            `;

            (document.head || document.documentElement)
                .appendChild(style);
        }

        applyStyle();

        const observer = new MutationObserver(applyStyle);

        observer.observe(document.documentElement, {
            childList: true,
            subtree: true
        });

        setTimeout(() => observer.disconnect(), 10000);
    })();
    """

    final class Coordinator: NSObject,
                            WKNavigationDelegate,
                            WKUIDelegate,
                            WKDownloadDelegate {

        weak var webView: WKWebView?

        private var downloadsDirectory: URL {
            let documents = FileManager.default.urls(
                for: .documentDirectory,
                in: .userDomainMask
            )[0]

            return documents.appendingPathComponent(
                "Downloads",
                isDirectory: true
            )
        }

        override init() {
            super.init()

            try? FileManager.default.createDirectory(
                at: downloadsDirectory,
                withIntermediateDirectories: true
            )
        }

        // MARK: - Web navigation

        func webView(
            _ webView: WKWebView,
            didFinish navigation: WKNavigation!
        ) {
            webView.evaluateJavaScript(
                Self.hideScrollbarsScript,
                completionHandler: nil
            )
        }

        // MARK: - Download detection

        func webView(
            _ webView: WKWebView,
            navigationAction: WKNavigationAction,
            didBecome download: WKDownload
        ) {
            download.delegate = self
        }

        func webView(
            _ webView: WKWebView,
            navigationResponse: WKNavigationResponse,
            didBecome download: WKDownload
        ) {
            download.delegate = self
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            if navigationAction.shouldPerformDownload {
                decisionHandler(.download)
            } else {
                decisionHandler(.allow)
            }
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationResponse: WKNavigationResponse,
            decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void
        ) {
            if navigationResponse.canShowMIMEType {
                decisionHandler(.allow)
            } else {
                decisionHandler(.download)
            }
        }

        // MARK: - Save downloaded files

        func download(
            _ download: WKDownload,
            decideDestinationUsing response: URLResponse,
            suggestedFilename: String,
            completionHandler: @escaping (URL?) -> Void
        ) {
            do {
                try FileManager.default.createDirectory(
                    at: downloadsDirectory,
                    withIntermediateDirectories: true
                )

                let filename = Self.safeFilename(
                    suggestedFilename
                )

                var destination =
                    downloadsDirectory.appendingPathComponent(filename)

                // Không ghi đè tệp cũ nếu tên bị trùng.
                if FileManager.default.fileExists(
                    atPath: destination.path
                ) {
                    let base = destination
                        .deletingPathExtension()
                        .lastPathComponent

                    let ext = destination.pathExtension

                    let suffix = UUID()
                        .uuidString
                        .prefix(8)

                    let newName: String

                    if ext.isEmpty {
                        newName = "\(base)-\(suffix)"
                    } else {
                        newName = "\(base)-\(suffix).\(ext)"
                    }

                    destination =
                        downloadsDirectory.appendingPathComponent(newName)
                }

                completionHandler(destination)

            } catch {
                print(
                    "Không thể tạo thư mục tải xuống: \(error)"
                )

                completionHandler(nil)
            }
        }

        func downloadDidFinish(_ download: WKDownload) {
            print(
                "Tải tệp thành công vào: \(downloadsDirectory.path)"
            )
        }

        func download(
            _ download: WKDownload,
            didFailWithError error: Error,
            resumeData: Data?
        ) {
            print(
                "Tải xuống thất bại: \(error.localizedDescription)"
            )
        }

        private static func safeFilename(
            _ filename: String
        ) -> String {
            let cleaned = filename
                .replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: "\\", with: "_")
                .trimmingCharacters(in: .whitespacesAndNewlines)

            return cleaned.isEmpty ? "download" : cleaned
        }
    }
}
