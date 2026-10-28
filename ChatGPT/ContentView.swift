import SwiftUI
import WebKit
import UIKit

struct ContentView: View {
    @State private var webView: WKWebView?
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            Color(red: 0.07, green: 0.07, blue: 0.07)
                .ignoresSafeArea()

            ChatGPTWebView(
                webView: $webView,
                isLoading: $isLoading,
                errorMessage: $errorMessage
            )
            .ignoresSafeArea()

            if isLoading {
                ProgressView()
                    .tint(.white)
                    .scaleEffect(1.2)
                    .padding(24)
                    .background(
                        Color.black.opacity(0.45),
                        in: RoundedRectangle(cornerRadius: 16)
                    )
                    .allowsHitTesting(false)
            }

            if let message = errorMessage {
                VStack(spacing: 16) {
                    Image(systemName: "wifi.exclamationmark")
                        .font(.system(size: 38))
                        .foregroundStyle(.white)

                    Text("Không thể tải ChatGPT")
                        .font(.headline)
                        .foregroundStyle(.white)

                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.75))
                        .multilineTextAlignment(.center)

                    Button {
                        errorMessage = nil
                        isLoading = true

                        if let webView {
                            if webView.url != nil {
                                webView.reload()
                            } else {
                                webView.load(
                                    URLRequest(
                                        url: URL(
                                            string: "https://chatgpt.com/"
                                        )!
                                    )
                                )
                            }
                        }
                    } label: {
                        Label("Thử lại", systemImage: "arrow.clockwise")
                            .fontWeight(.semibold)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 12)
                            .background(
                                Color.white.opacity(0.15),
                                in: Capsule()
                            )
                    }
                }
                .padding(28)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(red: 0.07, green: 0.07, blue: 0.07))
            }
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - ChatGPT WebView

