
import SwiftUI
import WebKit
import UIKit
import Photos
import PhotosUI
import UniformTypeIdentifiers

// MARK: - Main View

struct ContentView: View {
    @StateObject private var store = WebViewStore()

    var body: some View {
        GeometryReader { geometry in
            let screen = geometry.size
            let portrait = screen.height >= screen.width
            let ratio: CGFloat = portrait ? 9.0 / 17.5 : 17.5 / 9.0

            let width = min(screen.width, screen.height * ratio)
            let height = min(screen.height, screen.width / ratio)

            ZStack {
                Color.black

                WebView(store: store)
                    .frame(width: width, height: height)
                    .position(
                        x: screen.width / 2,
                        y: screen.height / 2
                    )
            }
            .frame(width: screen.width, height: screen.height)
            .background(Color.black)
        }
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
    }
}

// MARK: - WebView Store

final class WebViewStore: ObservableObject {
    var webView: WKWebView?
    var coordinator: WebView.Coordinator?
}

// MARK: - WebView

struct WebView: UIViewRepresentable {

    let store: WebViewStore

    func makeCoordinator() -> Coordinator {
        if let coordinator = store.coordinator {
            return coordinator
        }

        let coordinator = Coordinator()
        store.coordinator = coordinator
        return coordinator
    }

    func makeUIView(context: Context) -> WKWebView {

        if let existing = store.webView {
            existing.navigationDelegate = context.coordinator
            existing.uiDelegate = context.coordinator
            context.coordinator.webView = existing
            return existing
        }

        let configuration = WKWebViewConfiguration()
        let controller = WKUserContentController()

        // MARK: Upload JavaScript

        let uploadScript = """
        (function() {
            if (window.__nativeUploadInstalled) return;
            window.__nativeUploadInstalled = true;

            window.__nativeUploadInput = null;

            window.__nativeFindUploadInput = function() {
                if (window.__nativeUploadInput &&
                    window.__nativeUploadInput.isConnected) {
                    return window.__nativeUploadInput;
                }

                const inputs = Array.from(
                    document.querySelectorAll('input[type="file"]')
                );

                return inputs.find(function(input) {
                    return !input.disabled;
                }) || null;
            };

            window.__nativeSetFiles = function(items) {
                const input = window.__nativeFindUploadInput();

                if (!input) {
                    window.webkit.messageHandlers.uploadResult.postMessage({
                        success: false,
                        reason: 'input_missing'
                    });
                    return;
                }

                try {
                    const transfer = new DataTransfer();

                    items.forEach(function(item) {
                        const binary = atob(item.data);
                        const bytes = new Uint8Array(binary.length);

                        for (let i = 0; i < binary.length; i++) {
                            bytes[i] = binary.charCodeAt(i);
                        }

                        const file = new File(
                            [bytes],
                            item.name,
                            { type: item.type || 'application/octet-stream' }
                        );

                        transfer.items.add(file);
                    });

                    input.files = transfer.files;

                    input.dispatchEvent(new Event('input', {
                        bubbles: true
                    }));

                    input.dispatchEvent(new Event('change', {
                        bubbles: true
                    }));

                    window.__nativeUploadInput = null;

                    window.webkit.messageHandlers.uploadResult.postMessage({
                        success: true
                    });

                } catch (error) {
                    console.error(error);

                    window.webkit.messageHandlers.uploadResult.postMessage({
                        success: false,
                        reason: String(error)
                    });
                }
            };

            document.addEventListener('click', function(event) {
                const target = event.target;

                if (!target || !target.closest) return;

                const input = target.closest('input[type="file"]');

                if (!input) return;

                event.preventDefault();
                event.stopPropagation();
                event.stopImmediatePropagation();

                window.__nativeUploadInput = input;

                window.webkit.messageHandlers.uploadHandler.postMessage({
                    multiple: input.multiple,
                    accept: input.accept || ''
                });
            }, true);
        })();
        """

        controller.addUserScript(
            WKUserScript(
                source: uploadScript,
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: false
            )
        )

        // MARK: Image Context Menu

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
                                filename: filename
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

        controller.addUserScript(
            WKUserScript(
                source: imageScript,
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: false
            )
        )

        controller.add(context.coordinator, name: "uploadHandler")
        controller.add(context.coordinator, name: "uploadResult")
        controller.add(context.coordinator, name: "imageHandler")

        configuration.userContentController = controller
        configuration.websiteDataStore = .default()

        let webView = WKWebView(
            frame: .zero,
            configuration: configuration
        )

        store.webView = webView
        context.coordinator.webView = webView

        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator

        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.scrollView.backgroundColor = .black

        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.scrollView.alwaysBounceVertical = true
        webView.scrollView.delaysContentTouches = false
        webView.scrollView.panGestureRecognizer.delaysTouchesBegan = false
        webView.scrollView.canCancelContentTouches = true
        webView.scrollView.isDirectionalLockEnabled = false
        webView.scrollView.keyboardDismissMode = .none

        webView.allowsBackForwardNavigationGestures = true

        let request = URLRequest(
            url: URL(string: "https://chatgpt.com/")!,
            cachePolicy: .useProtocolCachePolicy,
            timeoutInterval: 60
        )

        webView.load(request)

        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        // Do not reload during SwiftUI updates.
    }

