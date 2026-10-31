
import SwiftUI
import WebKit
import UIKit
import Photos

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
            name: "chatGPTImageAction"
        )

        controller.add(
            context.coordinator,
            name: "chatGPTImageData"
        )

        let script = WKUserScript(
            source: Self.imageScript,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: false
        )

        controller.addUserScript(script)

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

        webView.scrollView.contentInsetAdjustmentBehavior = .never

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

    // MARK: - Image interaction

    static let imageScript = """
    (() => {
        if (window.__chatGPTImageHandlerInstalled) return;
        window.__chatGPTImageHandlerInstalled = true;

        function getImage(element) {
            if (!element) return null;

            const image = element.closest('img');

            if (!image) return null;

            return image.currentSrc || image.src || null;
        }

        document.addEventListener('contextmenu', function(event) {
            const src = getImage(event.target);

            if (!src) return;

            event.preventDefault();
            event.stopPropagation();

            window.webkit.messageHandlers.chatGPTImageAction.postMessage({
                src: src,
                alt: event.target.alt || ''
            });
        }, true);

        window.__chatGPTReadImage = function(src, filename) {
            fetch(src, { credentials: 'include' })
                .then(response => {
                    if (!response.ok) {
                        throw new Error('Image request failed: ' + response.status);
                    }

                    return response.blob();
                })
                .then(blob => {
                    const reader = new FileReader();

                    reader.onload = function() {
                        const result = reader.result;

                        window.webkit.messageHandlers.chatGPTImageData.postMessage({
                            filename: filename,
                            data: result.split(',')[1],
                            mime: blob.type || 'image/jpeg'
                        });
                    };

                    reader.onerror = function() {
                        console.error('Image read failed');
                    };

                    reader.readAsDataURL(blob);
                })
                .catch(error => {
                    console.error('Image save error:', error);

                    window.webkit.messageHandlers.chatGPTImageData.postMessage({
                        error: String(error),
                        filename: filename
                    });
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
            createDownloadsDirectory()
        }

        // MARK: - Directory

        private func createDownloadsDirectory() {
            do {
                try FileManager.default.createDirectory(
                    at: downloadsDirectory,
                    withIntermediateDirectories: true
                )
            } catch {
                print("Downloads directory error: \(error)")
            }
        }

        // MARK: - Script messages

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            guard let body = message.body as? [String: Any] else {
                return
            }

            if message.name == "chatGPTImageAction" {
                guard let src = body["src"] as? String else {
                    return
                }

                let alt = body["alt"] as? String ?? ""
                showImageOptions(src: src, alt: alt)
            }

            if message.name == "chatGPTImageData" {
                if let error = body["error"] as? String {
                    showError("Không thể lấy ảnh: \(error)")
                    return
                }

                guard
                    let base64 = body["data"] as? String,
                    let data = Data(base64Encoded: base64)
                else {
                    showError("Dữ liệu ảnh không hợp lệ.")
                    return
                }

                let filename = body["filename"] as? String ?? "image.jpg"
                saveImageData(data, filename: filename)
            }
        }

        // MARK: - Image menu

        private func showImageOptions(src: String, alt: String) {
            let alert = UIAlertController(
                title: "Ảnh",
                message: alt.isEmpty ? "Chọn thao tác với ảnh." : alt,
                preferredStyle: .actionSheet
            )

            alert.addAction(
                UIAlertAction(
                    title: "Lưu vào Ảnh",
                    style: .default
                ) { [weak self] _ in
                    self?.requestImageData(src: src)
                }
            )

            alert.addAction(
                UIAlertAction(
                    title: "Tải ảnh về Tệp",
                    style: .default
                ) { [weak self] _ in
                    self?.requestImageData(src: src)
                }
            )

            alert.addAction(
                UIAlertAction(
                    title: "Hủy",
                    style: .cancel
                )
            )

            present(alert)
        }

        private func requestImageData(src: String) {
            let filename = Self.filenameFromURL(src)

            let script = """
            window.__chatGPTReadImage(
                \(Self.jsonString(src)),
                \(Self.jsonString(filename))
            );
            """

            webView?.evaluateJavaScript(
                script,
                completionHandler: { _, error in
                    if let error {
                        print("Image JavaScript error: \(error)")
                    }
                }
            )
        }

        // MARK: - Save image

        private func saveImageData(
            _ data: Data,
            filename: String
        ) {
            guard let image = UIImage(data: data) else {
                showError("Không thể đọc dữ liệu hình ảnh.")
                return
            }

            saveToPhotoLibrary(image)
            saveImageToFiles(data, filename: filename)
        }

        private func saveToPhotoLibrary(_ image: UIImage) {
            PHPhotoLibrary.requestAuthorization(for: .addOnly) {
                [weak self] status in

                guard let self else { return }

                guard status == .authorized || status == .limited else {
                    self.showError(
                        "Ứng dụng chưa được cấp quyền thêm ảnh vào thư viện."
                    )
                    return
                }

                PHPhotoLibrary.shared().performChanges({
                    PHAssetChangeRequest.creationRequestForAsset(
                        from: image
                    )
                }) { success, error in

                    DispatchQueue.main.async {
                        if success {
                            self.showMessage(
                                title: "Đã lưu ảnh",
                                message: "Ảnh đã được lưu vào ứng dụng Ảnh."
                            )
                        } else {
                            self.showError(
                                error?.localizedDescription ?? "Không thể lưu ảnh."
                            )
                        }
                    }
                }
            }
        }

        private func saveImageToFiles(
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

                print("Image saved to Files: \(destination.path)")

            } catch {
                print("Image file save error: \(error)")
            }
        }

        // MARK: - Download navigation

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

        // MARK: - Download confirmation

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

                    guard let self, let download else {
                        completionHandler(nil)
                        return
                    }

                    self.createDownloadsDirectory()

                    let destination = self.uniqueDestination(
                        filename: suggestedFilename
                    )

                    self.activeDownloads[
                        ObjectIdentifier(download)
                    ] = destination

                    completionHandler(destination)
                }
            )

            present(alert)
        }

        // MARK: - Download finished

        func downloadDidFinish(_ download: WKDownload) {
            let key = ObjectIdentifier(download)

            guard let destination = activeDownloads.removeValue(
                forKey: key
            ) else {
                showError("Không xác định được vị trí tệp đã tải.")
                return
            }

            let exists = FileManager.default.fileExists(
                atPath: destination.path
            )

            guard exists else {
                showError("Không tìm thấy tệp sau khi tải.")
                return
            }

            let attributes = try? FileManager.default.attributesOfItem(
                atPath: destination.path
            )

            let size = attributes?[.size] as? Int64 ?? 0

            guard size > 0 else {
                showError("Tệp tải xuống có dung lượng 0 byte.")
                return
            }

            showMessage(
                title: "Tải xuống thành công",
                message: """
                \(destination.lastPathComponent)

                Đã lưu vào:
                Tệp → Trên iPhone của tôi → ChatGPT → Downloads

                Dung lượng: \(ByteCountFormatter.string(
                    fromByteCount: size,
                    countStyle: .file
                ))
                """
            )
        }

        func download(
            _ download: WKDownload,
            didFailWithError error: Error,
            resumeData: Data?
        ) {
            activeDownloads.removeValue(
                forKey: ObjectIdentifier(download)
            )

            showError(
                "Tải xuống thất bại: \(error.localizedDescription)"
            )
        }

        // MARK: - File utilities

        private func uniqueDestination(filename: String) -> URL {
            let safeName = Self.safeFilename(filename)

            var destination = downloadsDirectory
                .appendingPathComponent(safeName)

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

        private static func filenameFromURL(_ value: String) -> String {
            guard
                let components = URLComponents(string: value),
                let name = components.path
                    .split(separator: "/")
                    .last
            else {
                return "image.jpg"
            }

            let filename = String(name)

            if filename.contains(".") {
                return safeFilename(filename)
            }

            return "\(filename).jpg"
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

        // MARK: - Alerts

        private func present(_ alert: UIAlertController) {
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

                if let popover = alert.popoverPresentationController {
                    popover.sourceView = presenter.view
                    popover.sourceRect = CGRect(
                        x: presenter.view.bounds.midX,
                        y: presenter.view.bounds.midY,
                        width: 1,
                        height: 1
                    )
                }

                presenter.present(alert, animated: true)
            }
        }

        private func showMessage(
            title: String,
            message: String
        ) {
            let alert = UIAlertController(
                title: title,
                message: message,
                preferredStyle: .alert
            )

            alert.addAction(
                UIAlertAction(title: "Đóng", style: .default)
            )

            present(alert)
        }

        private func showError(_ message: String) {
            showMessage(
                title: "Không thể thực hiện",
                message: message
            )
        }
    }
}
