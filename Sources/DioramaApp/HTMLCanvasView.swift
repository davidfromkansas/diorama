import SwiftUI
import WebKit
import DioramaCore

struct HTMLCanvasView: View {
    let session: Session
    let livePhase: ExecutionPhase?
    var activities: [CanvasActivity] = []
    var observedSummary = ActivitySummary()
    @State private var activityClock = Date()
    private var effectivePhase: ExecutionPhase? { livePhase ?? CanvasActivity.observedPhase(observedSummary, now: activityClock) }
    private var observationLabel: String? { livePhase == nil && effectivePhase != nil ? "Recent activity · " + (effectivePhase?.rawValue ?? "") : nil }
    private let canvas = ConversationCanvas()
    @State private var url: URL?
    @State private var document: ConversationCanvas.Document?
    @State private var error: String?
    @State private var paused = false

    private var canvasProvider: Provider { Provider.allCases.first { session.id.hasPrefix($0.rawValue + ":") } ?? session.provider }
    private var canvasSessionID: String { session.parentID != nil ? session.sessionID : session.id.hasPrefix(canvasProvider.rawValue + ":") ? String(session.id.dropFirst(canvasProvider.rawValue.count + 1)) : session.sessionID }
    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 12) {
                    Label(observationLabel ?? effectivePhase?.rawValue ?? "No recent activity", systemImage: effectivePhase == .working || effectivePhase == .submitting ? "circle.fill" : "doc.richtext")
                        .foregroundStyle(effectivePhase == .working || effectivePhase == .submitting ? Color.mint : Color.secondary)
                    Spacer()
                    Button(paused ? "Resume updates" : "Pause updates") { paused.toggle() }.pointingHand()
                    if let url {
                        Button("Open in browser") { NSWorkspace.shared.open(url) }.pointingHand()
                        Menu {
                            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }.pointingHand()
                            Button("Copy agent instructions") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(ConversationCanvas.instructions(for: url), forType: .string)
                            }.pointingHand()
                        } label: { Image(systemName: "ellipsis.circle") }.pointingHand()
                        .menuStyle(.borderlessButton).fixedSize()
                    }
                }
                if let document {
                    Text("Page saved \(document.modified.formatted(date: .abbreviated, time: .standard)) · \(paused ? "Updates paused" : "Watching for changes")")
                        .foregroundStyle(.secondary)
                }
                Text("Optional visual summary. Use Copy agent instructions and explicitly ask the agent to maintain this page.").foregroundStyle(.secondary)
                if let error { Text(error).foregroundStyle(.orange).textSelection(.enabled) }
            }.font(.caption).padding(.horizontal, 24).padding(.vertical, 12)
            Divider()
            if let document {
                CanvasWebView(html: document.html, phase: effectivePhase, activities: activities, statusLabel: observationLabel)
            } else if error != nil {
                ContentUnavailableView("HTML view unavailable", systemImage: "doc.richtext", description: Text("The page needs an accessible local working folder. Conversation and Activity remain available."))
            } else {
                ProgressView("Opening HTML view…").frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: session.id) {
            url = nil; document = nil; error = nil; paused = false
            do {
                url = try canvas.prepare(folder: session.project, provider: canvasProvider, sessionID: canvasSessionID, title: session.title)
            } catch { self.error = error.localizedDescription; return }
            while !Task.isCancelled {
                activityClock = Date()
                if !paused {
                    do {
                        // Revalidate the path after every atomic replacement or symlink change.
                        let checked = try canvas.location(folder: session.project, provider: canvasProvider, sessionID: canvasSessionID)
                        let next = try canvas.read(at: checked)
                        if document != next { document = next }
                        error = nil
                    } catch { self.error = error.localizedDescription }
                }
                do { try await Task.sleep(for: .seconds(1)) } catch { return }
            }
        }
    }
}

/// Sandboxed srcdoc with no same-origin access, network, forms, navigation, or native bridge.
/// The parent stays mounted and remembers scroll position when the document changes.
struct CanvasWebView: NSViewRepresentable {
    let html: String
    var phase: ExecutionPhase? = nil
    var activities: [CanvasActivity] = []

