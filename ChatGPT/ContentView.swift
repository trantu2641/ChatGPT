
import SwiftUI
import WebKit
import UIKit

struct ContentView: View {

    var body: some View {
        GeometryReader { geometry in

            let screen = geometry.size
            let portrait = screen.height >= screen.width

            let ratio: CGFloat = portrait
                ? 9.0 / 17.5
                : 17.5 / 9.0

            ChatGPTWebView()
                .aspectRatio(ratio, contentMode: .fit)
                .frame(
                    maxWidth: .infinity,
                    maxHeight: .infinity
                )
                .background(Color.black)
                .frame(
                    width: screen.width,
                    height: screen.height
                )
        }
        .background(Color.black)
        .ignoresSafeArea()
        .ignoresSafeArea(.keyboard)
        .preferredColorScheme(.dark)
    }
}

// MARK: - WebView

private struct ChatGPTWebView: UIViewRepresentable {

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> WKWebView {

        let configuration = WKWebViewConfiguration()

        configuration.websiteDataStore = .default()
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

        webView.scrollView.contentInsetAdjustmentBehavior = .never

        webView.isOpaque = true
        webView.backgroundColor = .black
        webView.scrollView.backgroundColor = .black

        webView.allowsLinkPreview = true

        context.coordinator.webView = webView

        if let url = URL(string: "https://chatgpt.com/") {
            webView.load(URLRequest(url: url))
        }

        return webView
    }

    func updateUIView(
        _ uiView: WKWebView,
        context: Context
    ) {
        uiView.scrollView.showsVerticalScrollIndicator = false
        uiView.scrollView.showsHorizontalScrollIndicator = false
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject,
                             WKNavigationDelegate,
                             WKUIDelegate,
                             WKDownloadDelegate {

        weak var webView: WKWebView?

        private var downloadFolder: URL {

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
                at: downloadFolder,
                withIntermediateDirectories: true
            )
        }

        // MARK: - Download

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

            do {
                try FileManager.default.createDirectory(
                    at: downloadFolder,
                    withIntermediateDirectories: true
                )

                let filename = Self.safeFilename(
                    suggestedFilename
                )

                var destination = downloadFolder
                    .appendingPathComponent(filename)

                if FileManager.default.fileExists(
                    atPath: destination.path
                ) {

                    let base = destination
                        .deletingPathExtension()
                        .lastPathComponent

                    let ext = destination.pathExtension

                    let suffix = UUID()
                        .uuidString
                        .prefix(8)

                    let newName = ext.isEmpty
                        ? "\(base)-\(suffix)"
                        : "\(base)-\(suffix).\(ext)"

                    destination = downloadFolder
                        .appendingPathComponent(newName)
                }

                completionHandler(destination)

            } catch {
                print("Download error: \(error)")
                completionHandler(nil)
            }
        }

        func downloadDidFinish(_ download: WKDownload) {
            print("Download completed: \(downloadFolder.path)")
        }

        func download(
            _ download: WKDownload,
            didFailWithError error: Error,
            resumeData: Data?
        ) {
            print("Download failed: \(error.localizedDescription)")
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
