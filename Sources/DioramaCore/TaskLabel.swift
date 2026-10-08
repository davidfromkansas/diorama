import Foundation

/// A label of at most four words that sums up a task ("Add Stats Dashboard"), for a chef's name
/// tag. A small Claude model writes it once per task, through the person's own Claude Code login
/// with no tools, MCP servers or settings loaded; a keyword label stands in until then (or
/// without Claude).
public enum TaskLabel {
    public static let maxWords = 4
    static let instructions = "You label coding tasks for a dashboard. You never perform the task and never ask questions. Reply with only a label of at most 4 words in Title Case that names what the agent is working on now: the main thing being built, fixed or changed. When there is a latest request, label that work in the context of the original task. No punctuation, no quotes, no markdown."

    static func prompt(_ task: String, latest: String? = nil) -> String {
        let original = "<task>" + String(task.prefix(2000)) + "</task>"
        guard let latest, !latest.isEmpty else { return "Label this task: " + original }
        return "Original task: " + original + "\nLatest request: <latest>" + String(latest.prefix(2000)) + "</latest>\nLabel what the agent is working on now."
    }
    /// A follow-up that carries no new work ("yes", "ok, go ahead", "continue"): the label stays.
    public static func isAcknowledgement(_ message: String) -> Bool {
        let words = message.lowercased().split(whereSeparator: { !$0.isLetter && $0 != "'" })
        let filler: Set<String> = ["yes", "yeah", "yep", "yup", "ok", "okay", "k", "sure", "continue", "go", "ahead", "proceed", "please", "thanks",
                                   "thank", "you", "do", "it", "that", "sounds", "good", "great", "perfect", "lgtm", "looks", "nice", "cool", "keep",
                                   "going", "carry", "on", "approved", "approve", "fine", "alright", "right", "y", "again", "try", "retry", "the", "and", "now"]
        return words.count <= 6 && words.allSatisfy { filler.contains(String($0)) }
    }
    /// The model's reply as a label, or nil when it isn't one (too long, empty, chatty).
    public static func clean(_ output: String) -> String? {
        let line = output.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty && !$0.hasPrefix("Warning:") } ?? ""
        let allowed = CharacterSet.alphanumerics.union(.whitespaces).union(CharacterSet(charactersIn: ".+#-'&/"))
        let kept = String(line.unicodeScalars.filter(allowed.contains)).trimmingCharacters(in: CharacterSet(charactersIn: " .-"))
        let words = kept.split(whereSeparator: \.isWhitespace)
        guard (1...maxWords).contains(words.count), kept.count <= 40 else { return nil }
        return words.joined(separator: " ")
    }

    /// A stand-in from the task's own words: its verb and the first content words after it,
    /// without filler, in Title Case. Never a sentence cut mid-way.
    public static func fallback(_ task: String) -> String {
        let stop: Set<String> = ["i", "we", "you", "can", "could", "would", "please", "want", "like", "to", "a", "an", "the", "for", "me", "this", "that",
                                 "it", "and", "of", "my", "our", "in", "on", "with", "where", "which", "so", "be", "is", "are", "some", "into", "let's", "lets",
                                 "go", "ahead", "help", "just", "also", "then", "there", "here", "shows", "show", "using", "use", "by", "at", "from", "as"]
        let words = task.split(whereSeparator: { $0.isWhitespace || ",;:!?()\"".contains($0) })
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: ".'")) }
            .filter { !$0.isEmpty && !stop.contains($0.lowercased()) }
        return words.prefix(maxWords).map { $0.first!.isLowercase ? $0.prefix(1).uppercased() + $0.dropFirst() : $0 }.joined(separator: " ")
    }

    /// Asks Claude Haiku for the label (through the person's Claude Code login; no session is saved); nil when Claude Code isn't installed, fails or answers off-script.
    @concurrent public static func generate(_ task: String, latest: String? = nil, timeout: TimeInterval = 45) async -> String? {
        guard let binary = ClaudeExecutionTransport.binary() else { return nil }
        let process = Process(), output = Pipe()
        process.executableURL = binary
        let folder = FileManager.default.temporaryDirectory.path
        process.arguments = ["-p", "--model", "haiku", "--tools", "", "--strict-mcp-config", "--mcp-config", #"{"mcpServers":{}}"#,
                             "--setting-sources", "", "--disable-slash-commands", "--no-session-persistence", "--system-prompt", instructions,
                             prompt(task, latest: latest)]
        process.currentDirectoryURL = URL(fileURLWithPath: folder)
        process.environment = ClaudeExecutionTransport.childEnvironment(ProcessInfo.processInfo.environment, folder: folder, executable: binary)
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = output; process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let watchdog = Task { try await Task.sleep(for: .seconds(timeout)); if process.isRunning { process.terminate() } }
        let data = await Task.detached { output.fileHandleForReading.readDataToEndOfFile() }.value
        process.waitUntilExit(); watchdog.cancel()
        guard process.terminationStatus == 0 else { return nil }
        return clean(String(decoding: data, as: UTF8.self))
    }
}
