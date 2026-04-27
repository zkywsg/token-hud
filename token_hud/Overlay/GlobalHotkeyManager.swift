@preconcurrency import AppKit

@MainActor
final class GlobalHotkeyManager {

    var onHotkey: (() -> Void)?

    private var globalMonitor: Any?
    private var localMonitor: Any?

    // MARK: - Setup

    func setup() {
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown, .flagsChanged]) {
            [weak self] event in
            self?.handle(event)
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) {
            [weak self] event in
            self?.handle(event)
            return event
        }
    }

    func teardown() {
        if let m = globalMonitor { NSEvent.removeMonitor(m) }
        if let m = localMonitor  { NSEvent.removeMonitor(m) }
        globalMonitor = nil
        localMonitor = nil
    }

    // MARK: - Hotkey Matching

    private func handle(_ event: NSEvent) {
        let storedKeyCode = UserDefaults.standard.integer(forKey: "floatingHotkeyKeyCode")
        guard storedKeyCode >= 0 else { return }

        let storedMods = UserDefaults.standard.integer(forKey: "floatingHotkeyModifiers")
        let storedFlags = NSEvent.ModifierFlags(rawValue: UInt(storedMods))

        // Strip non-device flags from both before comparing
        let eventClean = event.modifierFlags.intersection([.command, .option, .control, .shift, .function])
        let storedClean = storedFlags.intersection([.command, .option, .control, .shift, .function])

        guard event.keyCode == storedKeyCode, eventClean == storedClean else { return }

        onHotkey?()
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
