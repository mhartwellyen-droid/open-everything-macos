import AppKit
import SwiftUI
import WebKit

struct WebMPlayerView: View {
    let url: URL
    @State private var playbackError: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label(url.lastPathComponent, systemImage: "play.rectangle")
                    .lineLimit(1)
                Spacer()
                Button("Reveal in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
            }
            .padding(12)

            Divider()

            if let playbackError {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.video")
                        .font(.largeTitle)
                    Text("Video Couldn’t Be Played")
                        .font(.title3.weight(.semibold))
                    Text(playbackError)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                    Button("Reveal in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            } else {
                LocalWebMView(url: url, playbackError: $playbackError)
            }
        }
    }
}

private struct LocalWebMView: NSViewRepresentable {
    let url: URL
    @Binding var playbackError: String?

    func makeCoordinator() -> Coordinator {
        Coordinator(playbackError: $playbackError)
    }

    func makeNSView(context: Context) -> WKWebView {
        let view = WKWebView(frame: .zero)
        view.navigationDelegate = context.coordinator
        view.loadFileURL(url, allowingReadAccessTo: url)
        return view
    }

    func updateNSView(_ view: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate {
        @Binding var playbackError: String?

        init(playbackError: Binding<String?>) {
            _playbackError = playbackError
        }

        func webView(
            _ webView: WKWebView,
            didFailProvisionalNavigation navigation: WKNavigation!,
            withError error: Error
        ) {
            playbackError = error.localizedDescription
        }

        func webView(
            _ webView: WKWebView,
            didFail navigation: WKNavigation!,
            withError error: Error
        ) {
            playbackError = error.localizedDescription
        }
    }
}