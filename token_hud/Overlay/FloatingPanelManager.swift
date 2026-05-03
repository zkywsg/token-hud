import AppKit
import SwiftUI

@MainActor
final class FloatingPanelManager: NSObject, NSWindowDelegate {

    private var window: NSPanel?
    private var hostingView: NSHostingView<AnyView>?
    private let stateWatcher: StateWatcher
    private let widgetStore: WidgetStore

    init(stateWatcher: StateWatcher, widgetStore: WidgetStore) {
        self.stateWatcher = stateWatcher
        self.widgetStore = widgetStore
        super.init()
    }

    func setup() {
        let win = makeWindow()
        window = win
        restoreFrame(for: win)
        win.orderFrontRegardless()
    }

    func teardown() {
        saveFrame()
        window?.close()
    }

    func toggle() {
        guard let win = window else { return }
        if win.isVisible {
            saveFrame()
            win.orderOut(nil)
        } else {
            NSApp.activate(ignoringOtherApps: true)
            win.orderFrontRegardless()
        }
    }

    var isVisible: Bool {
        window?.isVisible ?? false
    }

    // MARK: - Window Creation

    private func makeWindow() -> NSPanel {
        let defaultRect = NSRect(x: 200, y: 200, width: 300, height: 60)
        let panel = NSPanel(
            contentRect: defaultRect,
            styleMask: [.borderless, .resizable, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .screenSaver
        panel.backgroundColor = NSColor.black.withAlphaComponent(0.75)
        panel.isOpaque = false
        panel.hasShadow = true
        panel.ignoresMouseEvents = false
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = true
        panel.isReleasedWhenClosed = false
        panel.minSize = PanelResizeCalculator.minimumSize
        panel.becomesKeyOnlyIfNeeded = true
        panel.delegate = self

        let rootView = AnyView(
            FloatingPanelView()
                .environment(stateWatcher)
                .environment(widgetStore)
        )
        let hosting = NSHostingView(rootView: rootView)
        panel.contentView = hosting
        hostingView = hosting

        return panel
    }

    // MARK: - NSWindowDelegate

    nonisolated func windowDidMove(_ notification: Notification) {
        Task { @MainActor in
            saveFrame()
        }
    }

    nonisolated func windowDidResize(_ notification: Notification) {
        Task { @MainActor in
            saveFrame()
        }
    }

    // MARK: - Frame Persistence

    private static let frameKey = "floatingPanelFrame"

    private func saveFrame() {
        guard let win = window else { return }
        let f = win.frame
        let dict: [String: CGFloat] = [
            "x": f.origin.x, "y": f.origin.y,
            "w": f.size.width, "h": f.size.height
        ]
        UserDefaults.standard.set(dict, forKey: Self.frameKey)
    }

    private func restoreFrame(for win: NSWindow) {
        guard let dict = UserDefaults.standard.dictionary(forKey: Self.frameKey) as? [String: CGFloat],
              let x = dict["x"], let y = dict["y"],
              let w = dict["w"], let h = dict["h"]
        else { return }
        win.setFrame(NSRect(x: x, y: y, width: w, height: h), display: true)
    }
}
