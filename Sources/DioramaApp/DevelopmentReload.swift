import AppKit
import Observation
import DioramaCore

/// Opt-in local development only. Release bundles contain no DevelopmentRoot resource.
@Observable @MainActor final class DevelopmentReload {
    private(set) var enabled: Bool
    private(set) var status = "Auto-reload: watching sources"
    private(set) var isRequestingQuit = false
    let root: URL
    private weak var library: LibraryModel?
    @ObservationIgnored private var watcher: DirectoryWatcher?
    @ObservationIgnored private var debounce: Task<Void, Never>?
    @ObservationIgnored private var retry: Task<Void, Never>?
    @ObservationIgnored private var building = false
    @ObservationIgnored private var ready = false
    @ObservationIgnored private var observed: [String: Date] = [:]
    private var directory: URL { root.appendingPathComponent(".local/development") }
    private var stagedApp: URL { directory.appendingPathComponent("Diorama.app") }
    private var installedApp: URL { root.appendingPathComponent("dist/Diorama.app") }
    private var logURL: URL { directory.appendingPathComponent("reload.log") }

    static func configured(library: LibraryModel) -> DevelopmentReload? {
        guard let resource = Bundle.main.url(forResource: "DevelopmentRoot", withExtension: "txt"),
              let path = try? String(contentsOf: resource, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines),
              !path.isEmpty else { return nil }
        let root = URL(fileURLWithPath: path).standardizedFileURL
        guard FileManager.default.fileExists(atPath: root.appendingPathComponent("Package.swift").path),
              FileManager.default.fileExists(atPath: root.appendingPathComponent("scripts/development-relaunch.sh").path),
              Bundle.main.bundleURL.standardizedFileURL == root.appendingPathComponent("dist/Diorama.app") else { return nil }
        return DevelopmentReload(root: root, library: library)
    }

    private init(root: URL, library: LibraryModel) {
        self.root = root
        self.library = library
        enabled = UserDefaults.standard.object(forKey: "developmentAutoReload") as? Bool ?? true
        observed = Self.sourceDates(root: root)
        watcher = DirectoryWatcher(paths: [root.path]) { [weak self] in self?.sourcesChanged() }
        if !enabled { status = "Auto-reload: paused" }
        // Catch source edits made while the app was closed.
        let stamp = Bundle.main.url(forResource: "DevelopmentBuildDate", withExtension: "txt")
        let builtAt = stamp.flatMap { try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate } ?? .distantPast
        if enabled && observed.values.contains(where: { $0 > builtAt }) { scheduleBuild() }
    }