    var statusLabel: String? = nil
    func makeCoordinator() -> Coordinator { Coordinator(html: html, phase: phase, activities: activities, statusLabel: statusLabel) }
    func makeNSView(context: Context) -> WKWebView {
        let view = Self.makeWebView()
        view.navigationDelegate = context.coordinator
        view.loadHTMLString(Self.shell, baseURL: nil)
        return view
    }
    func updateNSView(_ view: WKWebView, context: Context) {
        if context.coordinator.html != html {
            context.coordinator.html = html
            context.coordinator.update(view)
        }
        if context.coordinator.phase != phase || context.coordinator.activities != activities || context.coordinator.statusLabel != statusLabel {
            context.coordinator.statusLabel = statusLabel
            context.coordinator.activities = activities
            context.coordinator.phase = phase
            context.coordinator.updatePhase(view)
        }
    }
    static func dismantleNSView(_ view: WKWebView, coordinator: Coordinator) {
        view.stopLoading(); view.navigationDelegate = nil
    }

    static func makeWebView() -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        config.preferences.javaScriptCanOpenWindowsAutomatically = false
        return WKWebView(frame: .zero, configuration: config)
    }

    static func prepared(_ html: String) -> String {
        // Native change detection replaces timer reloads. Keep refresh in the on-disk file.
        let refresh = #"(?is)<meta\b[^>]*\bhttp-equiv\s*=\s*["']?refresh\b[^>]*>"#
        return html.replacingOccurrences(of: refresh, with: "", options: .regularExpression)
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var html: String
        var ready = false
        var phase: ExecutionPhase?
        var activities: [CanvasActivity]
        var statusLabel: String?
        init(html: String, phase: ExecutionPhase? = nil, activities: [CanvasActivity] = [], statusLabel: String? = nil) { self.html = html; self.phase = phase; self.activities = activities; self.statusLabel = statusLabel }
        func updatePhase(_ view: WKWebView) {
            guard ready, let data = try? JSONEncoder().encode(phase?.rawValue ?? "Not connected"), let activityData = try? JSONEncoder().encode(activities), let labelData = try? JSONEncoder().encode(statusLabel) else { return }
            view.evaluateJavaScript("window.dioramaPhase(\(String(decoding: data, as: UTF8.self)), \(String(decoding: activityData, as: UTF8.self)), \(String(decoding: labelData, as: UTF8.self)))", completionHandler: nil)
        }
        func update(_ view: WKWebView) {
            guard ready, let data = try? JSONEncoder().encode(CanvasWebView.prepared(html) + CanvasLoaderRuntime.content) else { return }
            view.evaluateJavaScript("window.dioramaUpdate(\(String(decoding: data, as: UTF8.self)))", completionHandler: nil)
        }
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            ready = true; update(webView); updatePhase(webView)
        }
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void) {
            let url = navigationAction.request.url
            // Only the owned wrapper and its srcdoc document can navigate inside this view.
            decisionHandler(["about:blank", "about:srcdoc"].contains(url?.absoluteString ?? "") ? .allow : .cancel)
        }
    }

    static let shell = #"""
    <!doctype html><html><head><meta charset="utf-8">
    <meta http-equiv="Content-Security-Policy" content="default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; frame-src about:; img-src data: blob:; connect-src 'none'; base-uri 'none'; form-action 'none'">
    <style>html,body,iframe{margin:0;width:100%;height:100%;border:0;background:#f5f3ed;color-scheme:light dark}iframe{display:block;flex:1;min-height:0}body{display:flex;flex-direction:column}.signal{display:flex;align-items:center;gap:9px;padding:10px 24px;font:12px system-ui;color:#63685f;background:#f5f3ed;border-bottom:1px solid #cecec3}.signal-bars{display:flex;align-items:center;gap:3px;height:16px}.signal i{width:3px;height:12px;border-radius:2px;background:currentColor;transform:scaleY(.4)}.signal i:nth-child(2){animation-delay:.2s!important}.signal i:nth-child(3){animation-delay:.4s!important}.signal[data-active="true"]{color:#3459d4}.signal[data-active="true"] i{animation:pulse 1.8s cubic-bezier(.77,0,.175,1) infinite}.signal span{margin-left:auto;font-size:11px}.signal.updated span{animation:arrive 200ms cubic-bezier(.23,1,.32,1)}@keyframes pulse{50%{opacity:.45;transform:scaleY(1)}}@keyframes arrive{from{opacity:.35}to{opacity:1}}@media(prefers-reduced-motion:reduce){.signal[data-active="true"] i,.signal.updated span{animation:none}}@media(prefers-color-scheme:dark){.signal{background:#20231f;color:#b0b4a9;border-color:#484d43}.signal[data-active="true"]{color:#aec0ff}}</style>
    </head><body><div class="signal" id="signal" role="status"><div class="signal-bars" aria-hidden="true"><i></i><i></i><i></i></div><b id="execution">Not connected</b><span id="freshness">Saved canvas</span></div><iframe id="canvas" title="Conversation HTML view" sandbox="allow-scripts"></iframe>
    <script>
    const frame=document.getElementById('canvas');let scrollPosition=0;let disclosures={};let phase='Not connected';let hasPage=false;let activities=[];let observationLabel=null;let previousSections=new Map();let changedSections=[];
    function deliverPhase(){frame.contentWindow.postMessage({kind:'diorama-execution',phase,activities,changedSections,observationLabel},'*')}
    window.dioramaPhase=function(value,calls=[],label=null){phase=value;observationLabel=label;activities=calls;document.getElementById('execution').textContent=label||(value==='Working'&&calls.length?calls.map(c=>c.label).join(' · '):value);document.getElementById('execution').title=calls.map(c=>c.target).filter(Boolean).join('\n');document.getElementById('signal').dataset.active=String(value==='Working'||value==='Submitting');deliverPhase()};
    frame.addEventListener('load',deliverPhase);
    window.addEventListener('message',e=>{
      if(e.source!==frame.contentWindow||!e.data)return;
      if(e.data.kind==='diorama-scroll'&&Number.isFinite(e.data.y))scrollPosition=Math.max(0,e.data.y);
      if(e.data.kind==='diorama-details'&&Array.isArray(e.data.items)){
        disclosures=Object.fromEntries(e.data.items.slice(0,200).filter(v=>Array.isArray(v)&&typeof v[0]==='string'&&v[0].length<=128&&typeof v[1]==='boolean'));
      }
    });
    window.dioramaUpdate=function(html){
      const parsed=new DOMParser().parseFromString(html,'text/html');const nextSections=new Map();changedSections=[];
      parsed.querySelectorAll('section[id]').forEach(s=>{const signature=s.innerHTML;nextSections.set(s.id,signature);if(hasPage&&previousSections.get(s.id)!==signature)changedSections.push(s.id)});previousSections=nextSections;
      if(hasPage){document.getElementById('freshness').textContent='Canvas updated · '+new Date().toLocaleTimeString([], {hour:'2-digit',minute:'2-digit'});document.getElementById('signal').classList.remove('updated');requestAnimationFrame(()=>document.getElementById('signal').classList.add('updated'))}hasPage=true;
      const policy=`<meta http-equiv="Content-Security-Policy" content="default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; img-src data: blob:; font-src data:; connect-src 'none'; frame-src 'none'; media-src data:; object-src 'none'; base-uri 'none'; form-action 'none'">`;
      // Encode user-owned IDs as numeric code points; never interpolate HTML into a script.
      const state=JSON.stringify(Array.from(JSON.stringify(disclosures),c=>c.codePointAt(0)));
      const restore='<script>addEventListener("load",()=>{const saved=JSON.parse('+state+'.map(c=>String.fromCodePoint(c)).join(""));document.querySelectorAll("details[id]").forEach(d=>{if(Object.hasOwn(saved,d.id))d.open=saved[d.id]});scrollTo(0,'+scrollPosition+');document.addEventListener("toggle",()=>parent.postMessage({kind:"diorama-details",items:Array.from(document.querySelectorAll("details[id]")).slice(0,200).map(d=>[d.id,d.open])},"*"),true)});addEventListener("scroll",()=>parent.postMessage({kind:"diorama-scroll",y:scrollY},"*"),{passive:true});<\/script>';
      frame.srcdoc='<!doctype html>'+policy+html+restore;
    };
    </script></body></html>
    """#
}