private struct ChatGPTWebView: UIViewRepresentable {
    @Binding var webView: WKWebView?
    @Binding var isLoading: Bool
    @Binding var errorMessage: String?

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onLoadingChange: { loading in
                DispatchQueue.main.async {
                    isLoading = loading
                }
            },
            onError: { message in
                DispatchQueue.main.async {
                    errorMessage = message
                }
            }
        )
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()

        configuration.allowsInlineMediaPlayback = true
        configuration.websiteDataStore = .default()

        let contentController = WKUserContentController()

        let script = WKUserScript(
            source: Self.interfaceScript,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        )

        contentController.addUserScript(script)
        configuration.userContentController = contentController

        let view = WKWebView(
            frame: .zero,
            configuration: configuration
        )

        view.navigationDelegate = context.coordinator
        view.uiDelegate = context.coordinator

        view.allowsBackForwardNavigationGestures = true
        view.isOpaque = false
        view.backgroundColor = UIColor(
            red: 0.07,
            green: 0.07,
            blue: 0.07,
            alpha: 1
        )

        view.scrollView.backgroundColor = view.backgroundColor
        view.scrollView.isOpaque = false
        view.scrollView.showsVerticalScrollIndicator = false
        view.scrollView.showsHorizontalScrollIndicator = false
        view.scrollView.keyboardDismissMode = .interactive

        // Tránh trì hoãn thao tác cuộn không cần thiết.
        view.scrollView.delaysContentTouches = false

        context.coordinator.webView = view

        webView = view
        isLoading = true
        errorMessage = nil

        var request = URLRequest(
            url: URL(string: "https://chatgpt.com/")!
        )

        request.cachePolicy = .useProtocolCachePolicy
        request.timeoutInterval = 60

        view.load(request)

        return view
    }

    func updateUIView(
        _ uiView: WKWebView,
        context: Context
    ) {
        // Không gọi load() tại đây.
        // SwiftUI có thể gọi updateUIView nhiều lần.
        // Tải lại tại đây sẽ gây giật lag và mất trạng thái trang.
        uiView.scrollView.showsVerticalScrollIndicator = false
        uiView.scrollView.showsHorizontalScrollIndicator = false
    }

    // MARK: - Lightweight JavaScript

    private static let interfaceScript = """
    (() => {
        'use strict';

        if (window.__chatGPTInterfaceFixInstalled) {
            return;
        }

        window.__chatGPTInterfaceFixInstalled = true;

        const STYLE_ID = 'chatgpt-ios-interface-fixes';
        let observer = null;
        let scheduled = false;
        let lastHeader = null;

        const CSS = `
            html,
            body {
                scrollbar-width: none !important;
                -ms-overflow-style: none !important;
            }

            ::-webkit-scrollbar {
                display: none !important;
                width: 0 !important;
                height: 0 !important;
            }

            button,
            [role="button"] {
                -webkit-tap-highlight-color: transparent;
            }

            [data-chatgpt-ios-fixed-header="true"] {
                position: sticky !important;
                top: 0 !important;
                z-index: 100 !important;
                flex-shrink: 0 !important;
            }

            [data-chatgpt-ios-fixed-header="true"] button,
            [data-chatgpt-ios-fixed-header="true"] [role="button"] {
                pointer-events: auto !important;
                touch-action: manipulation !important;
            }
        `;

        function installStyle() {
            if (!document.head) {
                return;
            }

            let style = document.getElementById(STYLE_ID);

            if (!style) {
                style = document.createElement('style');
                style.id = STYLE_ID;
                style.textContent = CSS;
                document.head.appendChild(style);
            }
        }

        function isVisible(element) {
            if (!(element instanceof HTMLElement)) {
                return false;
            }

            const rect = element.getBoundingClientRect();

            return rect.width > 0 &&
                   rect.height > 0 &&
                   getComputedStyle(element).display !== 'none' &&
                   getComputedStyle(element).visibility !== 'hidden';
        }

        function findMenuButton() {
            const selectors = [
                'button[data-testid="open-sidebar-button"]',
                'button[data-testid*="sidebar"]',
                'button[aria-label*="sidebar" i]',
                'button[aria-label*="side bar" i]',
                'button[aria-label*="menu" i]',
                'button[aria-label*="lịch sử" i]',
                'button[aria-label*="thanh bên" i]',
                '[role="button"][aria-label*="sidebar" i]',
                '[role="button"][aria-label*="menu" i]'
            ];

            for (const selector of selectors) {
                let elements;

                try {
                    elements = document.querySelectorAll(selector);
                } catch (_) {
                    continue;
                }

                for (const element of elements) {
                    if (isVisible(element)) {
                        return element;
                    }
                }
            }

            return null;
        }

        function findHeader(button) {
            if (!button) {
                return null;
            }

            const viewportWidth =
                document.documentElement.clientWidth ||
                window.innerWidth;

            let current = button.parentElement;
            let candidate = null;
            let depth = 0;

            while (
                current &&
                current !== document.body &&
                depth < 6
            ) {
                const rect = current.getBoundingClientRect();

                if (
                    rect.width >= viewportWidth * 0.75 &&
                    rect.height >= 36 &&
                    rect.height <= 120 &&
                    rect.top >= -10 &&
                    rect.top < 150
                ) {
                    candidate = current;
                }

                current = current.parentElement;
                depth++;
            }

            return candidate;
        }

        function updateInterface() {
            scheduled = false;
            installStyle();

            const menuButton = findMenuButton();
            const header = findHeader(menuButton);

            if (header === lastHeader) {
                return;
            }

            if (lastHeader && lastHeader.isConnected) {
                lastHeader.removeAttribute(
                    'data-chatgpt-ios-fixed-header'
                );
            }

            lastHeader = header;

            if (header) {
                header.setAttribute(
                    'data-chatgpt-ios-fixed-header',
                    'true'
                );
            }
        }

        function scheduleUpdate() {
            if (scheduled) {
                return;
            }

            scheduled = true;

            window.setTimeout(updateInterface, 250);
        }

        function start() {
            installStyle();
            updateInterface();

            if (observer) {
                observer.disconnect();
            }

            // Chỉ quan sát việc thêm hoặc xóa node.
            // Không theo dõi class/style để tránh vòng lặp
            // và giảm chi phí xử lý DOM.
            observer = new MutationObserver(scheduleUpdate);

            observer.observe(document.body || document.documentElement, {
                childList: true,
                subtree: true
            });

            window.addEventListener(
                'resize',
                scheduleUpdate,
                { passive: true }
            );

            window.addEventListener(
                'pageshow',
                scheduleUpdate,
                { passive: true }
            );
        }

        if (document.readyState === 'loading') {
            document.addEventListener(
                'DOMContentLoaded',
                start,
                { once: true }
            );
        } else {
            start();
        }
    })();
    """
}

