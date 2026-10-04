import Foundation
import Darwin

public struct LocalServerProcess: Equatable, Sendable {
    public var pid: Int32
    public var parent: Int32
    public var started: UInt64
    public var name: String
    public var folder: String
    public var endpoints: [String]
    public var id: String { "\(pid):\(started)" }
    public init(pid: Int32, parent: Int32 = 0, started: UInt64, name: String, folder: String, endpoints: [String] = []) {
        self.pid = pid; self.parent = parent; self.started = started; self.name = name; self.folder = folder; self.endpoints = endpoints
    }
}
public struct LocalServerRoot: Equatable, Sendable {
    public var project: String
    public var folder: String
    public init(project: String, folder: String) { self.project = project; self.folder = folder }
}
public struct LocalServerLink: Equatable, Sendable {
    public var project: String
    public var conversation: String
    public var title: String
    public var url: URL
    public init(project: String, conversation: String, title: String, url: URL) {
        self.project = project; self.conversation = conversation; self.title = title; self.url = url
    }
    public var port: Int { url.port ?? (url.scheme == "https" ? 443 : 80) }
    /// No credentials, query strings or fragments in labels or diagnostics.
    public var label: String { "\(url.scheme ?? "http")://\(url.host ?? "localhost"):\(port)\(url.path)" }
}
public struct ProjectLocalServer: Equatable, Identifiable, Sendable {
    public var id: String
    public var process: LocalServerProcess
    public var project: String
    public var confirmed: Bool
    public var links: [LocalServerLink]
    public init(id: String, process: LocalServerProcess, project: String, confirmed: Bool, links: [LocalServerLink]) {
        self.id = id; self.process = process; self.project = project; self.confirmed = confirmed; self.links = links
    }
}
public struct LocalServerInventory: Sendable {
    public var processes: [LocalServerProcess]
    public var observed: Date
    public var duration: TimeInterval
}
public enum ProjectServerDiscovery {
    public static func port(_ endpoint: String) -> Int? { endpoint.split(separator: ":").last.flatMap { Int($0) } }
    public static func links(in text: String, project: String, conversation: String, title: String) -> [LocalServerLink] {
        let pattern = #"https?://(?:localhost|127\.0\.0\.1|\[::1\])(?::[0-9]+)?(?:[/?#][^\s<>\"']*)?"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return [] }
        let bounded = String(text.prefix(262_144))
        return regex.matches(in: bounded, range: NSRange(bounded.startIndex..., in: bounded)).compactMap { match in
            guard let range = Range(match.range, in: bounded), let url = URL(string: String(bounded[range]).trimmingCharacters(in: CharacterSet(charactersIn: ").,;`"))) else { return nil }
            return LocalServerLink(project: project, conversation: conversation, title: title, url: url)
        }
    }
    public static func match(_ processes: [LocalServerProcess], roots: [LocalServerRoot], links: [LocalServerLink]) -> [ProjectLocalServer] {
        let byPID = Dictionary(processes.map { ($0.pid, $0) }, uniquingKeysWith: { a, _ in a })
        func owner(_ process: LocalServerProcess) -> String? {
            var current = process, visited = Set<Int32>()
            for _ in 0..<16 {
                guard visited.insert(current.pid).inserted else { return nil }
                let matches = roots.filter { !current.folder.isEmpty && (current.folder == $0.folder || current.folder.hasPrefix($0.folder + "/")) }
                if let length = matches.map({ $0.folder.count }).max() {
                    let owners = Set(matches.filter { $0.folder.count == length }.map(\.project))
                    return owners.count == 1 ? owners.first : nil
                }
                guard current.parent > 1, let parent = byPID[current.parent], parent.started <= current.started else { return nil }
                current = parent
            }
            return nil
        }
        var rows: [ProjectLocalServer] = []
        for process in processes where !process.endpoints.isEmpty {
            let ports = Set(process.endpoints.compactMap(port))
            let evidence = links.filter { link in
                ports.contains(link.port) && process.endpoints.contains { endpoint in
                    guard port(endpoint) == link.port else { return false }
                    let host = endpoint.prefix(upTo: endpoint.lastIndex(of: ":")!)
                    return host == "*" || host == "0.0.0.0" || host == "[::]" || host == "127.0.0.1" || host == "[::1]"
                }
            }
            if let project = owner(process) {
                rows.append(.init(id: process.id, process: process, project: project, confirmed: true, links: evidence.filter { $0.project == project }))
            } else {
                for project in Set(evidence.map(\.project)).sorted() {
                    rows.append(.init(id: process.id, process: process, project: project, confirmed: false, links: evidence.filter { $0.project == project }))
                }
            }
        }
        // Related workers listening on exactly the same endpoints represent one service.
        return rows.filter { row in
            !rows.contains { parent in parent.project == row.project && parent.confirmed == row.confirmed && parent.process.pid == row.process.parent && Set(parent.process.endpoints) == Set(row.process.endpoints) }
        }
    }
    public static func parseListeners(_ text: String) -> [Int32: (String, [String])] {
        var result: [Int32: (String, [String])] = [:], pid: Int32?
        for line in text.split(separator: "\n") {
            guard let kind = line.first else { continue }; let value = String(line.dropFirst())
            if kind == "p" { pid = Int32(value); if let pid { result[pid] = ("Process", []) } }
            else if let pid, kind == "c" { result[pid]?.0 = value }
            else if let pid, kind == "n", port(value) != nil, result[pid]?.1.contains(value) == false { result[pid]?.1.append(value) }
        }
        return result
    }
    private static func process(_ pid: Int32) -> LocalServerProcess? {
        var info = proc_bsdinfo()
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, Int32(MemoryLayout.size(ofValue: info))) > 0 else { return nil }
        var paths = proc_vnodepathinfo()
        let found = proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &paths, Int32(MemoryLayout.size(ofValue: paths))) > 0
        let folder = found ? withUnsafePointer(to: &paths.pvi_cdir.vip_path) { ptr in
            ptr.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) { String(cString: $0) }
        } : ""
        return .init(pid: pid, parent: Int32(info.pbi_ppid), started: info.pbi_start_tvsec * 1_000_000 + info.pbi_start_tvusec,
                     name: "Process", folder: folder.isEmpty ? "" : URL(fileURLWithPath: folder).resolvingSymlinksInPath().standardizedFileURL.path)
    }
    @concurrent public static func scan() async throws -> LocalServerInventory {
        let start = Date()
        // lsof exit 1 with no output means an empty inventory; all other failures remain failures.
        let data: Data
        do { data = try await ProjectCommand.data("/usr/sbin/lsof", ["-nP", "-iTCP", "-sTCP:LISTEN", "-Fpcn"], timeout: 3) }
        catch { if error.localizedDescription == "Command failed (1)." { return .init(processes: [], observed: Date(), duration: Date().timeIntervalSince(start)) }; throw error }
        var processes: [Int32: LocalServerProcess] = [:]
        for (pid, value) in parseListeners(String(decoding: data, as: UTF8.self)) {
            try Task.checkCancellation()
            guard var current = process(pid) else { continue }
            current.name = value.0; current.endpoints = value.1.sorted(); processes[pid] = current
            for _ in 0..<16 {
                guard current.parent > 1, processes[current.parent] == nil, let parent = process(current.parent) else { break }
                processes[parent.pid] = parent; current = parent
            }
        }
        return .init(processes: Array(processes.values), observed: Date(), duration: Date().timeIntervalSince(start))
    }
}