    static func dismantleUIView(
        _ uiView: WKWebView,
        coordinator: Coordinator
    ) {
        // Keep WebView alive.
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject,
                             WKNavigationDelegate,
                             WKUIDelegate,
                             WKScriptMessageHandler,
                             WKDownloadDelegate,
                             UIImagePickerControllerDelegate,
                             UINavigationControllerDelegate,
                             PHPickerViewControllerDelegate,
                             UIDocumentPickerDelegate {

        weak var webView: WKWebView?

        private var isPresentingController = false
        private var isCameraOpen = false
        private var isPickerOpen = false

        private var needsWebRecovery = false
        private var isRecovering = false
        private var hasLoadedOnce = false

        private var savedConversationURL: URL?
        private var pendingUploadFiles: [UploadFile] = []

        private var allowsMultipleSelection = false
        private var downloadDestinations: [ObjectIdentifier: URL] = [:]

        private var activeNavigationURL: URL?

        private struct UploadFile {
            let data: Data
            let name: String
            let type: String
        }

        override init() {
            super.init()

            NotificationCenter.default.addObserver(
                self,
                selector: #selector(applicationDidBecomeActive),
                name: UIApplication.didBecomeActiveNotification,
                object: nil
            )
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
        }

        // MARK: Application State

        @objc private func applicationDidBecomeActive() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.recoverIfNeeded()
            }
        }

        private func saveCurrentConversation() {
            guard let url = webView?.url,
                  let scheme = url.scheme,
                  scheme == "https" else {
                return
            }

            savedConversationURL = url
        }

        private func recoverIfNeeded() {
            guard needsWebRecovery,
                  !isCameraOpen,
                  !isPickerOpen,
                  UIApplication.shared.applicationState == .active,
                  let webView = webView else {
                return
            }

            guard !isRecovering else {
                return
            }

            isRecovering = true
            needsWebRecovery = false

            let restoreURL = savedConversationURL
                ?? webView.url
                ?? URL(string: "https://chatgpt.com/")!

            print("Recovering ChatGPT WebView:", restoreURL.absoluteString)

            webView.stopLoading()

            var request = URLRequest(
                url: restoreURL,
                cachePolicy: .useProtocolCachePolicy,
                timeoutInterval: 60
            )

            request.setValue(
                "no-cache",
                forHTTPHeaderField: "Cache-Control"
            )

            webView.load(request)
        }

        // MARK: Navigation Delegate

        func webView(
            _ webView: WKWebView,
            didStartProvisionalNavigation navigation: WKNavigation!
        ) {
            activeNavigationURL = webView.url
        }

