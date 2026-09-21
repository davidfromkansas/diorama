import AppKit
import SwiftUI
import WebKit
import Testing
@testable import DioramaApp
@testable import DioramaCore

@MainActor struct HTMLCanvasViewTests {
    @Test func nativeTabWatchesAtomicEditsAndRetainsLastCompletePage() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("diorama-canvas-ui-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let canvas = ConversationCanvas()
        let url = try canvas.prepare(folder: root.path, provider: .codex, sessionID: "fixture", title: "Live canvas fixture")
        let original = try canvas.read(at: url).html
        var session = Session(id: "Codex:fixture", provider: .codex, url: nil, sessionID: "fixture", title: "Live canvas fixture", project: root.path, modified: Date(), bytes: 0, archived: false, parentID: nil)
        session.classification = .conversation
        let model = LibraryModel(); model.viewMode = .html
        let host = NSHostingView(rootView: SessionView(session: session, model: model).frame(width: 980, height: 1050).environment(\.colorScheme, .dark))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 980, height: 1050), styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host; window.orderBack(nil)
        defer { window.contentView = nil; window.orderOut(nil) }
        func webView(in parent: NSView) -> WKWebView? {
            if let web = parent as? WKWebView { return web }
            return parent.subviews.lazy.compactMap { webView(in: $0) }.first
        }
        for _ in 0..<100 {
            if webView(in: host) != nil { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        let web = try #require(webView(in: host))
        try await wait(web, for: "document.querySelector('iframe')?.srcdoc.includes('Live canvas fixture') === true")
        try Data("<html>partial update".utf8).write(to: url)
        try await Task.sleep(for: .milliseconds(1200))
        #expect(try await web.evaluateJavaScript("document.querySelector('iframe').srcdoc.includes('Live canvas fixture')") as? Bool == true)
        try Data(original.replacingOccurrences(of: "Live canvas fixture", with: "Batch completed").utf8).write(to: url, options: .atomic)
        try await wait(web, for: "document.querySelector('iframe')?.srcdoc.includes('Batch completed') === true")
        #expect(!model.execution.connected)
        #expect(model.execution.tasks["fixture"] == nil)
    }

    @Test func contextualLoadersFollowCallsAndOnlyRevealChangedSections() async throws {
        let view = CanvasWebView.makeWebView()
        view.configuration.userContentController.addUserScript(WKUserScript(source: "addEventListener('message',e=>{if(e.data?.kind==='loaderProbe')window.loaderProbe=e.data})", injectionTime: .atDocumentStart, forMainFrameOnly: true))
        let html = #"""
        <html><body><section id="work"><h1>Work</h1><div id="step" data-canvas-loader="step" data-canvas-activity="commandExecution"><span data-canvas-step-marker style="display:grid">1</span>Verify</div><div id="node" data-canvas-loader="halo" data-canvas-activity="commandExecution">Renderer</div><div id="image" data-canvas-loader="image" data-canvas-activity="imageGeneration"></div></section><section id="unchanged">Keep still</section>
        <script>addEventListener('message',e=>{if(e.data?.kind==='diorama-execution')setTimeout(()=>parent.postMessage({kind:'loaderProbe',dots:!!document.querySelector('.diorama-dots'),markerHidden:getComputedStyle(document.querySelector('[data-canvas-step-marker]')).display==='none',halo:document.getElementById('node').dataset.dioramaRunning,tiles:document.querySelectorAll('.diorama-image i').length,reveal:document.getElementById('work').classList.contains('diorama-changed'),unchanged:document.getElementById('unchanged').classList.contains('diorama-changed')},'*'),0)});</script></body></html>
        """#
        let coordinator = CanvasWebView.Coordinator(html: html, phase: .working, activities: [CanvasActivity(id: "cmd", tool: "commandExecution", label: "Running command", target: "swift test")])
        view.navigationDelegate = coordinator
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 700), styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = view; window.orderBack(nil)
        defer { view.stopLoading(); view.navigationDelegate = nil; window.orderOut(nil) }
        view.loadHTMLString(CanvasWebView.shell, baseURL: nil)
        try await wait(view, for: "window.loaderProbe?.dots === true && window.loaderProbe?.markerHidden === true && window.loaderProbe?.halo === 'true' && window.loaderProbe?.tiles === 0")
        coordinator.activities = [CanvasActivity(id: "img", tool: "imageGeneration", label: "Generating image", target: "")]
        coordinator.updatePhase(view)
        try await wait(view, for: "window.loaderProbe?.dots === false && window.loaderProbe?.halo === 'false' && window.loaderProbe?.tiles === 16")
        coordinator.html = html.replacingOccurrences(of: "<h1>Work</h1>", with: "<h1>Updated work</h1>")
        coordinator.update(view)
        try await wait(view, for: "window.loaderProbe?.reveal === true && window.loaderProbe?.unchanged === false")
        coordinator.phase = .finished; coordinator.updatePhase(view)
        try await wait(view, for: "window.loaderProbe?.tiles === 0 && window.loaderProbe?.dots === false")
    }

    private func wait(_ view: WKWebView, for expression: String) async throws {
        for _ in 0..<100 {
            if (try? await view.evaluateJavaScript(expression)) as? Bool == true { return }
            try await Task.sleep(for: .milliseconds(100))
        }
        print("CANVAS_DIAGNOSTIC", view.url as Any, (try? await view.evaluateJavaScript("JSON.stringify({url:location.href,update:typeof dioramaUpdate,source:document.querySelector('iframe')?.srcdoc?.length,fixture:window.fixture})")) as Any)
        Issue.record("Web view did not satisfy: \(expression)")
        throw AppServerFailure("HTML view timed out")
    }

    @Test func sandboxRendersAndUpdatesWithoutNativeOrParentAccess() async throws {
        let view = CanvasWebView.makeWebView()
        view.configuration.userContentController.addUserScript(WKUserScript(source: "addEventListener('message',e=>{if(e.data?.kind==='fixture')window.fixture=e.data;if(e.data?.kind==='blocked')window.blocked=e.data.directive;if(e.data?.kind==='scrollProbe')window.scrollProbe=e.data.y})", injectionTime: .atDocumentStart, forMainFrameOnly: true))
        let probe = #"""
        <script>addEventListener('securitypolicyviolation',e=>parent.postMessage({kind:'blocked',directive:e.violatedDirective},'*'));addEventListener('load',()=>{let isolated=false;try{parent.document.body}catch(e){isolated=true}parent.postMessage({kind:'fixture',isolated,goal:document.querySelector('h1').textContent,refresh:!!document.querySelector('meta[http-equiv="refresh"]'),native:!!window.webkit?.messageHandlers},'*');fetch('https://example.invalid/diorama-test').catch(()=>{})});</script>
        """#
        let html = ConversationCanvas.template(title: "A living conversation").replacingOccurrences(of: "</body>", with: probe + "</body>")
        let coordinator = CanvasWebView.Coordinator(html: html)
        view.navigationDelegate = coordinator
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 1050), styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = view
        window.orderBack(nil)
        defer { view.stopLoading(); view.navigationDelegate = nil; window.orderOut(nil) }
        view.loadHTMLString(CanvasWebView.shell, baseURL: nil)
        try await wait(view, for: "window.fixture?.goal === 'A living conversation'")
        #expect(try await view.evaluateJavaScript("window.fixture.isolated") as? Bool == true)
        #expect(try await view.evaluateJavaScript("window.fixture.refresh") as? Bool == false)
        #expect(try await view.evaluateJavaScript("window.fixture.native") as? Bool == false)
        try await wait(view, for: "window.blocked === 'connect-src'")
        #expect(try await view.evaluateJavaScript("document.querySelector('iframe').sandbox.value") as? String == "allow-scripts")
        let snapshot = try await view.takeSnapshot(configuration: nil)
        let bitmap = try #require(snapshot.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:)))
        let png = try #require(bitmap.representation(using: .png, properties: [:]))
        try png.write(to: URL(fileURLWithPath: "/tmp/diorama-html-view.png"))
        coordinator.html = html.replacingOccurrences(of: "A living conversation", with: "Updated goal")
        coordinator.update(view)
        try await wait(view, for: "window.fixture?.goal === 'Updated goal'")
        // Execution changes update the existing frame, even before the agent saves a page.
        let sourceBeforePhase = try await view.evaluateJavaScript("document.querySelector('iframe').srcdoc") as? String
        coordinator.phase = .working
        coordinator.updatePhase(view)
        try await wait(view, for: "document.getElementById('signal').dataset.active === 'true'")
        #expect(try await view.evaluateJavaScript("document.querySelector('iframe').srcdoc") as? String == sourceBeforePhase)
        for phase in [ExecutionPhase.approval, .input, .finished, .failed, .disconnected] {
            coordinator.phase = phase
            coordinator.updatePhase(view)
            try await wait(view, for: "document.getElementById('signal').dataset.active === 'false'")
        }
        let emptyProbe = "<script>addEventListener('message',e=>{if(e.data?.kind==='diorama-execution')setTimeout(()=>parent.postMessage({kind:'fixture',empty:document.getElementById('empty-heading').textContent,active:document.documentElement.dataset.agentActive},'*'),0)});</script>"
        coordinator.html = ConversationCanvas.template(title: "New task").replacingOccurrences(of: "</body>", with: emptyProbe + "</body>")
        coordinator.phase = .working
        coordinator.updatePhase(view)
        coordinator.update(view)
        try await wait(view, for: "window.fixture?.empty === 'The agent is working…' && window.fixture?.active === 'true'")
        coordinator.statusLabel = "Recent activity · Working"
        coordinator.updatePhase(view)
        try await wait(view, for: "window.fixture?.empty === 'Agent activity detected…' && window.fixture?.active === 'true'")
        coordinator.statusLabel = nil
        coordinator.phase = .approval
        coordinator.updatePhase(view)
        try await wait(view, for: "window.fixture?.empty === 'Waiting for your approval.' && window.fixture?.active === 'false'")
        // Native disclosures remain open after an agent replaces the document.
        coordinator.html = "<html><body><details id='evidence'><summary>Evidence</summary>Checked</details><script>addEventListener('load',()=>setTimeout(()=>document.querySelector('details').open=true,50));</script></body></html>"
        coordinator.update(view)
        try await wait(view, for: "disclosures.evidence === true")
        coordinator.html = "<html><body><details id='evidence'><summary>Evidence updated</summary>Checked again</details><script>addEventListener('load',()=>setTimeout(()=>parent.postMessage({kind:'fixture',open:document.querySelector('details').open},'*'),50));</script></body></html>"
        coordinator.update(view)
        try await wait(view, for: "window.fixture?.open === true")

        // A narrow viewport must reflow without horizontal scrolling.
        window.setContentSize(NSSize(width: 360, height: 1050))
        coordinator.html = ConversationCanvas.template(title: "A long goal that should wrap on a narrow screen").replacingOccurrences(of: "</body>", with: "<script>addEventListener('load',()=>setTimeout(()=>parent.postMessage({kind:'fixture',fits:document.documentElement.scrollWidth<=innerWidth},'*'),50));</script></body>")
        coordinator.update(view)
        try await wait(view, for: "window.fixture?.fits === true")
        let narrowSnapshot = try await view.takeSnapshot(configuration: nil)
        let narrowBitmap = try #require(narrowSnapshot.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:)))
        try #require(narrowBitmap.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: "/tmp/diorama-html-narrow.png"))
        window.setContentSize(NSSize(width: 1000, height: 1050))
        view.appearance = NSAppearance(named: .aqua)
        coordinator.html = html.replacingOccurrences(of: "A living conversation", with: "Light appearance")
        coordinator.update(view)
        try await wait(view, for: "window.fixture?.goal === 'Light appearance'")
        let lightSnapshot = try await view.takeSnapshot(configuration: nil)
        let lightBitmap = try #require(lightSnapshot.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:)))
        try #require(lightBitmap.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: "/tmp/diorama-html-light.png"))
        coordinator.html = "<html><body style='height:3000px'><script>addEventListener('load',()=>setTimeout(()=>{scrollTo(0,500);parent.postMessage({kind:'scrollProbe',y:scrollY},'*')},100));</script></body></html>"
        coordinator.update(view)
        try await wait(view, for: "window.scrollProbe === 500")
        try await view.evaluateJavaScript("window.scrollProbe = -1")
        coordinator.html = "<html><body style='height:3000px'><script>addEventListener('load',()=>setTimeout(()=>parent.postMessage({kind:'scrollProbe',y:scrollY},'*'),100));</script></body></html>"
        coordinator.update(view)
        try await wait(view, for: "window.scrollProbe === 500")
        // The parent remains mounted while its isolated child is replaced.
        #expect(coordinator.ready)
    }
}
