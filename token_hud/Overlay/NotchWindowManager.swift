// token_hud/Overlay/NotchWindowManager.swift
import AppKit
import SwiftUI

@MainActor
final class NotchWindowManager {

    private var leftWindow: NSWindow?
    private var rightWindow: NSWindow?
    private let stateWatcher: StateWatcher
    private let widgetStore: WidgetStore
    private var screenObserver: NSObjectProtocol?

    init(stateWatcher: StateWatcher, widgetStore: WidgetStore) {
        self.stateWatcher = stateWatcher
        self.widgetStore  = widgetStore
    }

    func setup() {
        guard let screen = NSScreen.main else { return }

        if screen.auxiliaryTopLeftArea != nil {
            leftWindow  = makeOverlayWindow(side: .left,  screen: screen)
            rightWindow = makeOverlayWindow(side: .right, screen: screen)
            positionWindows(screen: screen)
        }
        // Non-notch: no overlay windows; AppDelegate creates a status item.

        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleScreenChange()
        }
    }

    func teardown() {
        leftWindow?.close()
        rightWindow?.close()
        if let obs = screenObserver {
            NotificationCenter.default.removeObserver(obs)
        }
    }

    // MARK: - Private

    private enum Side { case left, right }

    private func makeOverlayWindow(side: Side, screen: NSScreen) -> NSWindow {
        let window = NSWindow(
            contentRect: .zero,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false,
            screen: screen
        )
        window.level             = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.statusWindow)) + 1)
        window.backgroundColor   = .clear
        window.isOpaque          = false
        window.hasShadow         = false
        window.ignoresMouseEvents = false
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        window.isReleasedWhenClosed = false

        let rootView: AnyView
        switch side {
        case .left:
            rootView = AnyView(
                LeftSideView()
                    .environment(stateWatcher)
                    .environment(widgetStore)
            )
        case .right:
            rootView = AnyView(
                RightSideView()
                    .environment(stateWatcher)
                    .environment(widgetStore)
            )
        }

        window.contentView = NSHostingView(rootView: rootView)
        window.orderFrontRegardless()
        return window
    }

    private func positionWindows(screen: NSScreen) {
        guard
            let leftArea  = screen.auxiliaryTopLeftArea,
            let rightArea = screen.auxiliaryTopRightArea
        else { return }

        let padding: CGFloat = 6

        if let lw = leftWindow {
            let w = max(leftArea.width - padding, 20)
            let h = leftArea.height
            let x = leftArea.minX
            let y = leftArea.minY
            lw.setFrame(NSRect(x: x, y: y, width: w, height: h), display: true)
        }

        if let rw = rightWindow {
            let w = max(rightArea.width - padding, 20)
            let h = rightArea.height
            let x = rightArea.minX + padding
            let y = rightArea.minY
            rw.setFrame(NSRect(x: x, y: y, width: w, height: h), display: true)
        }
    }

    private func handleScreenChange() {
        guard let screen = NSScreen.main else {
            leftWindow?.orderOut(nil)
            rightWindow?.orderOut(nil)
            return
        }
        if screen.auxiliaryTopLeftArea != nil {
            if leftWindow == nil {
                leftWindow  = makeOverlayWindow(side: .left,  screen: screen)
                rightWindow = makeOverlayWindow(side: .right, screen: screen)
            }
            positionWindows(screen: screen)
        } else {
            leftWindow?.orderOut(nil)
            rightWindow?.orderOut(nil)
        }
    }
}
