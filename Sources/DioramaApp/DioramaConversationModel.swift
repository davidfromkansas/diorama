import Foundation
import Observation
import DioramaCore

@Observable final class DioramaConversationModel {
    var records: [DioramaConversation] = []
    var error: String?
    var switching = Set<String>()
    var queueOperations = Set<String>()
    let file: URL
    private var readable = true
    init(file: URL = ConversationStorage.file) {
        self.file = file
        do { records = try ConversationStorage.load(file) }
        catch { self.error = error.localizedDescription; readable = false }
    }
    func save() throws {
        guard readable else { throw AppServerFailure("Conversation storage unavailable. Restore it before switching providers.") }
        try ConversationStorage.save(records, to: file)
    }
    func record(_ id: String) -> DioramaConversation? { records.first { $0.id == id || $0.contains(id) } }
    func project(_ sessions: [Session]) -> [Session] {
        var seen = Set<String>()
        return sessions.compactMap { session in
            guard let record = record(session.sessionID) else { return seen.insert(session.id).inserted ? session : nil }
            guard session.sessionID == record.activeID, seen.insert(record.id).inserted else { return nil }
            return record.session(using: session)
        }
    }
}

extension LibraryModel {
    func switchProvider(from session: Session, model: String) async throws -> Session {
        guard !conversations.switching.contains(session.id) else { throw AppServerFailure("A model switch is already in progress") }
        guard !outgoing.values.contains(where: { $0.sessionID == session.sessionID && [.pending, .uncertain].contains($0.state) }) else { throw AppServerFailure("Resolve the pending message before switching providers.") }
        guard conversations.record(session.id)?.carried.contains(where: { $0.destinationID != nil }) != true else { throw AppServerFailure("Finish the pending queued-message transfer before switching providers again.") }
        conversations.switching.insert(session.id); defer { conversations.switching.remove(session.id) }
        try conversations.save()
        if !execution.connected { await execution.connect() }
        try await execution.resumeImported(session)
        await execution.loadWorkflow(id: session.sessionID)
        guard execution.tasks[session.sessionID]?.phase.active != true else { throw AppServerFailure("Finish or stop the current turn before switching providers.") }
        // Refresh saved native history before freezing the segment; live entries are merged by nativeTranscript.
        let saved = await library.transcript(for: session, limit: 5000)
        guard saved.error == nil || execution.tasks[session.sessionID]?.transcript.entries.isEmpty == false else { throw AppServerFailure("Conversation history unavailable. No provider switch was made.") }
        transcript = saved; transcriptSessionID = session.id
        let nativeEntries = nativeTranscript.entries
        var record = conversations.record(session.id) ?? DioramaConversation(session: session, model: execution.tasks[session.sessionID]?.model ?? "")
        record.segments[record.segments.count - 1].history = nativeEntries
        let project = projects.projects.first { $0.workspaces.contains { $0.threadID == session.sessionID } }
        let work = project?.workspaces.first { $0.threadID == session.sessionID }
        let context = work.map { $0.context.prompt(folder: $0.folder, commit: $0.baseCommit) } ?? ""
        let handoff = DioramaConversation.handoff(title: record.title, folder: record.folder, entries: record.precedingEntries() + nativeEntries, goal: execution.tasks[session.sessionID]?.workflow.goal ?? .null, projectContext: context)
        let targetID = try await execution.prepareProviderSwitch(session: session, model: model, handoff: handoff)
        guard let target = execution.tasks[targetID]?.session else { throw AppServerFailure("New provider session unavailable. No message was sent.") }
        for row in execution.tasks[session.sessionID]?.workflow.queue ?? [] {
            if !record.carried.contains(where: { $0.sourceID == session.sessionID && $0.row["id"] == row["id"] }) {
                record.carried.append(CarriedSubmission(sourceID: session.sessionID, row: row, provider: session.provider, folder: session.project))
            }
        }
        record.segments.append(ConversationSegment(nativeID: targetID, provider: target.provider, model: model, handoff: handoff))
        let previous = conversations.records
        conversations.records.removeAll { $0.id == record.id }; conversations.records.append(record)
        do { try conversations.save() } catch { conversations.records = previous; throw error }
        execution.registerActivityConversation(record.segments.compactMap { segment in Provider(rawValue: segment.provider).map { ActivitySessionIdentity(provider: $0, id: segment.nativeID) } })
        execution.retireProviderSession(session.sessionID)
        // Membership is authoritative. The existing workspace object retains branch, base, context and PR.
        if let project, let work { projects.updateWorkspace(project.id, id: work.id) { $0.threadID = targetID } }
        transcript = Transcript(); transcriptSessionID = record.id
        syncOwnedSessions(); selectedID = record.id
        return record.session(using: target)
    }
    func restoreConversationMembership() {
        for record in conversations.records {
            execution.registerActivityConversation(record.segments.compactMap { segment in Provider(rawValue: segment.provider).map { ActivitySessionIdentity(provider: $0, id: segment.nativeID) } })
            if let first = record.segments.first, let provider = Provider(rawValue: first.provider) {
                execution.conversationCanvasIdentity[record.activeID] = (provider, first.nativeID)
            }
            for segment in record.segments.dropLast() { execution.retireProviderSession(segment.nativeID) }
            for p in projects.projects {
                for w in p.workspaces where w.threadID != record.activeID && w.threadID.map(record.contains) == true {
                    projects.updateWorkspace(p.id, id: w.id) { $0.threadID = record.activeID }
                }
            }
        }
    }
    func removeCarriedQueue(conversationID: String, submissionID: String) async throws {
        guard conversations.queueOperations.insert(conversationID).inserted else { throw AppServerFailure("A queue operation is already in progress") }
        defer { conversations.queueOperations.remove(conversationID) }
        guard let index = conversations.records.firstIndex(where: { $0.id == conversationID }),
              let item = conversations.records[index].carried.first(where: { $0.id == submissionID }), item.destinationID == nil else { throw AppServerFailure("Resolve the pending queue transfer before removing this message.") }
        try await execution.deleteCarriedSource(item)
        conversations.records[index].carried.removeAll { $0.id == submissionID }; try conversations.save()
    }
    func resumeCarriedQueue(conversationID: String, submissionID: String) async throws {
        guard conversations.queueOperations.insert(conversationID).inserted else { throw AppServerFailure("A queue operation is already in progress") }
        defer { conversations.queueOperations.remove(conversationID) }
        guard let index = conversations.records.firstIndex(where: { $0.id == conversationID }),
              let item = conversations.records[index].carried.firstIndex(where: { $0.id == submissionID }),
              let session = selected, session.id == conversationID else { throw AppServerFailure("Queued message unavailable") }
        try await execution.resumeImported(session)
        var carried = conversations.records[index].carried[item]
        guard carried.destinationID == nil || carried.destinationID == session.sessionID else { throw AppServerFailure("This message already has a pending transfer to a previous provider. Resolve it before switching again.") }
        if carried.destinationSubmission == nil {
            // Persist the destination before the request. Retrying uses the same client identity.
            carried.destinationID = session.sessionID
            conversations.records[index].carried[item] = carried; try conversations.save()
            carried.destinationSubmission = try await execution.importCarriedSubmission(id: session.sessionID, submission: carried)
            conversations.records[index].carried[item] = carried; try conversations.save()
        }
        try await execution.deleteCarriedSource(carried)
        conversations.records[index].carried.removeAll { $0.id == submissionID }; try conversations.save()
        // Explicit Resume runs the transferred item only when it is at the front; existing queue order is retained.
        if execution.tasks[session.sessionID]?.workflow.queue.first?["id"].string == carried.destinationSubmission { try await execution.startQueued(id: session.sessionID) }
    }
}
