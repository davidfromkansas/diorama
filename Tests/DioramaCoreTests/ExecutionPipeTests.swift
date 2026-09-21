import Foundation
import Testing
@testable import DioramaCore

struct ExecutionPipeTests {
    @Test func largeResponseAndReadOnlyTimeoutAreHandled() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let server = root.appendingPathComponent("server.py")
        let script = """
        #!/usr/bin/env python3
        import sys,json
        for line in sys.stdin:
            r=json.loads(line)
            if 'id' not in r: continue
            if r['method']=='thread/read': continue
            result={'payload':'x'*(4*1024*1024)} if r['method']=='model/list' else {}
            print(json.dumps({'id':r['id'],'result':result}),flush=True)
        """
        try script.write(to: server, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: server.path)
        let transport = CodexExecutionTransport(executable: server, timeout: .seconds(5))
        try await transport.connect()
        do {
            let reply = try await transport.request("model/list", .object([:]))
            #expect(reply["payload"].string?.count == 4 * 1024 * 1024)
            do { _ = try await transport.request("thread/read", .object([:])); Issue.record("Expected read timeout") }
            catch { #expect(error.localizedDescription.contains("did not send a message")); #expect(!error.localizedDescription.contains("outcome may be unknown")) }
        } catch { await transport.shutdown(); throw error }
        await transport.shutdown()
    }
}
