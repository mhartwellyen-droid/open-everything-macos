import SwiftUI
import WebKit

struct NESPlayerView: NSViewRepresentable {
    let romURL: URL

    func makeCoordinator() -> Coordinator {
        Coordinator(romURL: romURL)
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.mediaTypesRequiringUserActionForPlayback = []
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator

        guard
            let htmlURL = Bundle.module.url(
                forResource: "nes-player",
                withExtension: "html"
            )
        else {
            context.coordinator.errorMessage = "The NES player resource is missing."
            return webView
        }

        webView.loadFileURL(
            htmlURL,
            allowingReadAccessTo: htmlURL.deletingLastPathComponent()
        )
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        if context.coordinator.romURL != romURL {
            context.coordinator.romURL = romURL
            context.coordinator.loadROM(in: webView)
        }
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var romURL: URL
        var errorMessage: String?

        init(romURL: URL) {
            self.romURL = romURL
        }

        func webView(
            _ webView: WKWebView,
            didFinish navigation: WKNavigation!
        ) {
            loadROM(in: webView)
        }

        func loadROM(in webView: WKWebView) {
            do {
                let data = try Data(contentsOf: romURL)
                guard data.count >= 16 else {
                    throw PlayerError.invalidROM
                }
                let signature = Array(data.prefix(4))
                guard signature == [0x4e, 0x45, 0x53, 0x1a] else {
                    throw PlayerError.invalidROM
                }
                let base64 = data.base64EncodedString()
                webView.evaluateJavaScript("loadBase64ROM('\(base64)')") {
                    _, error in
                    if let error {
                        self.errorMessage = error.localizedDescription
                    }
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }

        enum PlayerError: LocalizedError {
            case invalidROM

            var errorDescription: String? {
                "This file is not a valid iNES ROM."
            }
        }
    }
}