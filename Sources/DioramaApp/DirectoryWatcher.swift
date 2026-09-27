import Foundation
import CoreServices

/// FSEvents watches whole trees without opening every transcript or keeping agents alive.
@MainActor final class DirectoryWatcher {
    private var stream: FSEventStreamRef?
    private let callback: Callback
    private final class Callback: @unchecked Sendable {
        let action: @MainActor @Sendable ([String]) -> Void
        init(_ action: @escaping @MainActor @Sendable ([String]) -> Void) { self.action = action }
    }
    convenience init(paths: [String], action: @escaping @MainActor @Sendable () -> Void) {
        self.init(paths: paths, changed: { _ in action() })
    }
    init(paths: [String], changed: @escaping @MainActor @Sendable ([String]) -> Void) {
        callback = Callback(changed)
        var context = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(callback).toOpaque(), retain: nil, release: nil, copyDescription: nil)
        stream = FSEventStreamCreate(nil, { _, info, _, paths, _, _ in
            guard let info else { return }
            let callback = Unmanaged<Callback>.fromOpaque(info).takeUnretainedValue()
            let changed = unsafeBitCast(paths, to: NSArray.self) as? [String] ?? []
            Task { @MainActor in callback.action(changed) }
        }, &context, paths as CFArray, FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 0.05,
        FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer | kFSEventStreamCreateFlagUseCFTypes))
        if let stream { FSEventStreamSetDispatchQueue(stream, .main); FSEventStreamStart(stream) }
    }
    isolated deinit {
        if let stream { FSEventStreamStop(stream); FSEventStreamInvalidate(stream); FSEventStreamRelease(stream) }
    }
}
