import Foundation
import DioramaCore

/// Nonobservable presentation registry: assigning a name during projection never invalidates SwiftUI.
final class AgentDisplayNameModel {
    private let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Diorama/AgentNames.json")
    private var value: AgentDisplayNames
    private let writer = AgentDisplayNameWriter()
    private var revision = 0
    private(set) var error: String?
    init() {
        value = (try? JSONDecoder().decode(AgentDisplayNames.self, from: Data(contentsOf: url))) ?? .init()
    }
    func resolve(project: String, identities: [String], reported: String) -> String {
        // Existing aliases dominate refreshes. Do not copy/compare the whole registry
        // or scan every project's names when these few identities already agree.
        let keys = identities.map { project + "\u{1E}" + $0 }
        let existing = keys.compactMap { value.names?[$0] }.first
        let selected = AgentDisplayNames.meaningful(reported) ? reported : existing
        if let selected, !keys.isEmpty, keys.allSatisfy({ value.names?[$0] == selected }) { return selected }
        let previous = value.names
        let name = value.resolve(project: project, identities: identities, reported: reported)
        if value.names != previous {
            revision += 1
            let snapshot = value, number = revision, destination = url, writer = writer
            Task { do { try await writer.save(snapshot, revision: number, to: destination) } catch { self.error = "Agent names could not be saved: " + error.localizedDescription } }
        }
        return name
    }
}

extension LibraryModel {
    func agentDisplayName(_ session: Session, agent: String = "main", reported: String = "Main agent", project explicitProject: String? = nil) -> String {
        let project = explicitProject ?? projects.projects.first { projects.sessions($0, library: self).contains { $0.id == session.id } }?.id ?? session.project
        let segments = conversations.record(session.id)?.segments ?? [ConversationSegment(nativeID: session.sessionID, provider: session.provider, model: "")]
        let identities = agent == "main" ? segments.map { $0.provider + ":" + $0.nativeID + ":main" } : [agent]
        return agentNames.resolve(project: project, identities: identities, reported: reported)
    }
}
