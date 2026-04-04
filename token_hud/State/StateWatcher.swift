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
    private let queue = DispatchQueue(label: "com.tokenHud.stateWatcher", qos: .utility)
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
            // File doesn't exist yet — retry after 2s
            queue.asyncAfter(deadline: .now() + 2) { [weak self] in
                guard let self else { return }
                Task { @MainActor in
                    guard self.isRunning else { return }
                    self.startWatching()
                }
            }
            return
        }
        fileDescriptor = fd

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .rename, .delete],
            queue: queue
        )
        source.setEventHandler { [weak self] in
            guard let self else { return }
            let flags = source.data
            if flags.contains(.delete) || flags.contains(.rename) {
                Task { @MainActor in self.stop(); self.start() }
            } else {
                Task { @MainActor in self.readNow() }
            }
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        dispatchSource = source
    }

    func readNow() {
        let path = stateFilePath
        queue.async { [weak self] in
            guard let self else { return }
            do {
                let data = try Data(contentsOf: URL(fileURLWithPath: path))
                let decoded = try JSONDecoder().decode(StateFile.self, from: data)
                Task { @MainActor in
                    self.currentState = decoded
                    self.lastUpdated = Date()
                    self.lastError = nil
                }
            } catch {
                Task { @MainActor in
                    self.lastError = error.localizedDescription
                }
            }
        }
    }

    private func restartIfNeeded() {
        guard isRunning else { return }
        stop()
        start()
    }
}
