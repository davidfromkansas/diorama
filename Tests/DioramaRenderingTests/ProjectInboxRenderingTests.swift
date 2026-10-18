import AppKit
import SwiftUI
import SceneKit
import Testing
@testable import DioramaApp
@testable import DioramaCore

@MainActor struct ProjectInboxRenderingTests {
    @Test func timestampUsesTimeTodayAndDateEarlier() {
        let now = Date(), yesterday = Calendar.current.date(byAdding: .day, value: -1, to: now)!
        #expect(InboxThreadRow.timestamp(now, received: false, now: now) == now.formatted(date: .omitted, time: .shortened))
        #expect(InboxThreadRow.timestamp(yesterday, received: false, now: now) == yesterday.formatted(date: .abbreviated, time: .shortened))
        #expect(InboxThreadRow.timestamp(now, received: true, now: now).hasPrefix("Received "))
    }

}

