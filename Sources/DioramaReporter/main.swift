import Foundation
import Darwin
import DioramaCore

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
    }
}
