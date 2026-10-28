import SwiftUI
import WebKit

struct ContentView: View {
    @State private var webView: WKWebView?
    @State private var isLoading = false

    var body: some View {
        GeometryReader { geometry in
            let landscape =
                geometry.size.width > geometry.size.height

            let ratio = landscape
                ? 17.5 / 9.0
                : 9.0 / 17.5

            let width = min(
                geometry.size.width,
                geometry.size.height * ratio
            )

            let height = width / ratio

            VStack(spacing: 0) {
                toolbar

                ChatGPTWebView(
                    webView: $webView,
                    isLoading: $isLoading
                )
                .frame(
                    maxWidth: .infinity,
                    maxHeight: .infinity
                )
                .clipped()
            }
            .frame(width: width, height: height)
            .background(Color(red: 0.07, green: 0.07, blue: 0.07))
            .frame(
                maxWidth: .infinity,
                maxHeight: .infinity
            )
            .background(Color.black)
        }
        .background(Color.black)
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            Button {
                webView?.openChatGPTSidebar()
            } label: {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 19, weight: .medium))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Mở thanh bên")

            Text("ChatGPT")
                .font(.system(size: 17, weight: .semibold))
                .lineLimit(1)

            Spacer(minLength: 4)

            if isLoading {
                ProgressView()
                    .tint(.white)
                    .frame(width: 32, height: 44)
            }

            Button {
                webView?.reload()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 17))
                    .frame(width: 40, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Tải lại")

            Button {
                if let webView {
                    if webView.canGoBack {
                        webView.goBack()
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
                Image(systemName: "arrow.left")
                    .font(.system(size: 17))
                    .frame(width: 40, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Quay lại")
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 6)
        .frame(height: 48)
        .background(
            Color(red: 0.10, green: 0.10, blue: 0.10)
        )
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.white.opacity(0.12))
                .frame(height: 0.5)
        }
    }
}

private struct ChatGPTWebView: UIViewRepresentable {
    @Binding var webView: WKWebView?
    @Binding var isLoading: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(isLoading: $isLoading)
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
        view.allowsBackForwardNavigationGestures = true

        // Ẩn chỉ báo cuộn gốc của iOS.
        view.scrollView.showsVerticalScrollIndicator = false
        view.scrollView.showsHorizontalScrollIndicator = false

        view.isOpaque = false
        view.backgroundColor = UIColor(
            red: 0.07,
            green: 0.07,
            blue: 0.07,
            alpha: 1
        )
        view.scrollView.backgroundColor = view.backgroundColor

        webView = view

        let url = URL(string: "https://chatgpt.com/")!
        view.load(URLRequest(url: url))

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
            if (document.getElementById(styleID)) return;

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

    final class Coordinator: NSObject, WKNavigationDelegate {
        @Binding var isLoading: Bool

        init(isLoading: Binding<Bool>) {
            _isLoading = isLoading
        }

        func webView(
            _ webView: WKWebView,
            didStartProvisionalNavigation navigation: WKNavigation!
        ) {
            isLoading = true
        }

        func webView(
            _ webView: WKWebView,
            didFinish navigation: WKNavigation!
        ) {
            isLoading = false

            webView.evaluateJavaScript(
                Self.hideScrollbarsScript,
                completionHandler: nil
            )
        }

        func webView(
            _ webView: WKWebView,
            didFail navigation: WKNavigation!,
            withError error: Error
        ) {
            isLoading = false
        }

        func webView(
            _ webView: WKWebView,
            didFailProvisionalNavigation navigation: WKNavigation!,
            withError error: Error
        ) {
            isLoading = false
        }

        private static let hideScrollbarsScript =
            ChatGPTWebView.hideScrollbarsScript
    }
}

private extension WKWebView {
    func openChatGPTSidebar() {
        let script = """
        (() => {
            const selectors = [
                'button[aria-label="Open sidebar"]',
                'button[aria-label="Close sidebar"]',
                'button[data-testid="open-sidebar-button"]',
                'button[aria-label*="sidebar" i]',
                'button[aria-label*="menu" i]'
            ];

            for (const selector of selectors) {
                const button = document.querySelector(selector);

                if (button && button.getClientRects().length > 0) {
                    button.click();
                    return true;
                }
            }

            return false;
        })();
        """

        evaluateJavaScript(script, completionHandler: nil)
    }
}
