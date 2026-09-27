import Foundation
import Testing
@testable import DioramaApp
@testable import DioramaCore

@MainActor struct DevelopmentReloadTests {
    @Test func watchesInputsWithoutRebuildingOnGeneratedOutput() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        func write(_ path: String) throws {
            let file = root.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("fixture".utf8).write(to: file)
        }
        let inputs = ["Sources/App/Main.swift", "helpers/claude/index.mjs", "helpers/claude/package-lock.json", "Package.swift", "scripts/development-relaunch.sh"]
        for path in inputs { try write(path) }
        let before = DevelopmentReload.sourceDates(root: root)
        #expect(before.count == inputs.count)
        for path in [".build/output.swift", ".local/development/build.log", "dist/Diorama.app/output.swift", "helpers/claude/node_modules/dependency/package.json", "Tests/Example.swift"] { try write(path) }
        #expect(DevelopmentReload.sourceDates(root: root) == before)
        try write("Sources/App/New.swift")
        #expect(DevelopmentReload.sourceDates(root: root).count == before.count + 1)
        try FileManager.default.removeItem(at: root.appendingPathComponent("Sources/App/Main.swift"))
        #expect(DevelopmentReload.sourceDates(root: root)[root.appendingPathComponent("Sources/App/Main.swift").path] == nil)
    }

    @Test func reloadDefersActiveUncertainAndQueuedWork() {
        let execution = ExecutionController()
        #expect(DevelopmentReload.canReload(execution))
        var task = ExecutedTask(id: "test", title: "Test", folder: "/tmp", attached: true)
        for phase in [ExecutionPhase.working, .approval, .input, .submitting] {
            task.phase = phase
            execution.tasks = [task.id: task]
            #expect(!DevelopmentReload.canReload(execution))
        }
        task.phase = .ready
        task.workflow.queue = [.object(["text": .string("next")])]
        execution.tasks = [task.id: task]
        #expect(!DevelopmentReload.canReload(execution))
        task.workflow.queue = []
        task.workflow.goal = .object(["status": .string("active")])
        execution.tasks = [task.id: task]
        #expect(!DevelopmentReload.canReload(execution))
        task.workflow.goal = .null
        task.phase = .disconnected
        task.requiresReconciliation = true
        execution.tasks = [task.id: task]
        #expect(!DevelopmentReload.canReload(execution))
        task.requiresReconciliation = false
        task.attached = false
        execution.tasks = [task.id: task]
        #expect(DevelopmentReload.canReload(execution))
    }
}
