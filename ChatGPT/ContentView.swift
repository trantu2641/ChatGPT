
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

        controller.add(
            context.coordinator,
            name: "chatGPTDownload"
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

    // MARK: - Blob Download Script

    static let downloadScript = """
    (() => {
        if (window.__chatGPTDownloadInstalled) return;
        window.__chatGPTDownloadInstalled = true;

        document.addEventListener('click', function(event) {
            const link = event.target.closest('a');

            if (!link) return;

            const url = link.href || '';

            if (!url.startsWith('blob:')) return;

            event.preventDefault();
            event.stopImmediatePropagation();

            window.webkit.messageHandlers.chatGPTDownload.postMessage({
                type: 'blob',
                url: url,
                filename: link.download || 'download'
            });

        }, true);

        window.__chatGPTReadBlob = function(url, filename) {

            fetch(url)
                .then(response => response.blob())
                .then(blob => {

                    const reader = new FileReader();

                    reader.onload = function() {

                        const result = reader.result;

                        window.webkit.messageHandlers.chatGPTDownload.postMessage({
                            type: 'data',
                            filename: filename,
                            data: result.split(',')[1]
                        });
                    };

                    reader.onerror = function() {
                        console.error('Cannot read Blob');
                    };

                    reader.readAsDataURL(blob);
                })
                .catch(error => {
                    console.error('Blob download error:', error);
                });
        };
    })();
    """

    // MARK: - Coordinator

    final class Coordinator: NSObject,
                            WKNavigationDelegate,
                            WKUIDelegate,
                            WKDownloadDelegate,
                            WKScriptMessageHandler {

        weak var webView: WKWebView?

        private var activeDownloads: [ObjectIdentifier: URL] = [:]

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

            createDownloadsDirectory()
        }

        // MARK: - Directory

        private func createDownloadsDirectory() {

            do {
                try FileManager.default.createDirectory(
                    at: downloadsDirectory,
                    withIntermediateDirectories: true,
                    attributes: nil
                )

                print("DOWNLOAD DIRECTORY:")
                print(downloadsDirectory.path)

            } catch {
                print("DIRECTORY ERROR: \(error)")
            }
        }

        // MARK: - JavaScript Message

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {

            guard
                message.name == "chatGPTDownload",
                let body = message.body as? [String: Any],
                let type = body["type"] as? String
            else {
                return
            }

            if type == "blob" {

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

            if type == "data" {

                guard
                    let filename = body["filename"] as? String,
                    let base64 = body["data"] as? String,
                    let data = Data(base64Encoded: base64)
                else {
                    showError("Dữ liệu tệp không hợp lệ.")
                    return
                }

                saveBlobFile(
                    data,
                    filename: filename
                )
            }
        }

        // MARK: - Blob Confirmation

        private func confirmBlobDownload(
            url: String,
            filename: String
        ) {

            let alert = UIAlertController(
                title: "Tải xuống tệp?",
                message: "Bạn có muốn lưu \(filename) vào ứng dụng Tệp?",
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

                    let script = """
                    window.__chatGPTReadBlob(
                        \(Self.jsonString(url)),
                        \(Self.jsonString(filename))
                    );
                    """

                    self.webView?.evaluateJavaScript(
                        script,
                        completionHandler: { _, error in
                            if let error {
                                print("BLOB ERROR: \(error)")
                            }
                        }
                    )
                }
            )

            present(alert)
        }

        // MARK: - Navigation Download

        func webView(
            _ webView: WKWebView,
            navigationAction: WKNavigationAction,
            didBecome download: WKDownload
        ) {

            print("NAVIGATION DOWNLOAD STARTED")

            download.delegate = self
        }

        func webView(
            _ webView: WKWebView,
            navigationResponse: WKNavigationResponse,
            didBecome download: WKDownload
        ) {

            print("RESPONSE DOWNLOAD STARTED")

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

        // MARK: - Download Destination

        func download(
            _ download: WKDownload,
            decideDestinationUsing response: URLResponse,
            suggestedFilename: String,
            completionHandler: @escaping (URL?) -> Void
        ) {

            let alert = UIAlertController(
                title: "Tải xuống tệp?",
                message: """
                \(suggestedFilename)

                Lưu vào Tệp → Trên iPhone của tôi → ChatGPT → Downloads?
                """,
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
                ) { [weak self, weak download] _ in

                    guard
                        let self,
                        let download
                    else {
                        completionHandler(nil)
                        return
                    }

                    do {
                        self.createDownloadsDirectory()

                        let destination = self.uniqueDestination(
                            filename: suggestedFilename
                        )

                        self.activeDownloads[
                            ObjectIdentifier(download)
                        ] = destination

                        print("DOWNLOAD DESTINATION:")
                        print(destination.path)

                        completionHandler(destination)

                    } catch {
                        print("DESTINATION ERROR: \(error)")
                        completionHandler(nil)
                    }
                }
            )

            present(alert)
        }

        // MARK: - Download Finished

        func downloadDidFinish(_ download: WKDownload) {

            let key = ObjectIdentifier(download)
            let destination = activeDownloads.removeValue(
                forKey: key
            )

            guard let destination else {
                showError("Không xác định được vị trí lưu tệp.")
                return
            }

            let exists = FileManager.default.fileExists(
                atPath: destination.path
            )

            if exists {

                let attributes = try? FileManager.default.attributesOfItem(
                    atPath: destination.path
                )

                let size = attributes?[.size] as? Int64 ?? 0

                print("DOWNLOAD SUCCESS")
                print(destination.path)
                print("SIZE: \(size) bytes")

                if size > 0 {
                    showSavedAlert(
                        filename: destination.lastPathComponent,
                        path: destination.path
                    )
                } else {
                    showError("Tệp được tạo nhưng có dung lượng 0 byte.")
                }

            } else {

                print("FILE DOES NOT EXIST")
                showError(
                    "WebKit báo tải xong nhưng không tìm thấy tệp tại:\n\(destination.path)"
                )
            }
        }

        // MARK: - Download Failed

        func download(
            _ download: WKDownload,
            didFailWithError error: Error,
            resumeData: Data?
        ) {

            activeDownloads.removeValue(
                forKey: ObjectIdentifier(download)
            )

            print("DOWNLOAD FAILED:")
            print(error.localizedDescription)

            showError(
                "Không thể tải tệp:\n\(error.localizedDescription)"
            )
        }

        // MARK: - Save Blob

        private func saveBlobFile(
            _ data: Data,
            filename: String
        ) {

            do {
                createDownloadsDirectory()

                let destination = uniqueDestination(
                    filename: filename
                )

                try data.write(
                    to: destination,
                    options: .atomic
                )

                let exists = FileManager.default.fileExists(
                    atPath: destination.path
                )

                guard exists else {
                    showError("Không tìm thấy tệp sau khi lưu.")
                    return
                }

                let size = Int64(data.count)

                print("BLOB SAVED:")
                print(destination.path)
                print("SIZE: \(size) bytes")

                showSavedAlert(
                    filename: destination.lastPathComponent,
                    path: destination.path
                )

            } catch {
                showError(
                    "Không thể lưu tệp:\n\(error.localizedDescription)"
                )
            }
        }

        // MARK: - Unique File Name

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

                let suffix = String(
                    UUID().uuidString.prefix(8)
                )

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
                    print("ALERT ERROR: Root controller unavailable")
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
            filename: String,
            path: String
        ) {

            let alert = UIAlertController(
                title: "Tải xuống thành công",
                message: """
                Tệp: \(filename)

                Đã lưu tại:
                \(path)

                Mở Tệp → Trên iPhone của tôi → ChatGPT → Downloads.
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
                title: "Lỗi tải xuống",
                message: message,
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

        // MARK: - New Windows

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
