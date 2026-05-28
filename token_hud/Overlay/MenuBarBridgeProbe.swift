import AppKit

/// Minimal menu-bar probe for validating whether a bridge can render inside the macOS menu bar.
@MainActor
final class MenuBarBridgeProbe {
    private static let isEnabledByDefault = false
    private var statusItem: NSStatusItem?
    private let length: CGFloat

    init(length: CGFloat = 120) {
        self.length = length
    }

    func setupIfNeeded() {
        guard Self.isEnabledByDefault else { return }
        guard statusItem == nil, Self.hasNotchedMainScreen else { return }

        let item = NSStatusBar.system.statusItem(withLength: length)
        if let button = item.button {
            button.image = nil
            button.title = ""
            button.toolTip = "token_hud menu-bar bridge probe"
            button.wantsLayer = true
            button.layer?.backgroundColor = NSColor.black.cgColor
            button.layer?.cornerRadius = 0
            button.layer?.masksToBounds = true
            button.setButtonType(.momentaryChange)
            button.isBordered = false
        }
        statusItem = item
    }

    func teardown() {
        guard let item = statusItem else { return }
        NSStatusBar.system.removeStatusItem(item)
        statusItem = nil
    }

    private static var hasNotchedMainScreen: Bool {
        guard let screen = NSScreen.main else { return false }
        let leftAux = screen.auxiliaryTopLeftArea ?? .null
        let rightAux = screen.auxiliaryTopRightArea ?? .null
        return leftAux != .null && rightAux != .null
    }
}
