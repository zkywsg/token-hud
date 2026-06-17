@preconcurrency import AppKit

@MainActor
final class GlobalHotkeyManager {

    var onHotkey: (() -> Void)?

    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var defaultsObserver: NSObjectProtocol?
    private var activationObserver: NSObjectProtocol?

    // MARK: - Setup

    func setup() {
        installLocalMonitorIfNeeded()
        refreshGlobalMonitor()
        installObserversIfNeeded()
    }

    func teardown() {
        if let m = globalMonitor { NSEvent.removeMonitor(m) }
        if let m = localMonitor  { NSEvent.removeMonitor(m) }
        if let observer = defaultsObserver { NotificationCenter.default.removeObserver(observer) }
        if let observer = activationObserver { NotificationCenter.default.removeObserver(observer) }
        globalMonitor = nil
        localMonitor = nil
        defaultsObserver = nil
        activationObserver = nil
    }

    private func installObserversIfNeeded() {
        if defaultsObserver == nil {
            defaultsObserver = NotificationCenter.default.addObserver(
                forName: UserDefaults.didChangeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.refreshGlobalMonitor()
                }
            }
        }

        if activationObserver == nil {
            activationObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.didBecomeActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.refreshGlobalMonitor()
                }
            }
        }
    }

    private func installLocalMonitorIfNeeded() {
        guard localMonitor == nil else { return }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) {
            [weak self] event in
            self?.handle(event)
            return event
        }
    }

    private func refreshGlobalMonitor() {
        let shouldInstallGlobalMonitor = Self.configuredHotkey() != nil && Self.isAccessibilityEnabled

        if shouldInstallGlobalMonitor {
            installGlobalMonitorIfNeeded()
        } else {
            removeGlobalMonitor()
        }
    }

    private func installGlobalMonitorIfNeeded() {
        guard globalMonitor == nil else { return }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown, .flagsChanged]) {
            [weak self] event in
            self?.handle(event)
        }
    }

    private func removeGlobalMonitor() {
        if let m = globalMonitor {
            NSEvent.removeMonitor(m)
            globalMonitor = nil
        }
    }

    // MARK: - Hotkey Matching

    private func handle(_ event: NSEvent) {
        guard let hotkey = Self.configuredHotkey() else { return }

        // Strip non-device flags from both before comparing
        let eventClean = event.modifierFlags.intersection([.command, .option, .control, .shift, .function])
        let storedClean = hotkey.modifiers.intersection([.command, .option, .control, .shift, .function])

        guard event.keyCode == hotkey.keyCode, eventClean == storedClean else { return }

        onHotkey?()
    }

    static func configuredHotkey() -> (keyCode: UInt16, modifiers: NSEvent.ModifierFlags)? {
        let rawKeyCode = UserDefaults.standard.object(forKey: "floatingHotkeyKeyCode") as? Int ?? -1
        guard rawKeyCode >= 0, rawKeyCode <= Int(UInt16.max) else { return nil }

        let rawModifiers = UserDefaults.standard.object(forKey: "floatingHotkeyModifiers") as? Int ?? 0
        let modifiers = NSEvent.ModifierFlags(rawValue: UInt(rawModifiers))
            .intersection([.command, .option, .control, .shift, .function])
        guard !modifiers.isEmpty else { return nil }

        return (UInt16(rawKeyCode), modifiers)
    }

    // MARK: - Accessibility Check

    static var isAccessibilityEnabled: Bool {
        AXIsProcessTrusted()
    }

    nonisolated static func requestAccessibility() {
        let prompt = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [prompt: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }
}
