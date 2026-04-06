// token_hud/State/AppWatcher.swift
import AppKit
import Observation

@Observable @MainActor
final class AppWatcher {

    private(set) var frontmostBundleID: String? = nil
    var onChange: ((String?) -> Void)?

    private var observer: NSObjectProtocol?

    func start() {
        // Seed initial value
        frontmostBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier

        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            let bundleID = app?.bundleIdentifier
            Task { @MainActor [weak self] in
                self?.frontmostBundleID = bundleID
                self?.onChange?(bundleID)
            }
        }
    }

    func stop() {
        if let obs = observer {
            NSWorkspace.shared.notificationCenter.removeObserver(obs)
            observer = nil
        }
    }
}