    static func sourceDates(root: URL) -> [String: Date] {
        var result: [String: Date] = [:]
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .contentModificationDateKey]
        for path in ["Sources", "helpers/claude"] {
            let directory = root.appendingPathComponent(path)
            guard let files = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: Array(keys),
                options: [.skipsHiddenFiles]) else { continue }
            for case let file as URL in files {
                if file.lastPathComponent == "node_modules" { files.skipDescendants(); continue }
                guard let values = try? file.resourceValues(forKeys: keys), values.isDirectory != true,
                      ["swift", "mjs", "json"].contains(file.pathExtension) else { continue }
                result[file.path] = values.contentModificationDate ?? .distantPast
            }
        }
        for path in ["Package.swift", "Package.resolved", "build-macos.sh",
                     "scripts/package-claude-helper.sh", "scripts/development-relaunch.sh"] {
            let file = root.appendingPathComponent(path)
            if let date = try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate {
                result[file.path] = date
            }
        }
        return result
    }

    func setEnabled(_ value: Bool) {
        enabled = value
        UserDefaults.standard.set(value, forKey: "developmentAutoReload")
        if value { scheduleBuild() }
        else { debounce?.cancel(); retry?.cancel(); status = "Auto-reload: paused" }
    }

    private func sourcesChanged() {
        let dates = Self.sourceDates(root: root)
        guard dates != observed else { return }
        observed = dates
        guard enabled else { return }
        scheduleBuild()
    }

    private func scheduleBuild() {
        ready = false
        retry?.cancel()
        debounce?.cancel()
        guard !building else { return } // Build completion checks for edits made during compilation.
        debounce = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(900)) } catch { return }
            await self?.build()
        }
    }

    private func build() async {
        guard enabled, !building else { return }
        building = true
        let inputs = Self.sourceDates(root: root)
        status = "Auto-reload: building…"
        log("Building updated sources")
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let buildLog = directory.appendingPathComponent("build.log")
            FileManager.default.createFile(atPath: buildLog.path, contents: nil)
            let output = try FileHandle(forWritingTo: buildLog)
            defer { try? output.close() }
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = [root.appendingPathComponent("build-macos.sh").path]
            process.currentDirectoryURL = root
            var environment = ProcessInfo.processInfo.environment
            environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
            environment["DIORAMA_BUILD_CONFIGURATION"] = "release"
            environment["DIORAMA_APP_PATH"] = stagedApp.path
            environment["DIORAMA_DEVELOPMENT_ROOT"] = root.path
            environment["DIORAMA_REUSE_HELPER_FROM"] = installedApp.appendingPathComponent("Contents/Resources/ClaudeHelper").path
            process.environment = environment
            process.standardOutput = output; process.standardError = output
            let code: Int32 = try await withCheckedThrowingContinuation { continuation in
                process.terminationHandler = { child in continuation.resume(returning: child.terminationStatus) }
                do { try process.run() } catch { continuation.resume(throwing: error) }
            }
            building = false
            let latest = Self.sourceDates(root: root)
            if latest != inputs {
                observed = latest
                if enabled { scheduleBuild() }
                return
            }
            guard code == 0 else {
                status = "Auto-reload: build failed — see build.log"
                log("Build failed; keeping current app. See \(buildLog.path)")
                return
            }
            ready = true
            guard enabled else { status = "Auto-reload: paused"; return }
            status = "Auto-reload: update ready"
            log("Build succeeded")
            waitForIdle()
        } catch {
            building = false
            status = "Auto-reload: build failed — see reload.log"
            log(error.localizedDescription)
        }
    }

    static func canReload(_ execution: ExecutionController) -> Bool {
        !execution.creating && !execution.connecting && !execution.stopping && execution.resuming.isEmpty
            && execution.workflowBusy.isEmpty && !execution.hasActiveWork && !execution.hasUncertainWork
            && execution.requests.isEmpty
            && !execution.tasks.values.contains {
                $0.attached && ($0.steering || $0.workflow.goal["status"].string == "active" || !$0.workflow.queue.isEmpty)
            }
    }

    private func waitForIdle() {
        retry?.cancel()
        retry = Task { [weak self] in
            while let self, self.enabled, self.ready, !Task.isCancelled {
                if !self.isRequestingQuit, let library = self.library,
                   Self.canReload(library.execution), library.conversations.switching.isEmpty,
                   library.projects.busy.isEmpty {
                    // Finish asynchronous shutdown before entering AppKit's termination loop.
                    // Swift MainActor jobs cannot reliably run inside that nested loop.
                    if await self.prepareToRelaunch() {
                        self.isRequestingQuit = true
                        // Shutdown is complete and the delegate returns terminateNow. Quit before
                        // another SwiftUI layout pass can delay the install handoff.
                        NSApplication.shared.terminate(nil)
                        return
                    }
                } else if !self.isRequestingQuit {
                    self.status = "Auto-reload: waiting for Diorama tasks"
                }
                do { try await Task.sleep(for: .seconds(3)) } catch { return }
            }
        }
    }

    /// Complete idle shutdown before asking AppKit to terminate; never interrupt active work.
    func prepareToRelaunch() async -> Bool {
        guard enabled, ready, let library else { isRequestingQuit = false; return false }
        do {
            guard Self.canReload(library.execution), !(try await library.execution.requiresQuitConfirmation()),
                  Self.canReload(library.execution) else {
                status = "Auto-reload: waiting for Diorama tasks"
                isRequestingQuit = false
                return false
            }
            library.flushWindowPresentation()
            try await library.execution.stopAndShutdown()
            let helper = Process()
            helper.executableURL = URL(fileURLWithPath: "/bin/zsh")
            helper.arguments = [root.appendingPathComponent("scripts/development-relaunch.sh").path,
                                String(ProcessInfo.processInfo.processIdentifier), root.path]
            let output = try FileHandle(forWritingTo: logURL)
            try output.seekToEnd()
            helper.standardOutput = output; helper.standardError = output
            try helper.run()
            try? output.close()
            return true
        } catch {
            status = "Auto-reload: waiting — see reload.log"
            log(error.localizedDescription)
            isRequestingQuit = false
            return false
        }
    }

    private func log(_ message: String) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: logURL.path) { FileManager.default.createFile(atPath: logURL.path, contents: nil) }
        guard let output = try? FileHandle(forWritingTo: logURL) else { return }
        defer { try? output.close() }
        _ = try? output.seekToEnd()
        try? output.write(contentsOf: Data((Date().description + " " + message + "\n").utf8))
    }
}
