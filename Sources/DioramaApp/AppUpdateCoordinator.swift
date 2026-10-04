import AppKit
import Observation
import Sparkle
import DioramaCore

@Observable @MainActor final class AppUpdateCoordinator: NSObject {
    enum Phase: Equatable { case idle, checking, available, downloading, preparing, ready, restarting, failed, current }
    var phase: Phase = .idle
    var version = ""
    var progress: Double?
    var detail = ""
    var hidden = false
    var confirmingRestart = false
    var preview = false
    private(set) var approvedShutdown = false
    @ObservationIgnored private var updater: SPUUpdater?
    @ObservationIgnored private weak var library: LibraryModel?
    @ObservationIgnored private var choice: ((SPUUserUpdateChoice) -> Void)?
    @ObservationIgnored private var readyReply: ((SPUUserUpdateChoice) -> Void)?
    @ObservationIgnored private var cancelOperation: (() -> Void)?
    @ObservationIgnored private var received: UInt64 = 0
    @ObservationIgnored private var expected: UInt64 = 0
    @ObservationIgnored private var lastProgress = Date.distantPast
    @ObservationIgnored private var userInitiated = false
    @ObservationIgnored private var cancellingForQuit = false
    @ObservationIgnored private var activationObserver: NSObjectProtocol?
    @ObservationIgnored private var consentSnapshot: Set<String> = []
    @ObservationIgnored private var restartPending = false
    static let feed = URL(string: "https://github.com/davidfromkansas/diorama-releases/releases/latest/download/appcast.xml")!
    static let releases = URL(string: "https://github.com/davidfromkansas/diorama-releases/releases")!
    var visible: Bool { phase != .idle && !hidden }
    var isDevelopment: Bool { Bundle.main.url(forResource: "DevelopmentRoot", withExtension: "txt") != nil }

    func configure(library: LibraryModel) {
        guard self.library == nil else { return }
        self.library = library
        guard !isDevelopment, Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String != nil else { return }
        let driver = SPUUpdater(hostBundle: .main, applicationBundle: .main, userDriver: self, delegate: self)
        updater = driver
        do {
            try driver.start()
            driver.automaticallyChecksForUpdates = true
            driver.automaticallyDownloadsUpdates = false
            driver.updateCheckInterval = 6 * 60 * 60
            activationObserver = NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.checkIfDue() }
            }
            checkIfDue()
        } catch { updater = nil; detail = error.localizedDescription }
    }
    private func checkIfDue() {
        guard let updater, !updater.sessionInProgress,
              Date().timeIntervalSince(updater.lastUpdateCheckDate ?? .distantPast) >= 6 * 60 * 60 else { return }
        updater.checkForUpdatesInBackground()
    }
    func check() {
        hidden = false
        guard !preview else { return }
        guard let updater else {
            phase = .failed
            detail = isDevelopment ? "Automatic installation is disabled in development builds." : "Updates are not configured for this build. Download the latest release from GitHub."
            return
        }
        if updater.sessionInProgress { return }
        userInitiated = true
        updater.checkForUpdates()
    }
    func dismiss() { hidden = true }
    func releaseNotes() {
        let url = version.range(of: #"^\d+\.\d+\.\d+$"#, options: .regularExpression) != nil
            ? Self.releases.appendingPathComponent("tag/v" + version) : Self.releases
        NSWorkspace.shared.open(url)
    }
    func download() {
        guard phase == .available else { return }
        if preview { phase = .downloading; progress = 0.42; return }
        guard let callback = choice else { return }
        choice = nil; userInitiated = true; phase = .downloading; progress = nil
        callback(.install)
    }
    private func workSnapshot(_ execution: ExecutionController) -> Set<String> {
        Set(execution.tasks.values.filter { $0.attached && ($0.phase.active || $0.steering || $0.workflow.goal["status"].string == "active") }
            .map { $0.id + ":" + ($0.turnID ?? "") })
    }
    func requestRestart() {
        guard phase == .ready, !restartPending else { return }
        if preview { confirmingRestart = true; return }
        guard let library else { return }
        restartPending = true
        Task {
            defer { restartPending = false }
            do {
                if try await library.execution.requiresQuitConfirmation() {
                    consentSnapshot = workSnapshot(library.execution); confirmingRestart = true
                } else { await restart(consented: false) }
            } catch { detail = error.localizedDescription; phase = .ready }
        }
    }
    func confirmRestart() {
        confirmingRestart = false
        guard !preview, !restartPending else { return }
        restartPending = true
        Task {
            defer { restartPending = false }
            await restart(consented: true)
        }
    }
    private func restart(consented: Bool) async {
        guard let library, let callback = readyReply, phase == .ready else { return }
        do {
            let requiresConsent = try await library.execution.requiresQuitConfirmation()
            let latest = workSnapshot(library.execution)
            if (requiresConsent || library.execution.hasActiveWork || library.execution.hasUncertainWork)
                && (!consented || !latest.isSubset(of: consentSnapshot)) {
                consentSnapshot = latest; confirmingRestart = true; return
            }
            phase = .restarting; detail = ""
            library.flushWindowPresentation()
            // stopAndShutdown gates submissions synchronously before its first await.
            try await library.execution.stopAndShutdown()
            approvedShutdown = true
            readyReply = nil
            callback(.install)
        } catch { phase = .ready; detail = "Could not restart: " + error.localizedDescription }
    }
    /// Sparkle prepares an installer before Ready. Cancel it before an ordinary
    /// quit so that closing the app cannot implicitly consent to installation.
    func cancelForOrdinaryQuit() async throws {
        guard !approvedShutdown, !preview, let updater, updater.sessionInProgress else { return }
        try await cancelPendingUpdate(while: { updater.sessionInProgress })
    }
    func cancelPendingUpdate(while sessionInProgress: () -> Bool) async throws {
        cancellingForQuit = true
        defer { cancellingForQuit = false }
        if let reply = readyReply { readyReply = nil; reply(.skip) }
        else if let reply = choice { choice = nil; reply(.dismiss) }
        else { cancelOperation?() }
        let deadline = Date().addingTimeInterval(15)
        while sessionInProgress() {
            guard Date() < deadline else { throw AppServerFailure("The update is still being cancelled. Keep Diorama open and try quitting again.") }
            try await Task.sleep(for: .milliseconds(100))
        }
    }
    func showPreview(_ phase: Phase) {
        guard isDevelopment || ProcessInfo.processInfo.environment["DIORAMA_UPDATE_TEST"] == "1" else { return }
        preview = true; hidden = false; version = "0.9.0"; self.phase = phase
        progress = phase == .downloading ? 0.42 : nil
        detail = phase == .failed ? "The download was interrupted. Check your connection and try again." : ""
    }
}

