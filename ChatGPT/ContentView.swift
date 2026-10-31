
import SwiftUI
import WebKit
import UIKit
import Photos

struct ContentView: View {
    var body: some View {
        GeometryReader { geometry in
            let screen = geometry.size
            let isPortrait = screen.height >= screen.width

            let ratio: CGFloat = isPortrait
                ? 9.0 / 17.5
                : 17.5 / 9.0

            let frameWidth = min(
                screen.width,
                screen.height * ratio
            )

            let frameHeight = min(
                screen.height,
                screen.width / ratio
            )

            ZStack {
                Color.black

                WebView()
                    .frame(
                        width: frameWidth,
                        height: frameHeight
                    )
                    .position(
                        x: screen.width / 2,
                        y: screen.height / 2
                    )
            }
            .frame(
                width: screen.width,
                height: screen.height
            )
            .background(Color.black)
        }
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
        .background(Color.black)
    }
}

struct WebView: UIViewRepresentable {

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        let contentController = WKUserContentController()

        let imageScript = """
        (function() {
            if (window.__nativeImageMenuInstalled) return;
            window.__nativeImageMenuInstalled = true;

            document.addEventListener('contextmenu', function(event) {
                const image = event.target.closest('img');
                if (!image) return;

                const src = image.currentSrc || image.src;
                if (!src) return;

                event.preventDefault();

                const filename = 'image_' + Date.now() + '.jpg';

                fetch(src, { credentials: 'include' })
                    .then(response => {
                        if (!response.ok) throw new Error('Image fetch failed');
                        return response.blob();
                    })
                    .then(blob => {
                        const reader = new FileReader();

                        reader.onloadend = function() {
                            window.webkit.messageHandlers.imageHandler.postMessage({
                                data: reader.result,
                                filename: filename,
                                mimeType: blob.type || 'image/jpeg'
                            });
                        };

                        reader.readAsDataURL(blob);
                    })
                    .catch(() => {
                        window.webkit.messageHandlers.imageHandler.postMessage({
                            url: src,
                            filename: filename
                        });
                    });
            }, true);
        })();
        """

        let script = WKUserScript(
            source: imageScript,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: false
        )

        contentController.addUserScript(script)
        contentController.add(context.coordinator, name: "imageHandler")

        configuration.userContentController = contentController
        configuration.websiteDataStore = .default()

        let webView = WKWebView(
            frame: .zero,
            configuration: configuration
        )

        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator

        context.coordinator.webView = webView

        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.scrollView.backgroundColor = .black
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.scrollView.alwaysBounceVertical = true
        webView.allowsBackForwardNavigationGestures = true

        webView.load(
            URLRequest(
                url: URL(string: "https://chatgpt.com/")!,
                cachePolicy: .useProtocolCachePolicy,
                timeoutInterval: 60
            )
        )

        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    static func dismantleUIView(
        _ uiView: WKWebView,
        coordinator: Coordinator
    ) {
        uiView.configuration.userContentController.removeScriptMessageHandler(
            forName: "imageHandler"
        )

        uiView.navigationDelegate = nil
        uiView.uiDelegate = nil
        coordinator.webView = nil
    }

    final class Coordinator: NSObject,
                             WKNavigationDelegate,
                             WKUIDelegate,
                             WKScriptMessageHandler,
                             WKDownloadDelegate {

        weak var webView: WKWebView?

        private var downloadDestinations: [ObjectIdentifier: URL] = [:]
        private var isPresentingController = false

        // MARK: Image handler

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            guard message.name == "imageHandler",
                  let payload = message.body as? [String: Any] else {
                return
            }

            if let dataURL = payload["data"] as? String,
               let commaIndex = dataURL.firstIndex(of: ",") {

                let encoded = String(dataURL[dataURL.index(after: commaIndex)...])

                guard let data = Data(base64Encoded: encoded),
                      !data.isEmpty else {
                    showMessage(
                        title: "Không thể lưu ảnh",
                        message: "Dữ liệu ảnh không hợp lệ."
                    )
                    return
                }

                let filename = payload["filename"] as? String ?? makeImageFilename()
                showImageOptions(data: data, filename: filename)

            } else if let urlString = payload["url"] as? String,
                      let url = URL(string: urlString) {

                downloadImageFromURL(
                    url,
                    filename: payload["filename"] as? String ?? makeImageFilename()
                )
            }
        }

        // MARK: Image download

