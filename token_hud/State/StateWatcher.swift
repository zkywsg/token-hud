// token_hud/State/StateWatcher.swift
import Foundation
import Observation

@Observable
@MainActor
final class StateWatcher {

    // MARK: - Published state

    private(set) var currentState: StateFile?
    private(set) var lastError: String?
    private(set) var lastUpdated: Date?

    /// Real data when available, falls back to mock preview so widgets always show something.
    var effectiveState: StateFile { currentState ?? .preview }

    // MARK: - Configuration

    var stateFilePath: String {
        didSet { restartIfNeeded() }
    }

    // MARK: - Private

    private var dispatchSource: DispatchSourceFileSystemObject?
    private var fileDescriptor: Int32 = -1
    private var isRunning = false

    // MARK: - Init

    init(stateFilePath: String = ("~/.token-hud/state.json" as NSString).expandingTildeInPath) {
        self.stateFilePath = stateFilePath
    }

    // MARK: - Lifecycle

    func start() {
        guard !isRunning else { return }
        isRunning = true
        readNow()
        startWatching()
    }

    func stop() {
        isRunning = false
        dispatchSource?.cancel()
        dispatchSource = nil
        if fileDescriptor >= 0 {
            close(fileDescriptor)
            fileDescriptor = -1
        }
    }

    // MARK: - Internals

    private func startWatching() {
        let path = stateFilePath
        let fd = open(path, O_EVTONLY)
        guard fd >= 0 else {
            // File doesn't exist yet — retry after 2s on main queue
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                guard let self, self.isRunning else { return }
                self.readNow()
                self.startWatching()
            }
            return
        }
        fileDescriptor = fd

        // Use .main so the handler runs on the main actor — no cross-queue Task hops needed.
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .rename, .delete],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            guard let self else { return }
            let flags = source.data
            if flags.contains(.delete) || flags.contains(.rename) {
                self.stop()
                self.start()
            } else {
                self.readNow()
            }
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        dispatchSource = source
    }

    /// Read state.json synchronously on the main actor.
    /// The file is small (< 4 KB) so synchronous I/O here is acceptable.
    func readNow() {
        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: stateFilePath))
            let decoded = try JSONDecoder().decode(StateFile.self, from: data)
            currentState = decoded
            lastUpdated = Date()
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func restartIfNeeded() {
        guard isRunning else { return }
        stop()
        start()
    }
}