// MARK: - WebView Coordinator

private final class Coordinator: NSObject,
                                WKNavigationDelegate,
                                WKUIDelegate,
                                WKDownloadDelegate {

    weak var webView: WKWebView?

    private let onLoadingChange: (Bool) -> Void
    private let onError: (String) -> Void

    private var hasShownMainFrameError = false

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

    init(
        onLoadingChange: @escaping (Bool) -> Void,
        onError: @escaping (String) -> Void
    ) {
        self.onLoadingChange = onLoadingChange
        self.onError = onError

        super.init()

        try? FileManager.default.createDirectory(
            at: downloadsDirectory,
            withIntermediateDirectories: true
        )
    }

    // MARK: Navigation lifecycle

    func webView(
        _ webView: WKWebView,
        didStartProvisionalNavigation navigation: WKNavigation!
    ) {
        hasShownMainFrameError = false
        onLoadingChange(true)
        onError("")
    }

    func webView(
        _ webView: WKWebView,
        didFinish navigation: WKNavigation!
    ) {
        onLoadingChange(false)
        onError("")
    }

    func webView(
        _ webView: WKWebView,
        didFail navigation: WKNavigation!,
        withError error: Error
    ) {
        handleNavigationError(error)
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        handleNavigationError(error)
    }

    private func handleNavigationError(_ error: Error) {
        let nsError = error as NSError

        // Bỏ qua các lỗi do người dùng chủ động dừng tải.
        if nsError.code == NSURLErrorCancelled {
            onLoadingChange(false)
            return
        }

        onLoadingChange(false)

        if !hasShownMainFrameError {
            hasShownMainFrameError = true

            onError(
                "Không thể kết nối hoặc tải trang. " +
                "Hãy kiểm tra kết nối Internet rồi thử lại. " +
                "(\(nsError.localizedDescription))"
            )
        }
    }

    // MARK: Recover WebKit process termination

    func webViewWebContentProcessDidTerminate(
        _ webView: WKWebView
    ) {
        // WebKit có thể kết thúc tiến trình khi thiếu bộ nhớ.
        // Không tự tải lại liên tục vì có thể gây vòng lặp.
        onLoadingChange(false)

        onError(
            "Tiến trình hiển thị trang đã bị dừng. " +
            "Nhấn Thử lại để tải lại ChatGPT."
        )
    }

    // MARK: Download detection

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

    // MARK: Save downloaded files

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

            let filename = Self.safeFilename(suggestedFilename)

            var destination = downloadsDirectory
                .appendingPathComponent(filename)

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

                let newName: String

                if ext.isEmpty {
                    newName = "\(base)-\(suffix)"
                } else {
                    newName = "\(base)-\(suffix).\(ext)"
                }

                destination = downloadsDirectory
                    .appendingPathComponent(newName)
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
            "Tải xuống thành công: \(downloadsDirectory.path)"
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

    private static func safeFilename(_ filename: String) -> String {
        let cleaned = filename
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "\\", with: "_")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if cleaned.isEmpty || cleaned == "." || cleaned == ".." {
            return "download"
        }

        return cleaned
    }
}
