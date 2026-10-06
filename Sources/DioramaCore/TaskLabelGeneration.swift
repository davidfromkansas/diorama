import Foundation

/// A throwaway thread's reply, collected until its turn completes.
@MainActor final class LabelRun {
    private var text = ""
    private var continuation: CheckedContinuation<String?, Never>?
    private var finished: String??
    func receive(_ method: String, _ p: WireValue) {
        if method == "item/completed", p["item"]["type"].string == "agentMessage" { text = p["item"]["text"].string ?? text }
        if method == "turn/completed" { finish(text) }
    }
    func finish(_ value: String?) {
        guard finished == nil else { return }
        finished = .some(value)
        continuation?.resume(returning: value); continuation = nil
    }
    func wait() async -> String? {
        if let finished { return finished }
        return await withCheckedContinuation { continuation = $0 }
    }
}

extension ExecutionController {
    /// A four-word label for a task, written by a small model from the same provider as the agent,
    /// through the connection Diorama already has (the person's own subscription): an ephemeral
    /// Codex thread that is never saved, or a one-shot Claude Haiku call without a session.
    /// Nil when that provider isn't connected; callers fall back to `TaskLabel.fallback`.
    public func taskLabel(_ task: String, latest: String? = nil, provider: Provider, timeout: TimeInterval = 30) async -> String? {
        switch provider {
        case .claude:
            guard models.contains(where: { $0.id.hasPrefix("claude/") }) else { return nil }
            return await TaskLabel.generate(task, latest: latest, timeout: timeout)
        case .codex:
            let codex = models.filter { !$0.id.hasPrefix("claude/") }
            guard connected, !codex.isEmpty else { return nil }
            // The smallest model on offer does: a label is a few words.
            let model = codex.first { $0.id.contains("mini") } ?? codex.first { $0.isDefault } ?? codex[0]
            var start: [String: WireValue] = ["cwd": .string(FileManager.default.temporaryDirectory.path), "ephemeral": .bool(true),
                                              "sandbox": .string("read-only"), "approvalPolicy": .string("never"),
                                              "developerInstructions": .string(TaskLabel.instructions), "model": .string(model.id)]
            start["serviceName"] = .string("diorama-task-labels")
            guard let reply = try? await transport.request("thread/start", .object(start)), let thread = reply["thread"]["id"].string else { return nil }
            let run = LabelRun()
            labelRuns[thread] = run
            defer { labelRuns[thread] = nil }
            var turn: [String: WireValue] = ["threadId": .string(thread), "input": .array([.object(["type": .string("text"), "text": .string(TaskLabel.prompt(task, latest: latest))])])]
            if let effort = ["minimal", "low"].first(where: model.efforts.contains) { turn["effort"] = .string(effort) }
            guard (try? await transport.request("turn/start", .object(turn))) != nil else { return nil }
            let timer = Task { try? await Task.sleep(for: .seconds(timeout)); run.finish(nil) }
            let text = await run.wait()
            timer.cancel()
            return text.flatMap(TaskLabel.clean)
        }
    }
}
