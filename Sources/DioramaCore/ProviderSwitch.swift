import Foundation

extension ExecutionController {
    /// Pause before creating another native session in the same working directory.
    public func prepareProviderSwitch(session: Session, model: String, handoff: String) async throws -> String {
        try await resumeImported(session)
        try requireIdle(session.sessionID)
        providerSwitches.insert(session.sessionID)
        defer { providerSwitches.remove(session.sessionID) }
        guard !workflowBusy.contains(session.sessionID), tasks[session.sessionID]?.requiresReconciliation != true,
              tasks[session.sessionID]?.workflow.queueUncertain != true else { throw AppServerFailure("Resolve pending delivery before changing providers.") }
        queueAutoStart.remove(session.sessionID)
        await loadWorkflow(id: session.sessionID)
        guard featureErrors["goals"] == nil, featureErrors["queue:" + session.sessionID] == nil,
              tasks[session.sessionID]?.workflow.queueUncertain != true else { throw AppServerFailure("Could not verify pending work. Refresh before switching providers.") }
        if tasks[session.sessionID]?.workflow.goal["status"].string == "active" {
            try await setGoal(id: session.sessionID, status: "paused")
        }
        try requireIdle(session.sessionID, allowProviderSwitch: true)
        let goal = tasks[session.sessionID]?.workflow.goal ?? .null
        let target = try await prepare(folder: session.project, title: session.title, model: model, projectContext: handoff)
        guard tasks[target]?.folder == session.project else { throw AppServerFailure("The provider did not preserve the worktree. No message was sent.") }
        if let objective = goal["objective"].string, ["active", "paused"].contains(goal["status"].string ?? "") {
            let remainingBudget = goal["tokenBudget"].number.map { max(1, Int($0 - (goal["tokensUsed"].number ?? 0))) }
            try await setGoal(id: target, objective: objective, status: "paused", tokenBudget: remainingBudget)
        }
        return target
    }
    public func retireProviderSession(_ id: String) {
        retiredProviderSessions.insert(id); queueAutoStart.remove(id)
    }
    /// Copies input verbatim into a paused native queue. The stable client ID permits safe reconciliation.
    public func importCarriedSubmission(id: String, submission: CarriedSubmission) async throws -> String {
        try requireIdle(id)
        guard !submission.row["input"].array.isEmpty else { throw AppServerFailure("Queued input is unavailable") }
        await refreshQueue(id: id)
        guard featureErrors["queue:" + id] == nil else { throw AppServerFailure("Destination queue unavailable") }
        if let existing = tasks[id]?.workflow.queue.first(where: { $0["clientUserMessageId"].string == submission.id })?["id"].string { return existing }
        let reply = try await transport.request("thread/queue/add", .object(["threadId": .string(id), "clientUserMessageId": .string(submission.id), "input": submission.row["input"]]))
        guard reply["queuedSubmission"]["clientUserMessageId"].string == submission.id,
              let queued = reply["queuedSubmission"]["id"].string else { throw AppServerFailure("Queue transfer outcome unconfirmed. Inspect queued messages before retrying.") }
        await refreshQueue(id: id)
        return queued
    }
    public func deleteCarriedSource(_ submission: CarriedSubmission) async throws {
        guard let queued = submission.row["id"].string else { throw AppServerFailure("Original queued message identity unavailable") }
        // Read/delete do not acquire a writer or start a turn in the historical session.
        var identity: [String: WireValue] = ["threadId": .string(submission.sourceID), "limit": .number(100)]
        if let provider = submission.sourceProvider { identity["dioramaProvider"] = .string(provider) }
        if let folder = submission.sourceFolder { identity["cwd"] = .string(folder) }
        let list = try await transport.request("thread/queue/list", .object(identity))
        guard case .array(let rows) = list["data"] else { throw AppServerFailure("Original queue unavailable") }
        if !rows.contains(where: { $0["id"].string == queued }), list["nextCursor"].string == nil { return }
        identity.removeValue(forKey: "limit"); identity["queuedSubmissionId"] = .string(queued)
        let reply = try await transport.request("thread/queue/delete", .object(identity))
        guard reply["deleted"].bool else { throw AppServerFailure("Original queue removal not confirmed") }
    }
}
