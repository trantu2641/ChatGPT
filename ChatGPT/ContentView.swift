
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
            name: "chatGPTBlobDownload"
        )

        controller.addUserScript(
            WKUserScript(
                source: Self.downloadScript,
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: false
            )
        )

        let configuration = WKWebViewConfiguration()
        configuration.userContentController = controller
        configuration.websiteDataStore = .default()
        configuration.allowsInlineMediaPlayback = true

        let webView = WKWebView(
            frame: .zero,
            configuration: configuration
        )

        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator

        webView.allowsBackForwardNavigationGestures = true
        webView.allowsLinkPreview = true

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

    // MARK: - Blob download script

    static let downloadScript = """
    (() => {
        if (window.__chatGPTDownloadInstalled) return;
        window.__chatGPTDownloadInstalled = true;

        function requestDownload(url, filename) {
            window.webkit.messageHandlers.chatGPTBlobDownload.postMessage({
                url: url,
                filename: filename || 'download'
            });
        }

        window.__chatGPTStartBlobDownload = function(url, filename) {
            fetch(url)
                .then(response => {
                    if (!response.ok) {
                        throw new Error('Cannot read download');
                    }
                    return response.blob();
                })
                .then(blob => {
                    const reader = new FileReader();

                    reader.onload = function() {
                        const result = reader.result;
                        const base64 = result.split(',')[1];

                        window.webkit.messageHandlers.chatGPTBlobDownload.postMessage({
                            filename: filename || 'download',
                            data: base64
                        });
                    };

                    reader.onerror = function() {
                        console.error('Cannot read file');
                    };

                    reader.readAsDataURL(blob);
                })
                .catch(error => console.error(error));
        };

        document.addEventListener('click', function(event) {
            const link = event.target.closest('a');

            if (!link) return;

            const url = link.href || '';

            // Chỉ xử lý Blob và Data URL.
            // Không chặn liên kết HTTP, HTTPS hoặc sandbox.
            if (
                url.startsWith('blob:') ||
                url.startsWith('data:')
            ) {
                event.preventDefault();
                event.stopImmediatePropagation();

                requestDownload(
                    url,
                    link.download || 'download'
                );
            }
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

        // MARK: - JavaScript messages

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            guard
                message.name == "chatGPTBlobDownload",
                let body = message.body as? [String: Any]
            else {
                return
            }

            if let base64 = body["data"] as? String,
               let filename = body["filename"] as? String,
               let data = Data(base64Encoded: base64) {

                saveFile(data, filename: filename)
                return
            }

            guard
                let url = body["url"] as? String,
                let filename = body["filename"] as? String
            else {
                return
            }

            confirmBlobDownload(
                url: url,
                filename: filename
            )
        }

        // MARK: - Blob confirmation

        private func confirmBlobDownload(
            url: String,
            filename: String
        ) {
            let alert = UIAlertController(
                title: "Tải xuống tệp?",
                message: "Lưu \(filename) vào ứng dụng Tệp?",
                preferredStyle: .alert
            )

            alert.addAction(
                UIAlertAction(
                    title: "Hủy",
                    style: .cancel
                )
            )

            alert.addAction(
                UIAlertAction(
                    title: "Tải xuống",
                    style: .default
                ) { [weak self] _ in

                    guard let self else { return }

                    let urlValue = Self.jsonString(url)
                    let nameValue = Self.jsonString(filename)

                    let script = """
                    window.__chatGPTStartBlobDownload(
                        \(urlValue),
                        \(nameValue)
                    );
                    """

                    self.webView?.evaluateJavaScript(
                        script,
                        completionHandler: { _, error in
                            if let error {
                                print("Blob download error: \(error)")
                            }
                        }
                    )
                }
            )

            present(alert)
        }

        // MARK: - WKDownload

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

        // MARK: - Confirm normal download

        func download(
            _ download: WKDownload,
            decideDestinationUsing response: URLResponse,
            suggestedFilename: String,
            completionHandler: @escaping (URL?) -> Void
        ) {
            let alert = UIAlertController(
                title: "Tải xuống tệp?",
                message: "Lưu \(suggestedFilename) vào ứng dụng Tệp?",
                preferredStyle: .alert
            )

            alert.addAction(
                UIAlertAction(
                    title: "Hủy",
                    style: .cancel
                ) { _ in
                    completionHandler(nil)
                }
            )

            alert.addAction(
                UIAlertAction(
                    title: "Tải xuống",
                    style: .default
                ) { [weak self] _ in

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
                            filename: suggestedFilename
                        )

                        completionHandler(destination)

                    } catch {
                        print("Directory error: \(error)")
                        completionHandler(nil)
                    }
                }
            )

            present(alert)
        }

        func downloadDidFinish(_ download: WKDownload) {
            print("Download completed")
        }

        func download(
            _ download: WKDownload,
            didFailWithError error: Error,
            resumeData: Data?
        ) {
            print("Download failed: \(error.localizedDescription)")
        }

        // MARK: - Save Blob/Data files

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

                showSavedAlert(
                    filename: destination.lastPathComponent
                )

            } catch {
                showError(error.localizedDescription)
            }
        }

        // MARK: - File paths

        private func uniqueDestination(
            filename: String
        ) -> URL {

            let safeName = Self.safeFilename(filename)

            var destination = downloadsDirectory
                .appendingPathComponent(safeName)

            if FileManager.default.fileExists(
                atPath: destination.path
            ) {
                let base = destination
                    .deletingPathExtension()
                    .lastPathComponent

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

        private static func safeFilename(
            _ filename: String
        ) -> String {

            let cleaned = filename
                .replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: "\\", with: "_")
                .trimmingCharacters(in: .whitespacesAndNewlines)

            return cleaned.isEmpty ? "download" : cleaned
        }

        private static func jsonString(
            _ value: String
        ) -> String {

            guard
                let data = try? JSONSerialization.data(
                    withJSONObject: [value],
                    options: [.fragmentsAllowed]
                ),
                let result = String(
                    data: data,
                    encoding: .utf8
                )
            else {
                return "\"\""
            }

            return String(
                result.dropFirst().dropLast()
            )
        }

        // MARK: - Alerts

        private func present(
            _ alert: UIAlertController
        ) {
            DispatchQueue.main.async { [weak self] in
                guard
                    let self,
                    let root = self.webView?.window?.rootViewController
                else {
                    return
                }

                var presenter = root

                while let presented = presenter.presentedViewController {
                    presenter = presented
                }

                presenter.present(
                    alert,
                    animated: true
                )
            }
        }

        private func showSavedAlert(
            filename: String
        ) {
            let alert = UIAlertController(
                title: "Đã lưu tệp",
                message: """
                \(filename)

                Tệp nằm trong:
                Tệp → Trên iPhone của tôi → ChatGPT → Downloads
                """,
                preferredStyle: .alert
            )

            alert.addAction(
                UIAlertAction(
                    title: "Đóng",
                    style: .default
                )
            )

            present(alert)
        }

        private func showError(_ message: String) {
            let alert = UIAlertController(
                title: "Không thể lưu tệp",
                message: message,
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

                webView.load(
                    URLRequest(url: url)
                )
            }

            return nil
        }
    }
}
