import Foundation
import Darwin
import DioramaCore

// Git invokes this helper only for a single verified HTTPS GitHub destination.
if CommandLine.arguments.contains("--github-credential") {
    if CommandLine.arguments.last == "get" {
        let data = (try? FileHandle.standardInput.read(upToCount: 8192)) ?? Data()
        let fields = String(decoding: data, as: UTF8.self).split(separator: "\n").reduce(into: [String: String]()) { result, line in
            let pair = line.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            if pair.count == 2 { result[String(pair[0])] = String(pair[1]) }
        }
        if fields["protocol"] == "https", fields["host"] == "github.com",
           let expected = ProcessInfo.processInfo.environment["DIORAMA_GITHUB_REPOSITORY"],
           fields["path"] == expected || fields["path"] == expected + ".git",
           let token = try? GitHubCredentials.load() {
            FileHandle.standardOutput.write(Data("username=x-access-token\npassword=\(token)\n\n".utf8))
        }
    }
    exit(0)
}

// Fail open, bounded input, no provider decisions, and no dependency on a running GUI.
defer { FileHandle.standardOutput.write(Data("{}\n".utf8)) }
let args = CommandLine.arguments
if args.count == 4, args[1] == "--diorama-reporter-v1", ["codex", "claude"].contains(args[2]) {
    var bytes = Data()
    var buffer = [UInt8](repeating: 0, count: 8192)
    let deadline = Date().addingTimeInterval(0.5)
    while Date() < deadline, bytes.count <= 2 * 1024 * 1024 {
        var descriptor = pollfd(fd: STDIN_FILENO, events: Int16(POLLIN), revents: 0)
        guard poll(&descriptor, 1, 10) > 0 else { continue }
        let count = read(STDIN_FILENO, &buffer, buffer.count)
        if count <= 0 { break }
        bytes.append(contentsOf: buffer.prefix(count))
    }
    if bytes.count <= 2 * 1024 * 1024,
       let record = try? JSONSerialization.jsonObject(with: bytes) as? [String: Any],
       let event = ActivityParser.hook(record, provider: args[2] == "codex" ? .codex : .claude) {
        try? HookStore.write(event, directory: URL(fileURLWithPath: args[3]))
        if args[2] == "claude", let reference = ClaudeSessionReference.hook(record) {
            let defaults = ClaudeDesktopPaths.defaults
            let paths = ClaudeDesktopPaths(metadata: defaults.metadata, transcripts: defaults.transcripts,
                registry: URL(fileURLWithPath: args[3]).deletingLastPathComponent().appendingPathComponent("ClaudeSessions"))
            try? reference.write(paths: paths)
        }
    }
}