        func webView(
            _ webView: WKWebView,
            didFinish navigation: WKNavigation!
        ) {
            hasLoadedOnce = true
            isRecovering = false

            if let url = webView.url {
                savedConversationURL = url
            }

            if !pendingUploadFiles.isEmpty {
                let files = pendingUploadFiles
                pendingUploadFiles.removeAll()

                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    self.performUpload(files)
                }
            }
        }

        func webView(
            _ webView: WKWebView,
            didFail navigation: WKNavigation!,
            withError error: Error
        ) {
            isRecovering = false
            print("WebView navigation error:", error.localizedDescription)
        }

        func webView(
            _ webView: WKWebView,
            didFailProvisionalNavigation navigation: WKNavigation!,
            withError error: Error
        ) {
            isRecovering = false
            print("WebView provisional error:", error.localizedDescription)
        }

        func webViewWebContentProcessDidTerminate(
            _ webView: WKWebView
        ) {
            print("ChatGPT WebContent process terminated.")

            if let url = webView.url {
                savedConversationURL = url
            }

            needsWebRecovery = true

            // If the camera is still open, wait until it closes.
            if !isCameraOpen && !isPickerOpen {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    self.recoverIfNeeded()
                }
            }
        }

        // MARK: JavaScript Messages

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            guard let payload = message.body as? [String: Any] else {
                return
            }

            switch message.name {

            case "uploadHandler":
                allowsMultipleSelection =
                    payload["multiple"] as? Bool ?? false

                saveCurrentConversation()
                showUploadOptions()

            case "uploadResult":
                let success = payload["success"] as? Bool ?? false

                if !success {
                    let reason = payload["reason"] as? String ?? ""

                    showMessage(
                        title: "Không thể đính kèm",
                        message: reason == "input_missing"
                            ? "Không tìm thấy ô chọn tệp. Hãy mở lại nút đính kèm."
                            : "Không thể đưa ảnh vào ChatGPT. Hãy thử lại."
                    )
                }

            case "imageHandler":
                handleImageMessage(payload)

            default:
                break
            }
        }

        // MARK: Upload Menu

        private func showUploadOptions() {
            presentActionSheet(
                title: "Đính kèm",
                message: "Chọn cách thêm nội dung",
                actions: [
                    ("Camera", {
                        self.openCamera()
                    }),
                    ("Thư viện ảnh", {
                        self.openPhotoLibrary()
                    }),
                    ("Tệp", {
                        self.openDocumentPicker()
                    })
                ]
            )
        }

        // MARK: Camera

        private func openCamera() {
            guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
                showMessage(
                    title: "Camera không khả dụng",
                    message: "Thiết bị hiện không có camera khả dụng."
                )
                return
            }

            guard let presenter = topViewController() else {
                return
            }

            saveCurrentConversation()

            isCameraOpen = true

            let picker = UIImagePickerController()
            picker.sourceType = .camera
            picker.mediaTypes = [UTType.image.identifier]
            picker.allowsEditing = false
            picker.delegate = self

            presenter.present(picker, animated: true)
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            guard let image = info[.originalImage] as? UIImage,
                  let data = image.jpegData(compressionQuality: 0.92) else {
                picker.dismiss(animated: true) {
                    self.isCameraOpen = false
                    self.recoverIfNeeded()
                }
                return
            }

            let file = UploadFile(
                data: data,
                name: makeImageFilename(),
                type: "image/jpeg"
            )

            picker.dismiss(animated: true) {
                self.isCameraOpen = false
                self.pendingUploadFiles = [file]

                self.recoverIfNeeded()

                if !self.needsWebRecovery && !self.isRecovering {
                    self.pendingUploadFiles.removeAll()
                    self.performUpload([file])
                }
            }
        }

        func imagePickerControllerDidCancel(
            _ picker: UIImagePickerController
        ) {
            picker.dismiss(animated: true) {
                self.isCameraOpen = false
                self.recoverIfNeeded()
            }
        }

        // MARK: Photo Library

        private func openPhotoLibrary() {
            guard let presenter = topViewController() else {
                return
            }

            saveCurrentConversation()
            isPickerOpen = true

            var configuration = PHPickerConfiguration()
            configuration.filter = .images
            configuration.selectionLimit = allowsMultipleSelection ? 0 : 1

            let picker = PHPickerViewController(
                configuration: configuration
            )

            picker.delegate = self
            presenter.present(picker, animated: true)
        }

        func picker(
            _ picker: PHPickerViewController,
            didFinishPicking results: [PHPickerResult]
        ) {
            guard !results.isEmpty else {
                picker.dismiss(animated: true) {
                    self.isPickerOpen = false
                    self.recoverIfNeeded()
                }
                return
            }

            let group = DispatchGroup()
            let lock = NSLock()

            var files: [UploadFile] = []

            for result in results {
                group.enter()

                result.itemProvider.loadObject(ofClass: UIImage.self) {
                    object, error in

                    defer {
                        group.leave()
                    }

                    guard error == nil,
                          let image = object as? UIImage,
                          let data = image.jpegData(compressionQuality: 0.92) else {
                        return
                    }

                    let file = UploadFile(
                        data: data,
                        name: self.makeImageFilename(),
                        type: "image/jpeg"
                    )

                    lock.lock()
                    files.append(file)
                    lock.unlock()
                }
            }

            group.notify(queue: .main) {
                picker.dismiss(animated: true) {
                    self.isPickerOpen = false
                    self.pendingUploadFiles = files
                    self.recoverIfNeeded()

                    if !self.needsWebRecovery && !self.isRecovering {
                        self.pendingUploadFiles.removeAll()
                        self.performUpload(files)
                    }
                }
            }
        }

        // MARK: Document Picker

        private func openDocumentPicker() {
            guard let presenter = topViewController() else {
                return
            }

            saveCurrentConversation()
            isPickerOpen = true

            let picker = UIDocumentPickerViewController(
                forOpeningContentTypes: [.item],
                asCopy: true
            )

            picker.allowsMultipleSelection = allowsMultipleSelection
            picker.delegate = self

            presenter.present(picker, animated: true)
        }

        func documentPicker(
            _ controller: UIDocumentPickerViewController,
            didPickDocumentsAt urls: [URL]
        ) {
            let group = DispatchGroup()
            let lock = NSLock()

            var files: [UploadFile] = []

            for url in urls {
                group.enter()

                DispatchQueue.global(qos: .userInitiated).async {
                    defer {
                        group.leave()
                    }

                    do {
                        let data = try Data(contentsOf: url)

                        let file = UploadFile(
                            data: data,
                            name: url.lastPathComponent,
                            type: self.mimeType(for: url)
                        )

                        lock.lock()
                        files.append(file)
                        lock.unlock()

                    } catch {
                        // Skip unreadable files.
                    }
                }
            }

            group.notify(queue: .main) {
                self.isPickerOpen = false
                self.pendingUploadFiles = files
                self.recoverIfNeeded()

                if !self.needsWebRecovery && !self.isRecovering {
                    self.pendingUploadFiles.removeAll()
                    self.performUpload(files)
                }
            }
        }

        func documentPickerWasCancelled(
            _ controller: UIDocumentPickerViewController
        ) {
            isPickerOpen = false
            recoverIfNeeded()
        }

        // MARK: Upload Execution

        private func performUpload(_ files: [UploadFile]) {
            guard let webView = webView else {
                pendingUploadFiles = files
                return
            }

            guard !files.isEmpty else {
                return
            }

            guard !needsWebRecovery,
                  !isRecovering else {
                pendingUploadFiles = files
                return
            }

            let selectedFiles = allowsMultipleSelection
                ? files
                : Array(files.prefix(1))

            let items: [[String: String]] = selectedFiles.map {
                [
                    "data": $0.data.base64EncodedString(),
                    "name": $0.name,
                    "type": $0.type
                ]
            }

            guard let jsonData = try? JSONSerialization.data(
                withJSONObject: items
            ),
            let json = String(data: jsonData, encoding: .utf8) else {
                showMessage(
                    title: "Lỗi dữ liệu",
                    message: "Không thể chuẩn bị ảnh để gửi."
                )
                return
            }

            let script = """
            (function() {
                if (typeof window.__nativeSetFiles !== 'function') {
                    window.webkit.messageHandlers.uploadResult.postMessage({
                        success: false,
                        reason: 'handler_missing'
                    });
                    return;
                }

                window.__nativeSetFiles(\(json));
            })();
            """

            webView.evaluateJavaScript(script) { _, error in
                if let error = error {
                    print("Upload error:", error.localizedDescription)
                }
            }
        }

        // MARK: MIME Type

        private func mimeType(for url: URL) -> String {
            if let type = UTType(filenameExtension: url.pathExtension),
               let mime = type.preferredMIMEType {
                return mime
            }

            return "application/octet-stream"
        }

        // MARK: Image Context Menu

        private func handleImageMessage(_ payload: [String: Any]) {
            if let dataURL = payload["data"] as? String,
               let comma = dataURL.firstIndex(of: ",") {

                let encoded = String(dataURL[dataURL.index(after: comma)...])

                guard let data = Data(base64Encoded: encoded) else {
                    return
                }

                showImageOptions(
                    data: data,
                    filename: payload["filename"] as? String ?? makeImageFilename()
                )

            } else if let urlString = payload["url"] as? String,
                      let url = URL(string: urlString) {

                URLSession.shared.dataTask(with: url) {
                    data, _, error in

                    DispatchQueue.main.async {
                        guard error == nil, let data = data else {
                            self.showMessage(
                                title: "Không thể tải ảnh",
                                message: "Không thể lấy dữ liệu ảnh."
                            )
                            return
                        }

                        self.showImageOptions(
                            data: data,
                            filename: payload["filename"] as? String
                                ?? self.makeImageFilename()
                        )
                    }
                }.resume()
            }
        }

        private func showImageOptions(
            data: Data,
            filename: String
        ) {
            guard let image = UIImage(data: data) else {
                return
            }

            presentActionSheet(
                title: "Lưu hình ảnh",
                message: "Bạn muốn lưu ảnh ở đâu?",
                actions: [
                    ("Lưu vào Ảnh", {
                        self.saveImageToPhotos(image)
                    }),
                    ("Lưu vào Tệp", {
                        self.saveDataToFiles(data, filename: filename)
                    })
                ]
            )
        }

        // MARK: Save Photos

        private func saveImageToPhotos(_ image: UIImage) {
            PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
                guard status == .authorized || status == .limited else {
                    DispatchQueue.main.async {
                        self.showMessage(
                            title: "Chưa được cấp quyền",
                            message: "Hãy cấp quyền thêm ảnh trong Cài đặt iPhone."
                        )
                    }
                    return
                }

                PHPhotoLibrary.shared().performChanges({
                    PHAssetChangeRequest.creationRequestForAsset(from: image)
                }) { success, error in
                    DispatchQueue.main.async {
                        self.showMessage(
                            title: success ? "Đã lưu ảnh" : "Không thể lưu ảnh",
                            message: success
                                ? "Ảnh đã được lưu vào thư viện."
                                : (error?.localizedDescription ?? "Đã xảy ra lỗi.")
                        )
                    }
                }
            }
        }

        // MARK: Save Files

        private func saveDataToFiles(
            _ data: Data,
            filename: String
        ) {
            do {
                let directory = try downloadsDirectory()

                let destination = uniqueURL(
                    in: directory,
                    filename: sanitizedFilename(filename)
                )

                try data.write(to: destination, options: .atomic)

                showMessage(
                    title: "Đã lưu tệp",
                    message: "Đã lưu \(destination.lastPathComponent) vào ChatGPT/Downloads."
                )

            } catch {
                showMessage(
                    title: "Lỗi lưu tệp",
                    message: error.localizedDescription
                )
            }
        }

        // MARK: Navigation Policy

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
            if let response = navigationResponse.response as? HTTPURLResponse,
               let disposition = response.value(
                    forHTTPHeaderField: "Content-Disposition"
               ),
               disposition.localizedCaseInsensitiveContains("attachment") {
                decisionHandler(.download)
                return
            }

            decisionHandler(.allow)
        }

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

        // MARK: Downloads

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

        func download(
            _ download: WKDownload,
            decideDestinationUsing response: URLResponse,
            suggestedFilename: String,
            completionHandler: @escaping (URL?) -> Void
        ) {
            do {
                let directory = try downloadsDirectory()

                let destination = uniqueURL(
                    in: directory,
                    filename: sanitizedFilename(suggestedFilename)
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
            let destination = downloadDestinations.removeValue(
                forKey: ObjectIdentifier(download)
            )

            guard let destination = destination else {
                return
            }

            showMessage(
                title: "Tải xuống hoàn tất",
                message: "Đã lưu \(destination.lastPathComponent) vào ChatGPT/Downloads."
            )
        }

        func download(
            _ download: WKDownload,
            didFailWithError error: Error,
            resumeData: Data?
        ) {
            downloadDestinations.removeValue(
                forKey: ObjectIdentifier(download)
            )

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
            let invalid = CharacterSet(charactersIn: "/\\:?%*|\"<>")

            let cleaned = filename
                .components(separatedBy: invalid)
                .joined(separator: "_")
                .trimmingCharacters(in: .whitespacesAndNewlines)

            return cleaned.isEmpty
                ? "download_\(Int(Date().timeIntervalSince1970))"
                : cleaned
        }

        private func uniqueURL(
            in directory: URL,
            filename: String
        ) -> URL {
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
            actions: [(String, () -> Void)]
        ) {
            DispatchQueue.main.async {
                guard !self.isPresentingController,
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
                        UIAlertAction(title: item.0, style: .default) { _ in
                            self.isPresentingController = false
                            item.1()
                        }
                    )
                }

                alert.addAction(
                    UIAlertAction(title: "Hủy", style: .cancel) { _ in
                        self.isPresentingController = false
                    }
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
                presenter.present(alert, animated: true)
            }
        }

        private func showMessage(
            title: String,
            message: String
        ) {
            DispatchQueue.main.async {
                guard !self.isPresentingController,
                      let presenter = self.topViewController() else {
                    return
                }

                let alert = UIAlertController(
                    title: title,
                    message: message,
                    preferredStyle: .alert
                )

                alert.addAction(
                    UIAlertAction(title: "Đóng", style: .default) { _ in
                        self.isPresentingController = false
                    }
                )

                self.isPresentingController = true
                presenter.present(alert, animated: true)
            }
        }
    }
}