        private func downloadImageFromURL(_ url: URL, filename: String) {
            var request = URLRequest(url: url)
            request.timeoutInterval = 60

            URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
                DispatchQueue.main.async {
                    guard let self = self else { return }

                    guard error == nil,
                          let response = response as? HTTPURLResponse,
                          (200...299).contains(response.statusCode),
                          let data = data,
                          !data.isEmpty else {

                        self.showMessage(
                            title: "Không thể tải ảnh",
                            message: "Máy chủ không cho phép tải ảnh này. Hãy thử ảnh khác."
                        )
                        return
                    }

                    self.showImageOptions(data: data, filename: filename)
                }
            }.resume()
        }

        // MARK: Image options

        private func showImageOptions(data: Data, filename: String) {
            guard let image = UIImage(data: data) else {
                showMessage(
                    title: "Ảnh không hợp lệ",
                    message: "Không thể đọc dữ liệu ảnh này."
                )
                return
            }

            presentActionSheet(
                title: "Lưu hình ảnh",
                message: "Bạn muốn lưu ảnh ở đâu?",
                actions: [
                    ("Lưu vào Ảnh", .default, { [weak self] in
                        self?.saveImageToPhotos(image)
                    }),
                    ("Lưu vào Tệp", .default, { [weak self] in
                        self?.saveDataToFiles(data, filename: filename)
                    })
                ]
            )
        }

        // MARK: Save to Photos

        private func saveImageToPhotos(_ image: UIImage) {
            PHPhotoLibrary.requestAuthorization(for: .addOnly) { [weak self] status in

                guard let self = self else { return }

                guard status == .authorized else {
                    DispatchQueue.main.async {
                        self.showMessage(
                            title: "Chưa được cấp quyền",
                            message: "Hãy cho phép ứng dụng thêm ảnh vào thư viện trong Cài đặt iPhone."
                        )
                    }
                    return
                }

                PHPhotoLibrary.shared().performChanges({
                    PHAssetChangeRequest.creationRequestForAsset(from: image)
                }) { success, error in

                    DispatchQueue.main.async {
                        if success {
                            self.showMessage(
                                title: "Đã lưu ảnh",
                                message: "Ảnh đã được lưu vào thư viện Ảnh."
                            )
                        } else {
                            self.showMessage(
                                title: "Không thể lưu ảnh",
                                message: error?.localizedDescription ?? "Đã xảy ra lỗi khi lưu ảnh."
                            )
                        }
                    }
                }
            }
        }

        // MARK: Save to Files

        private func saveDataToFiles(_ data: Data, filename: String) {
            do {
                let directory = try downloadsDirectory()
                let safeName = sanitizedFilename(filename)

                let destination = uniqueURL(
                    in: directory,
                    filename: safeName
                )

                try data.write(to: destination, options: .atomic)

                showMessage(
                    title: "Đã lưu tệp",
                    message: "Đã lưu \(destination.lastPathComponent) vào ChatGPT/Downloads trong ứng dụng Tệp."
                )

            } catch {
                showMessage(
                    title: "Lỗi lưu tệp",
                    message: error.localizedDescription
                )
            }
        }

        // MARK: Navigation downloads

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
            if !navigationResponse.canShowMIMEType {
                decisionHandler(.download)
            } else {
                decisionHandler(.allow)
            }
        }

        // MARK: New window

        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {

            if navigationAction.targetFrame == nil {
                webView.load(navigationAction.request)
            }

            return nil
        }

        // MARK: Download delegate

        func download(
            _ download: WKDownload,
            decideDestinationUsing response: URLResponse,
            suggestedFilename: String,
            completionHandler: @escaping (URL?) -> Void
        ) {
            do {
                let directory = try downloadsDirectory()
                let safeName = sanitizedFilename(suggestedFilename)

                let destination = uniqueURL(
                    in: directory,
                    filename: safeName
                )

                downloadDestinations[ObjectIdentifier(download)] = destination

                completionHandler(destination)

            } catch {
                completionHandler(nil)

                showMessage(
                    title: "Không thể tải tệp",
                    message: error.localizedDescription
                )
            }
        }

        func downloadDidFinish(_ download: WKDownload) {
            let key = ObjectIdentifier(download)
            let destination = downloadDestinations.removeValue(forKey: key)

            guard let destination = destination else {
                showMessage(
                    title: "Tải xuống hoàn tất",
                    message: "Hãy kiểm tra thư mục Downloads trong ứng dụng Tệp."
                )
                return
            }

            if FileManager.default.fileExists(atPath: destination.path) {
                showMessage(
                    title: "Tải xuống hoàn tất",
                    message: "Đã lưu \(destination.lastPathComponent) vào ChatGPT/Downloads trong ứng dụng Tệp."
                )
            } else {
                showMessage(
                    title: "Không tìm thấy tệp",
                    message: "Quá trình tải đã kết thúc nhưng không tìm thấy tệp tại vị trí lưu."
                )
            }
        }

        func download(
            _ download: WKDownload,
            didFailWithError error: Error,
            resumeData: Data?
        ) {
            downloadDestinations.removeValue(forKey: ObjectIdentifier(download))

            showMessage(
                title: "Tải xuống thất bại",
                message: error.localizedDescription
            )
        }

        // MARK: Directory

        private func downloadsDirectory() throws -> URL {
            let documents = FileManager.default.urls(
                for: .documentDirectory,
                in: .userDomainMask
            )[0]

            let directory = documents.appendingPathComponent(
                "Downloads",
                isDirectory: true
            )

            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )

            return directory
        }

        private func sanitizedFilename(_ filename: String) -> String {
            let invalidCharacters = CharacterSet(charactersIn: "/\\:?%*|\"<>")

            let cleaned = filename
                .components(separatedBy: invalidCharacters)
                .joined(separator: "_")
                .trimmingCharacters(in: .whitespacesAndNewlines)

            return cleaned.isEmpty
                ? "download_\(Int(Date().timeIntervalSince1970))"
                : cleaned
        }

        private func uniqueURL(in directory: URL, filename: String) -> URL {
            let original = URL(fileURLWithPath: filename)
            let name = original.deletingPathExtension().lastPathComponent
            let ext = original.pathExtension

            var candidate = directory.appendingPathComponent(filename)
            var index = 1

            while FileManager.default.fileExists(atPath: candidate.path) {
                let newName = ext.isEmpty
                    ? "\(name)_\(index)"
                    : "\(name)_\(index).\(ext)"

                candidate = directory.appendingPathComponent(newName)
                index += 1
            }

            return candidate
        }

        private func makeImageFilename() -> String {
            "image_\(Int(Date().timeIntervalSince1970)).jpg"
        }

        // MARK: Presentation

        private func topViewController() -> UIViewController? {
            guard let root = webView?.window?.rootViewController else {
                return nil
            }

            var current = root

            while let presented = current.presentedViewController {
                current = presented
            }

            return current
        }

        private func presentActionSheet(
            title: String,
            message: String,
            actions: [(String, UIAlertAction.Style, () -> Void)]
        ) {
            DispatchQueue.main.async { [weak self] in
                guard let self = self,
                      !self.isPresentingController,
                      let presenter = self.topViewController() else {
                    return
                }

                let alert = UIAlertController(
                    title: title,
                    message: message,
                    preferredStyle: .actionSheet
                )

                for item in actions {
                    alert.addAction(
                        UIAlertAction(title: item.0, style: item.1) { _ in
                            item.2()
                        }
                    )
                }

                alert.addAction(
                    UIAlertAction(title: "Hủy", style: .cancel)
                )

                if let popover = alert.popoverPresentationController {
                    popover.sourceView = presenter.view
                    popover.sourceRect = CGRect(
                        x: presenter.view.bounds.midX,
                        y: presenter.view.bounds.midY,
                        width: 1,
                        height: 1
                    )
                    popover.permittedArrowDirections = []
                }

                self.isPresentingController = true
                alert.presentationController?.delegate = self

                presenter.present(alert, animated: true)
            }
        }

        private func showMessage(title: String, message: String) {
            DispatchQueue.main.async { [weak self] in
                guard let self = self,
                      !self.isPresentingController,
                      let presenter = self.topViewController() else {
                    return
                }

                let alert = UIAlertController(
                    title: title,
                    message: message,
                    preferredStyle: .alert
                )

                alert.addAction(
                    UIAlertAction(title: "Đóng", style: .default)
                )

                self.isPresentingController = true
                alert.presentationController?.delegate = self

                presenter.present(alert, animated: true)
            }
        }
    }
}

extension WebView.Coordinator: UIAdaptivePresentationControllerDelegate {
    func presentationControllerDidDismiss(
        _ presentationController: UIPresentationController
    ) {
        isPresentingController = false
    }
}
