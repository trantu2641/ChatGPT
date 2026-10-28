import SwiftUI import WebKit

struct ContentView: View { @State private var webView: WKWebView?


var body: some View {
    ChatGPTWebView(webView: $webView)
        .background(Color(red: 0.07, green: 0.07, blue: 0.07))
        .ignoresSafeArea(.container, edges: [.top, .bottom])
}
}

private struct ChatGPTWebView: UIViewRepresentable { @Binding var webView: WKWebView?


func makeCoordinator() -> Coordinator {
    Coordinator()
}

func makeUIView(context: Context) -> WKWebView {
    let contentController = WKUserContentController()

    contentController.addUserScript(
        WKUserScript(
            source: Self.interfaceScript,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: false
        )
    )

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

    view.scrollView.showsVerticalScrollIndicator = false
    view.scrollView.showsHorizontalScrollIndicator = false
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

// MARK: - JavaScript

static let interfaceScript = """
(() => {
    if (window.__chatGPTInterfaceFixInstalled) {
        return;
    }

    window.__chatGPTInterfaceFixInstalled = true;

    const STYLE_ID = 'chatgpt-ios-interface-fixes';

    const CSS = `
        html,
        body,
        * {
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
            z-index: 9999 !important;
            flex-shrink: 0 !important;
            pointer-events: auto !important;
            isolation: isolate !important;
        }

        [data-chatgpt-ios-fixed-header="true"] button,
        [data-chatgpt-ios-fixed-header="true"] [role="button"] {
            pointer-events: auto !important;
            touch-action: manipulation !important;
        }
    `;

    function installStyle() {
        if (!document.documentElement) {
            return;
        }

        let style = document.getElementById(STYLE_ID);

        if (!style) {
            style = document.createElement('style');
            style.id = STYLE_ID;

            (document.head || document.documentElement)
                .appendChild(style);
        }

        if (style.textContent !== CSS) {
            style.textContent = CSS;
        }
    }

    function isVisible(element) {
        if (!(element instanceof HTMLElement)) {
            return false;
        }

        const rect = element.getBoundingClientRect();
        const css = window.getComputedStyle(element);

        return rect.width > 0 &&
               rect.height > 0 &&
               css.display !== 'none' &&
               css.visibility !== 'hidden';
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
            depth < 8
        ) {
            const rect = current.getBoundingClientRect();

            if (
                rect.width >= viewportWidth * 0.70 &&
                rect.height >= 36 &&
                rect.height <= 120 &&
                rect.top >= -10 &&
                rect.top < 150
            ) {
                candidate = current;
            }

            if (
                candidate &&
                rect.width >= viewportWidth * 0.85 &&
                rect.height >= 40 &&
                rect.height <= 100
            ) {
                break;
            }

            current = current.parentElement;
            depth++;
        }

        return candidate;
    }

    function updateInterface() {
        installStyle();

        document.querySelectorAll(
            '[data-chatgpt-ios-fixed-header="true"]'
        ).forEach(element => {
            element.removeAttribute(
                'data-chatgpt-ios-fixed-header'
            );
        });

        const menuButton = findMenuButton();

        if (!menuButton) {
            return;
        }

        const header = findHeader(menuButton);

        if (header) {
            header.setAttribute(
                'data-chatgpt-ios-fixed-header',
                'true'
            );
        }

        menuButton.style.setProperty(
            'pointer-events',
            'auto',
            'important'
        );
    }

    let scheduled = false;

    function scheduleUpdate() {
        if (scheduled) {
            return;
        }

        scheduled = true;

        requestAnimationFrame(() => {
            scheduled = false;
            updateInterface();
        });
    }

    function startObserver() {
        if (!document.documentElement) {
            setTimeout(startObserver, 100);
            return;
        }

        updateInterface();

        const observer = new MutationObserver(() => {
            scheduleUpdate();
        });

        observer.observe(document.documentElement, {
            childList: true,
            subtree: true,
            attributes: true,
            attributeFilter: [
                'aria-label',
                'data-testid',
                'class',
                'style',
                'hidden'
            ]
        });

        window.addEventListener(
            'resize',
            scheduleUpdate,
            { passive: true }
        );

        window.addEventListener(
            'orientationchange',
            () => setTimeout(scheduleUpdate, 200),
            { passive: true }
        );
    }

    if (document.readyState === 'loading') {
        document.addEventListener(
            'DOMContentLoaded',
            startObserver,
            { once: true }
        );
    } else {
        startObserver();
    }
})();
"""

// MARK: - Coordinator

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

    // MARK: - Navigation

    func webView(
        _ webView: WKWebView,
        didFinish navigation: WKNavigation!
    ) {
        webView.evaluateJavaScript(
            ChatGPTWebView.interfaceScript
        ) { _, error in
            if let error = error {
                print(
                    "Lỗi giao diện ChatGPT: " +
                    error.localizedDescription
                )
            }
        }
    }

    // MARK: - Detect downloads

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

    // MARK: - Save downloads

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

                destination =
                    downloadsDirectory.appendingPathComponent(
                        newName
                    )
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
            "Tải xuống thất bại: " +
            error.localizedDescription
        )
    }

    private static func safeFilename(
        _ filename: String
    ) -> String {
        let cleaned = filename
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "\\", with: "_")
            .trimmingCharacters(
                in: .whitespacesAndNewlines
            )

        return cleaned.isEmpty ? "download" : cleaned
    }
}
}
