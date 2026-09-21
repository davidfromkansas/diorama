import SwiftUI
import Testing
@testable import DioramaApp
@testable import DioramaCore

/// Offline visual fixture; never opens a provider connection or reads a conversation.
@MainActor struct ConversationPreviewTests {
    @Test func renderConversation() throws {
        for width in [520.0, 800.0] {
            let controller = ExecutionController()
            let view = VStack(alignment: .leading, spacing: 20) {
                HStack {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Polish the conversation interface").font(.headline)
                        Text("Codex · Last reported: Last turn finished · Observing").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "info.circle")
                }
                Divider()
                EntryView(entry: .init(id: "u", kind: "You", text: "Can you make the conversation easier to read and give it a familiar input box?", timestamp: nil))
                EntryView(entry: .init(id: "tool", kind: "Tool activity", text: "Read Sources/DioramaApp/ExecutionViews.swift", timestamp: nil))
                EntryView(entry: .init(id: "a", kind: "Assistant", text: "**The conversation layout is updated.**\n\n- A quieter header and clear message spacing.\n- A rounded composer below the conversation.\n- Tool details stay one click away.\n\n```swift\nConversationComposer(prompt: $prompt)\n```\n\nYou can keep validating the same execution flow.", timestamp: nil))
                Divider()
                LockedConversationComposer(checking: false, details: "Fixture writer conflict", retry: {})
                ConversationComposer(controller: controller, model: .constant(""), effort: .constant(""), prompt: .constant(""), attachments: .constant([]), approvalReview: .constant(.inherit), effectiveModel: "", sending: false, active: false, send: {})
            }.padding(24).frame(width: width).background(Color(white: 0.12)).environment(\.colorScheme, .dark)
            let host = NSHostingView(rootView: view)
            host.frame.size = host.fittingSize
            host.layoutSubtreeIfNeeded()
            let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            let png = try #require(bitmap.representation(using: .png, properties: [:]))
            try png.write(to: URL(fileURLWithPath: "/tmp/diorama-conversation-\(Int(width)).png"))
        }
    }
    @Test func renderActiveComposer() throws {
        let controller = ExecutionController()
        for width in [520.0, 800.0] {
            let view = ConversationComposer(controller: controller, model: .constant(""), effort: .constant(""), prompt: .constant("Please focus on the tests"), attachments: .constant([]), approvalReview: .constant(.inherit), effectiveModel: "", sending: false, active: true, canSteer: true, queued: true, queueMode: .constant(true), send: {})
                .padding(24).frame(width: width).background(Color(white: 0.12)).environment(\.colorScheme, .dark)
            let host = NSHostingView(rootView: view); host.frame.size = host.fittingSize; host.layoutSubtreeIfNeeded()
            let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            try #require(bitmap.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: "/tmp/diorama-active-\(Int(width)).png"))
        }
    }

}
