import Foundation
import Testing
@testable import DioramaCore

struct PresentationTests {
    @Test func claudeBlockAndStringHistoryHideGoalStatus() throws {
        let text = "Evidence verified.\nDIORAMA_GOAL_12345678-1234-1234-1234-123456789012:COMPLETE"
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".jsonl")
        defer { try? FileManager.default.removeItem(at: file) }
        for content: Any in [text, [["type": "text", "text": text]]] {
            var data = try JSONSerialization.data(withJSONObject: ["type": "assistant", "message": ["content": content]])
            data.append(10); try data.write(to: file)
            let entries = SessionLibrary.readTranscript(url: file, provider: .claude).entries
            #expect(entries.count == 1)
            #expect(entries.first?.text.trimmingCharacters(in: .whitespacesAndNewlines) == "Evidence verified.")
        }
    }

    @Test func claudeCanvasInstructionsStaySeparateFromUserText() throws {
        let text = "Describe the image.\n<diorama_html_view>\nMaintain this conversation's live HTML view at the path: /tmp/test.html\n</diorama_html_view>"
        #expect(MessageContent.split(text, provider: .claude).map(\.context) == [false, true])
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".jsonl")
        defer { try? FileManager.default.removeItem(at: file) }
        var data = try JSONSerialization.data(withJSONObject: ["type": "user", "uuid": "test", "message": ["content": [["type": "text", "text": text]]]])
        data.append(10); try data.write(to: file)
        let entries = SessionLibrary.readTranscript(url: file, provider: .claude).entries
        #expect(entries.map(\.kind) == ["You", "System context"])
        #expect(entries.first?.text.contains("Describe the image.") == true)
    }

    func session(_ id: String, _ kind: SessionClassification, parent: String? = nil, provider: Provider = .codex, sid: String? = nil) -> Session {
        Session(id: id, provider: provider, url: URL(fileURLWithPath: "/test/\(id).jsonl"), sessionID: sid ?? id,
                title: id, project: "/project", modified: .distantPast, bytes: 0, archived: false,
                parentID: parent, classification: kind, classificationEvidence: "test metadata")
    }

    @Test func nestingVisibilityCountsAndSelection() {
        let sessions = [session("review", .internalReview), session("child", .subagent, parent: "main"),
                        session("orphan", .subagent, parent: "missing"), session("main", .conversation), session("unknown", .unknown)]
        let hidden = SessionPresentation.rows(sessions, showInternal: false)
        #expect(hidden.map(\.id) == ["orphan", "main", "child", "unknown"])
        #expect(hidden.first { $0.id == "child" }?.depth == 1)
        #expect(hidden.first { $0.id == "orphan" }?.label == "Subagent · parent unknown")
        #expect(SessionPresentation.selection("review", rows: hidden) == "main")
        #expect(SessionPresentation.selection("child", rows: hidden) == "child")
        #expect(SessionPresentation.rows(sessions, showInternal: true).count == 5)
        #expect(SessionPresentation.counts(sessions, showInternal: false) == "1 conversation · 2 subagents · 1 internal review hidden · 1 unknown")
        #expect(SessionPresentation.rows([sessions[0]], showInternal: false).isEmpty)
        #expect(SessionPresentation.selection("review", rows: []) == nil)
        #expect(SessionPresentation.selection(nil, rows: SessionPresentation.rows([sessions[0]], showInternal: true)) == "review")
    }

    @Test func noFalseParentLinksOrDroppedCycles() {
        let crossProvider = [session("c", .subagent, parent: "p"), session("p", .conversation, provider: .claude)]
        #expect(SessionPresentation.rows(crossProvider, showInternal: false).allSatisfy { $0.depth == 0 })
        let siblings = [session("a", .subagent, parent: "p", provider: .claude, sid: "p"), session("b", .subagent, parent: "p", provider: .claude, sid: "p")]
        #expect(SessionPresentation.rows(siblings, showInternal: false).allSatisfy { $0.depth == 0 })
        let cycle = [session("a", .subagent, parent: "b"), session("b", .subagent, parent: "a")]
        #expect(Set(SessionPresentation.rows(cycle, showInternal: false).map(\.id)).count == 2)
    }

    @Test func contextSplittingPreservesSurroundingUserTextAndExamples() {
        let context = "<environment_context>\n<cwd>/project</cwd><shell>zsh</shell>\n</environment_context>"
        let text = "Please help\n" + context + "\nwith this change."
        let parts = MessageContent.split(text, provider: .codex)
        #expect(parts.map(\.context) == [false, true, false])
        #expect(parts.map(\.text).joined() == text)
        for userText in ["<example>XML</example>", "<environment_context>example only</environment_context>", "```xml\n" + context + "\n```", "Show me " + context, "<environment_context>\n<cwd>/project</cwd><shell>zsh</shell>"] {
            #expect(MessageContent.split(userText, provider: .codex) == [.init(text: userText, context: false)])
        }
        #expect(MessageContent.split(context, provider: .claude).allSatisfy { !$0.context })
        let instructions = "# AGENTS.md instructions for /project\n\n<INSTRUCTIONS>\nUse tests.\n</INSTRUCTIONS>"
        #expect(MessageContent.split(instructions + "\nPlease fix this.", provider: .codex).map(\.context) == [true, false])
    }

    @Test func metadataOverridesReviewLookingTitlesAndStatesStayLocal() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        func write(_ name: String, _ records: [[String: Any]]) throws {
            var bytes = Data()
            for record in records { bytes.append(try JSONSerialization.data(withJSONObject: record)); bytes.append(10) }
            try bytes.write(to: root.appendingPathComponent(name + ".jsonl"))
        }
        func meta(_ id: String, _ source: String?) -> [String: Any] {
            var p: [String: Any] = ["id": id, "cwd": "/project"]
            if let source { p["thread_source"] = source }
            return ["type": "session_meta", "payload": p]
        }
        let user: [String: Any] = ["type": "response_item", "payload": ["type": "message", "role": "user", "content": "The following is the Codex agent history whose request action you are assessing."]]
        try write("main", [meta("main", "user"), user, ["type": "event_msg", "payload": ["type": "task_started"]]])
        try write("review", [meta("review", "guardian_review"), user, ["type": "event_msg", "payload": ["type": "task_complete"]]])
        try write("unknown", [meta("unknown", nil)])
        let library = SessionLibrary(roots: [.init(url: root, provider: .codex)])
        let snapshot = await library.scan()
        let main = try #require(snapshot.sessions.first { $0.sessionID == "main" })
        let review = try #require(snapshot.sessions.first { $0.sessionID == "review" })
        #expect(main.classification == .conversation)
        #expect(review.classification == .internalReview)
        #expect(review.title == "Internal approval review")
        #expect(review.classificationEvidence == "thread_source=guardian_review")
        #expect(snapshot.sessions.first { $0.sessionID == "unknown" }?.title == "Untitled conversation · unknown")
        #expect(await library.transcript(for: main).state == "Working")
        #expect(await library.transcript(for: review).state == "Last turn finished")
        let rows = SessionPresentation.rows(snapshot.sessions, showInternal: false)
        #expect(!rows.contains { $0.id == review.id })
        #expect(SessionPresentation.selection(nil, rows: rows) == main.id)
    }
}
