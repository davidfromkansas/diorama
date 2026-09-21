import Foundation
import CoreServices

/// FSEvents watches whole trees without opening every transcript or keeping agents alive.
final class DirectoryWatcher {
    private var stream: FSEventStreamRef?
    private let callback: Callback
    private final class Callback: @unchecked Sendable {
        let action: @MainActor @Sendable () -> Void
        init(_ action: @escaping @MainActor @Sendable () -> Void) { self.action = action }
    }
    init(paths: [String], action: @escaping @MainActor @Sendable () -> Void) {
        callback = Callback(action)
        var context = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(callback).toOpaque(), retain: nil, release: nil, copyDescription: nil)
        stream = FSEventStreamCreate(nil, { _, info, _, _, _, _ in
            guard let info else { return }
            let callback = Unmanaged<Callback>.fromOpaque(info).takeUnretainedValue()
            Task { @MainActor in callback.action() }
        }, &context, paths as CFArray, FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 0.5,
        FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents))
        if let stream { FSEventStreamSetDispatchQueue(stream, .main); FSEventStreamStart(stream) }
    }
    isolated deinit {
        if let stream { FSEventStreamStop(stream); FSEventStreamInvalidate(stream); FSEventStreamRelease(stream) }
    }
}