extension AppUpdateCoordinator: SPUUserDriver {
    func show(_ request: SPUUpdatePermissionRequest, reply: @escaping (SUUpdatePermissionResponse) -> Void) {
        reply(SUUpdatePermissionResponse(automaticUpdateChecks: true, sendSystemProfile: false))
    }
    func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) {
        cancelOperation = cancellation; userInitiated = true; phase = .checking; hidden = false; detail = ""
    }
    func showUpdateFound(with appcastItem: SUAppcastItem, state: SPUUserUpdateState, reply: @escaping (SPUUserUpdateChoice) -> Void) {
        detail = ""; progress = nil
        version = appcastItem.displayVersionString
        guard !appcastItem.isInformationOnlyUpdate else {
            detail = "This release requires a manual download. Open Release notes for instructions."
            phase = .failed; reply(.dismiss); return
        }
        if state.stage == .installing { readyReply = reply; phase = .ready }
        else { choice = reply; phase = .available }
    }
    func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {}
    func showUpdateReleaseNotesFailedToDownloadWithError(_ error: Error) {}
    func showUpdateNotFoundWithError(_ error: Error, acknowledgement: @escaping () -> Void) {
        if userInitiated { phase = .current; detail = "You’re using the latest compatible version." }
        acknowledgement()
    }
    func showUpdaterError(_ error: Error, acknowledgement: @escaping () -> Void) {
        if userInitiated && !cancellingForQuit { phase = .failed; detail = error.localizedDescription }
        acknowledgement()
    }
    func showDownloadInitiated(cancellation: @escaping () -> Void) {
        cancelOperation = cancellation; received = 0; expected = 0; lastProgress = .distantPast; progress = nil; detail = ""; phase = .downloading
    }
    func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) { expected = expectedContentLength }
    func showDownloadDidReceiveData(ofLength length: UInt64) {
        received = received.addingReportingOverflow(length).overflow ? UInt64.max : received + length
        guard Date().timeIntervalSince(lastProgress) >= 0.1 || (expected > 0 && received >= expected) else { return }
        lastProgress = Date(); progress = expected > 0 ? min(1, Double(received) / Double(expected)) : nil
    }
    func showDownloadDidStartExtractingUpdate() { cancelOperation = nil; progress = nil; phase = .preparing }
    func showExtractionReceivedProgress(_ progress: Double) {}
    func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) {
        if cancellingForQuit { reply(.skip); return }
        readyReply = reply; phase = .ready
    }
    func showInstallingUpdate(withApplicationTerminated applicationTerminated: Bool, retryTerminatingApplication: @escaping () -> Void) { phase = .restarting }
    func showUpdateInstalledAndRelaunched(_ relaunched: Bool, acknowledgement: @escaping () -> Void) { acknowledgement() }
    func dismissUpdateInstallation() {
        choice = nil; readyReply = nil; cancelOperation = nil
        if phase != .failed && phase != .current { phase = .idle }
    }
}
extension AppUpdateCoordinator: SPUUpdaterDelegate {
    func updater(_ updater: SPUUpdater, shouldDownloadReleaseNotesForUpdate updateItem: SUAppcastItem) -> Bool { false }
    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: Error?) { userInitiated = false }
}
