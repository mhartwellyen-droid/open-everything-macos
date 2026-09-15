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
        webView.loadHTMLString(
            Self.playerHTML,
            baseURL: Bundle.main.resourceURL
        )
        return webView
    }

    private static let playerHTML = """
    <!doctype html><html><head><meta charset="utf-8"><style>
    *{box-sizing:border-box}html,body{margin:0;width:100%;height:100%;overflow:hidden;background:#0a0a0d;color:#f5f5f7;font-family:-apple-system,sans-serif}
    body{display:grid;grid-template-rows:1fr auto;place-items:center;padding:20px;outline:none}
    canvas{width:min(calc((100vh - 110px)*1.0667),calc(100vw - 40px));height:auto;max-height:calc(100vh - 110px);aspect-ratio:256/240;image-rendering:pixelated;background:#000;border-radius:8px;box-shadow:0 18px 60px #000a}
    #help{padding:15px 8px 0;font-size:12px;color:#a1a1aa;text-align:center;user-select:none}
    kbd{display:inline-block;margin:0 2px;padding:2px 6px;background:#28282d;border:1px solid #45454d;border-radius:5px}
    </style></head><body tabindex="0"><canvas id="screen" width="256" height="240"></canvas>
    <div id="help">Move <kbd>↑</kbd><kbd>↓</kbd><kbd>←</kbd><kbd>→</kbd> &nbsp; A <kbd>Z</kbd> &nbsp; B <kbd>X</kbd> &nbsp; Start <kbd>Return</kbd> &nbsp; Select <kbd>Shift</kbd></div>
    <script src="jsnes.min.js"></script><script>
    const c=document.getElementById("screen"),x=c.getContext("2d",{alpha:false}),im=x.createImageData(256,240),px=new Uint32Array(im.data.buffer),aq=[];
    let ac,node,started=false,prev=performance.now(),pending=0;
    function audio(){if(ac){ac.resume();return}ac=new AudioContext({sampleRate:44100});node=ac.createScriptProcessor(1024,0,2);node.onaudioprocess=e=>{let l=e.outputBuffer.getChannelData(0),r=e.outputBuffer.getChannelData(1);for(let i=0;i<l.length;i++){let s=aq.shift();l[i]=s?s[0]:0;r[i]=s?s[1]:0}};node.connect(ac.destination)}
    const nes=new jsnes.NES({onFrame:f=>{for(let i=0;i<f.length;i++){let v=f[i];px[i]=0xff000000|((v&255)<<16)|(v&65280)|((v&16711680)>>>16)}x.putImageData(im,0,0)},onAudioSample:(l,r)=>{if(aq.length<8192)aq.push([l,r])},sampleRate:44100});
    const keys={ArrowUp:jsnes.Controller.BUTTON_UP,ArrowDown:jsnes.Controller.BUTTON_DOWN,ArrowLeft:jsnes.Controller.BUTTON_LEFT,ArrowRight:jsnes.Controller.BUTTON_RIGHT,z:jsnes.Controller.BUTTON_A,Z:jsnes.Controller.BUTTON_A,x:jsnes.Controller.BUTTON_B,X:jsnes.Controller.BUTTON_B,Enter:jsnes.Controller.BUTTON_START,Shift:jsnes.Controller.BUTTON_SELECT};
    addEventListener("keydown",e=>{let b=keys[e.key];if(b!==undefined){e.preventDefault();audio();nes.buttonDown(1,b)}});
    addEventListener("keyup",e=>{let b=keys[e.key];if(b!==undefined){e.preventDefault();nes.buttonUp(1,b)}});
    addEventListener("mousedown",audio);
    function tick(now){pending+=now-prev;prev=now;while(pending>=1000/60){nes.frame();pending-=1000/60}requestAnimationFrame(tick)}
    function loadBase64ROM(value){nes.loadROM(atob(value));document.body.focus();if(!started){started=true;prev=performance.now();requestAnimationFrame(tick)}return true}
    </script></body></html>
    """

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