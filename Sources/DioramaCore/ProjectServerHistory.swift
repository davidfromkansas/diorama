import Foundation

/// Bounded, fingerprinted history reads; no provider connection or execution.
public actor ProjectServerHistory {
    private var cache: [String: (Date, Int, [LocalServerLink])] = [:]
    public init() {}
    public func read(_ session: Session, project: String) async -> [LocalServerLink] {
        let key = project + ":" + session.id
        if let known = cache[key], known.0 == session.modified, known.1 == session.bytes { return known.2 }
        let links = await Self.readFile(session, project: project)
        if cache.count >= 256 { cache.removeAll() }
        cache[key] = (session.modified, session.bytes, links)
        return links
    }
    @concurrent private static func readFile(_ session: Session, project: String) async -> [LocalServerLink] {
        guard let url = session.url, let handle = try? FileHandle(forReadingFrom: url) else { return [] }
        defer { try? handle.close() }
        do {
            let size = try handle.seekToEnd(), start = size > 512 * 1024 ? size - 512 * 1024 : 0
            try handle.seek(toOffset: start)
            var data = try handle.read(upToCount: 512 * 1024) ?? Data()
            if start > 0, let line = data.firstIndex(of: 10) { data = Data(data[data.index(after: line)...]) }
            let transcript = SessionLibrary.parseTranscript(data: data, provider: session.provider, limit: 200, start: start, scope: session.id)
            return transcript.entries.filter { $0.kind != "You" }.flatMap { entry in
                ProjectServerDiscovery.links(in: entry.text + "\n" + (entry.claude?.detail ?? ""), project: project, conversation: session.id, title: session.title)
            }
        } catch { return [] }
    }
}
