
import SwiftUI
import WebKit
import UIKit

struct ContentView: View {
    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let isPortrait = size.height >= size.width
            let ratio: CGFloat = isPortrait ? 9.0 / 17.5 : 17.5 / 9.0

            ChatGPTWebView()
                .aspectRatio(ratio, contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .frame(width: size.width, height: size.height)
                .background(Color.black)
        }
        .background(Color.black)
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

        controller.add(context.coordinator, name: "downloadRequest")
        controller.add(context.coordinator, name: "downloadData")

        controller.addUserScript(
            WKUserScript(
                source: Self.downloadScript,
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: false
            )
        )

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

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    // MARK: - JavaScript

    static let downloadScript = """
    (() => {
        if (window.__chatGPTNativeDownloadInstalled) return;
        window.__chatGPTNativeDownloadInstalled = true;

        function sendBlob(url, filename) {
            fetch(url)
                .then(response => response.blob())
                .then(blob => {
                    const reader = new FileReader();

                    reader.onload = () => {
                        const result = reader.result;
                        const base64 = result.split(',')[1];

                        window.webkit.messageHandlers.downloadData.postMessage({
                            filename: filename || 'download',
                            data: base64
                        });
                    };

                    reader.readAsDataURL(blob);
                })
                .catch(error => {
                    console.error('Download error:', error);
                });
        }

        window.__chatGPTNativeDownloadBlob = sendBlob;

        document.addEventListener('click', event => {
            const link = event.target.closest('a');

            if (!link) return;

            const href = link.href || '';

            if (!href.startsWith('blob:')) return;

            event.preventDefault();
            event.stopImmediatePropagation();

            window.webkit.messageHandlers.downloadRequest.postMessage({
                url: href,
                filename: link.download || 'download'
            });

        }, true);
    })();
    """

    // MARK: - Coordinator

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

        // MARK: - Message handler

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            guard let body = message.body as? [String: Any] else {
                return
            }

            if message.name == "downloadRequest" {
                guard
                    let url = body["url"] as? String,
                    let filename = body["filename"] as? String
                else {
                    return
                }

                confirmBlobDownload(url: url, filename: filename)
            }

            if message.name == "downloadData" {
                guard
                    let filename = body["filename"] as? String,
                    let base64 = body["data"] as? String,
                    let data = Data(base64Encoded: base64)
                else {
                    return
                }

                saveFile(data, filename: filename)
            }
        }

        // MARK: - Blob confirmation

        private func confirmBlobDownload(
            url: String,
            filename: String
        ) {
            let alert = UIAlertController(
                title: "Tải xuống tệp?",
                message: "Bạn có muốn lưu \(filename) vào ứng dụng Tệp không?",
                preferredStyle: .alert
            )

            alert.addAction(
                UIAlertAction(title: "Hủy", style: .cancel)
            )

            alert.addAction(
                UIAlertAction(title: "Tải xuống", style: .default) {
                    [weak self] _ in

                    guard let self else { return }

                    let urlJSON = Self.jsonString(url)
                    let filenameJSON = Self.jsonString(filename)

                    let script = """
                    window.__chatGPTNativeDownloadBlob(
                        \(urlJSON),
                        \(filenameJSON)
                    );
                    """

                    self.webView?.evaluateJavaScript(
                        script,
                        completionHandler: { _, error in
                            if let error {
                                print("Blob error: \(error)")
                            }
                        }
                    )
                }
            )

            present(alert)
        }

        // MARK: - Normal download

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

        func download(
            _ download: WKDownload,
            decideDestinationUsing response: URLResponse,
            suggestedFilename: String,
            completionHandler: @escaping (URL?) -> Void
        ) {
            confirmNormalDownload(
                filename: suggestedFilename,
                completionHandler: completionHandler
            )
        }

        private func confirmNormalDownload(
            filename: String,
            completionHandler: @escaping (URL?) -> Void
        ) {
            let alert = UIAlertController(
                title: "Tải xuống tệp?",
                message: "Bạn có muốn lưu \(filename) vào ứng dụng Tệp không?",
                preferredStyle: .alert
            )

            alert.addAction(
                UIAlertAction(title: "Hủy", style: .cancel) { _ in
                    completionHandler(nil)
                }
            )

            alert.addAction(
                UIAlertAction(title: "Tải xuống", style: .default) {
                    [weak self] _ in

                    guard let self else {
                        completionHandler(nil)
                        return
                    }

                    do {
                        try FileManager.default.createDirectory(
                            at: self.downloadsDirectory,
                            withIntermediateDirectories: true
                        )

                        let destination = self.uniqueDestination(
                            filename: filename
                        )

                        completionHandler(destination)

                    } catch {
                        print("Download directory error: \(error)")
                        completionHandler(nil)
                    }
                }
            )

            present(alert)
        }

        // MARK: - Save file

        private func saveFile(
            _ data: Data,
            filename: String
        ) {
            do {
                try FileManager.default.createDirectory(
                    at: downloadsDirectory,
                    withIntermediateDirectories: true
                )

                let destination = uniqueDestination(
                    filename: filename
                )

                try data.write(
                    to: destination,
                    options: .atomic
                )

                print("Saved: \(destination.path)")

                showSavedAlert(filename: destination.lastPathComponent)

            } catch {
                print("Save error: \(error)")
            }
        }

        private func uniqueDestination(filename: String) -> URL {
            let safe = Self.safeFilename(filename)

            var destination = downloadsDirectory
                .appendingPathComponent(safe)

            if FileManager.default.fileExists(
                atPath: destination.path
            ) {
                let base = destination.deletingPathExtension().lastPathComponent
                let ext = destination.pathExtension
                let suffix = String(UUID().uuidString.prefix(8))

                let newName = ext.isEmpty
                    ? "\(base)-\(suffix)"
                    : "\(base)-\(suffix).\(ext)"

                destination = downloadsDirectory
                    .appendingPathComponent(newName)
            }

            return destination
        }

        private static func safeFilename(_ filename: String) -> String {
            let cleaned = filename
                .replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: "\\", with: "_")
                .trimmingCharacters(in: .whitespacesAndNewlines)

            return cleaned.isEmpty ? "download" : cleaned
        }

        private static func jsonString(_ value: String) -> String {
            guard
                let data = try? JSONSerialization.data(
                    withJSONObject: [value],
                    options: [.fragmentsAllowed]
                ),
                let result = String(data: data, encoding: .utf8)
            else {
                return "\"\""
            }

            return String(result.dropFirst().dropLast())
        }

        // MARK: - Alerts

        private func present(_ alert: UIAlertController) {
            DispatchQueue.main.async { [weak self] in
                guard let self,
                      let root = self.webView?.window?.rootViewController
                else {
                    return
                }

                var presenter = root

                while let presented = presenter.presentedViewController {
                    presenter = presented
                }

                presenter.present(alert, animated: true)
            }
        }

        private func showSavedAlert(filename: String) {
            let alert = UIAlertController(
                title: "Đã lưu tệp",
                message: "\(filename)\n\nTệp nằm trong Tệp → Trên iPhone của tôi → ChatGPT → Downloads.",
                preferredStyle: .alert
            )

            alert.addAction(
                UIAlertAction(title: "Đóng", style: .default)
            )

            present(alert)
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
