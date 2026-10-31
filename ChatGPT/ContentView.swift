
import SwiftUI
import WebKit
import UIKit

struct ContentView: View {
    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let portrait = size.height >= size.width
            let ratio: CGFloat = portrait ? 9.0 / 17.5 : 17.5 / 9.0

            ChatGPTWebView()
                .aspectRatio(ratio, contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .frame(width: size.width, height: size.height)
                .background(.black)
        }
        .background(.black)
        .ignoresSafeArea()
        .ignoresSafeArea(.keyboard)
        .preferredColorScheme(.dark)
    }
}

private struct ChatGPTWebView: UIViewRepresentable {

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> WKWebView {

        let controller = WKUserContentController()

        controller.add(
            context.coordinator,
            name: "fileDownload"
        )

        let script = WKUserScript(
            source: Self.downloadScript,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: false
        )

        controller.addUserScript(script)

        let configuration = WKWebViewConfiguration()
        configuration.userContentController = controller
        configuration.allowsInlineMediaPlayback = true

        let webView = WKWebView(
            frame: .zero,
            configuration: configuration
        )

        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator

        webView.allowsBackForwardNavigationGestures = true
        webView.scrollView.showsVerticalScrollIndicator = false
        webView.scrollView.showsHorizontalScrollIndicator = false
        webView.scrollView.keyboardDismissMode = .interactive

        webView.isOpaque = true
        webView.backgroundColor = .black
        webView.scrollView.backgroundColor = .black

        context.coordinator.webView = webView

        if let url = URL(string: "https://chatgpt.com/") {
            webView.load(URLRequest(url: url))
        }

        return webView
    }

    func updateUIView(
        _ uiView: WKWebView,
        context: Context
    ) {}

    static let downloadScript = """
    (() => {
        if (window.__chatGPTDownloadInstalled) return;
        window.__chatGPTDownloadInstalled = true;

        function sendFile(blob, filename) {
            const reader = new FileReader();

            reader.onload = function() {
                const result = reader.result;

                if (typeof result !== 'string') return;

                const base64 = result.split(',')[1];

                window.webkit.messageHandlers.fileDownload.postMessage({
                    filename: filename || 'download',
                    data: base64
                });
            };

            reader.readAsDataURL(blob);
        }

        document.addEventListener('click', function(event) {
            const link = event.target.closest('a');

            if (!link || !link.href.startsWith('blob:')) return;

            event.preventDefault();
            event.stopPropagation();

            fetch(link.href)
                .then(response => response.blob())
                .then(blob => {
                    sendFile(
                        blob,
                        link.download || 'download'
                    );
                })
                .catch(error => console.error(error));

        }, true);

        const originalCreate = URL.createObjectURL;

        URL.createObjectURL = function(object) {
            const url = originalCreate.call(this, object);

            if (object instanceof Blob) {
                window.__chatGPTBlobs =
                    window.__chatGPTBlobs || {};

                window.__chatGPTBlobs[url] = object;
            }

            return url;
        };

        document.addEventListener('click', function(event) {
            const link = event.target.closest('a');

            if (!link || !link.href.startsWith('blob:')) return;

            const blob = window.__chatGPTBlobs?.[link.href];

            if (blob) {
                event.preventDefault();

                sendFile(
                    blob,
                    link.download || 'download'
                );
            }
        }, true);

    })();
    """

    final class Coordinator: NSObject,
                            WKNavigationDelegate,
                            WKUIDelegate,
                            WKDownloadDelegate,
                            WKScriptMessageHandler {

        weak var webView: WKWebView?

        private var downloadsDirectory: URL {
            FileManager.default.urls(
                for: .documentDirectory,
                in: .userDomainMask
            )[0].appendingPathComponent(
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

        // MARK: - JavaScript downloads

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {

            guard
                message.name == "fileDownload",
                let body = message.body as? [String: Any],
                let filename = body["filename"] as? String,
                let base64 = body["data"] as? String,
                let data = Data(base64Encoded: base64)
            else {
                return
            }

            saveFile(data, filename: filename)
        }

        private func saveFile(
            _ data: Data,
            filename: String
        ) {

            do {
                try FileManager.default.createDirectory(
                    at: downloadsDirectory,
                    withIntermediateDirectories: true
                )

                let safeName = Self.safeFilename(filename)

                var destination =
                    downloadsDirectory.appendingPathComponent(safeName)

                if FileManager.default.fileExists(
                    atPath: destination.path
                ) {
                    let ext = destination.pathExtension
                    let base = destination.deletingPathExtension().lastPathComponent
                    let suffix = String(UUID().uuidString.prefix(8))

                    let newName = ext.isEmpty
                        ? "\(base)-\(suffix)"
                        : "\(base)-\(suffix).\(ext)"

                    destination = downloadsDirectory.appendingPathComponent(newName)
                }

                try data.write(to: destination, options: .atomic)

                print("Đã lưu tệp: \(destination.path)")

            } catch {
                print("Lỗi lưu tệp: \(error)")
            }
        }

        private static func safeFilename(_ filename: String) -> String {
            let cleaned = filename
                .replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: "\\", with: "_")
                .trimmingCharacters(in: .whitespacesAndNewlines)

            return cleaned.isEmpty ? "download" : cleaned
        }

        // MARK: - Normal downloads

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
            decisionHandler(
                navigationResponse.canShowMIMEType ? .allow : .download
            )
        }

        func download(
            _ download: WKDownload,
            decideDestinationUsing response: URLResponse,
            suggestedFilename: String,
            completionHandler: @escaping (URL?) -> Void
        ) {

            let destination = downloadsDirectory
                .appendingPathComponent(
                    Self.safeFilename(suggestedFilename)
                )

            completionHandler(destination)
        }

        func downloadDidFinish(_ download: WKDownload) {
            print("Tải tệp hoàn tất")
        }

        func download(
            _ download: WKDownload,
            didFailWithError error: Error,
            resumeData: Data?
        ) {
            print("Lỗi tải: \(error.localizedDescription)")
        }

        // MARK: - New windows

        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {

            if navigationAction.targetFrame == nil,
               let url = navigationAction.request.url {
                webView.load(URLRequest(url: url))
            }

            return nil
        }
    }
}
