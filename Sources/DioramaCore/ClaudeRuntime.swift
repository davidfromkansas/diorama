import Foundation

public enum ClaudeBackend: String, Sendable { case automatic, cli, sdk }

public struct ClaudeSDKRuntime: Sendable {
    public let node: URL
    public let directory: URL
    public static func discover() -> Self? {
        let environment = ProcessInfo.processInfo.environment
        if let resources = Bundle.main.resourceURL {
            let directory = resources.appendingPathComponent("ClaudeHelper")
            let node = directory.appendingPathComponent("node")
            if FileManager.default.isExecutableFile(atPath: node.path), FileManager.default.fileExists(atPath: directory.appendingPathComponent("index.mjs").path) {
                return Self(node: node, directory: directory)
            }
        }
        // Explicit development override; production never searches arbitrary working-directory scripts.
        if let path = environment["DIORAMA_CLAUDE_HELPER"], let node = environment["DIORAMA_NODE"],
           FileManager.default.isExecutableFile(atPath: node), FileManager.default.fileExists(atPath: path + "/index.mjs") {
            return Self(node: URL(fileURLWithPath: node), directory: URL(fileURLWithPath: path))
        }
        return nil
    }
}

extension ExecutionController {
    /// Inspection never attaches, resumes or changes the selected task.
    public func inspectChild(provider: Provider, parentID: String, childID: String, folder: String) async throws -> Transcript {
        if provider == .codex {
            let response = try await transport.request("thread/read", .object(["threadId": .string(childID), "includeTurns": .bool(true)]))
            let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(response["thread"])) as? [String: Any] ?? [:]
            return try AppServerHistory.transcript(object, limit: 300)
        }
        guard UUID(uuidString: parentID) != nil, !childID.isEmpty,
              childID.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }) else { throw AppServerFailure("Invalid child identity") }
        if let runtime = ClaudeSDKRuntime.discover() {
            let data = try await ProjectCommand.data(runtime.node.path, [runtime.directory.appendingPathComponent("history.mjs").path, parentID, childID, folder])
            let messages = try JSONDecoder().decode([WireValue].self, from: data)
            var lines = Data()
            for message in messages {
                lines.append(try JSONEncoder().encode(message))
                lines.append(0x0a)
            }
            var transcript = await Task.detached {
                ClaudeNormalizer.parse(lines, scope: parentID + ":" + childID)
            }.value
            transcript.source = "Claude SDK · read-only saved history"
            return transcript
        }
        let encoded = folder.replacingOccurrences(of: "[^a-zA-Z0-9]", with: "-", options: .regularExpression)
        let base = ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"].map { URL(fileURLWithPath: $0) } ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude")
        let file = base.appendingPathComponent("projects").appendingPathComponent(encoded).appendingPathComponent(parentID).appendingPathComponent("subagents/agent-" + childID + ".jsonl")
        return await Task.detached { SessionLibrary.readTranscript(url: file, provider: .claude) }.value
    }
}
