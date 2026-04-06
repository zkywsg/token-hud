// token_hud/Overlay/NotchWindowManager.swift
import AppKit
import SwiftUI

@MainActor
final class NotchWindowManager {

    private var leftWindow: NSWindow?
    private var rightWindow: NSWindow?
    private var leftHostingView: NSHostingView<AnyView>?
    private var rightHostingView: NSHostingView<AnyView>?
    private let stateWatcher: StateWatcher
    private let widgetStore: WidgetStore
    private let appFilterStore: AppFilterStore
    private let appWatcher: AppWatcher
    private var screenObserver: NSObjectProtocol?

    init(stateWatcher: StateWatcher, widgetStore: WidgetStore,
         appFilterStore: AppFilterStore, appWatcher: AppWatcher) {
        self.stateWatcher    = stateWatcher
        self.widgetStore     = widgetStore
        self.appFilterStore  = appFilterStore
        self.appWatcher      = appWatcher
    }

    func setup() {
        if let screen = notchScreen() {
            (leftWindow,  leftHostingView)  = makeOverlayWindow(side: .left,  screen: screen)
            (rightWindow, rightHostingView) = makeOverlayWindow(side: .right, screen: screen)
            positionWindows(screen: screen)
        }
        // Non-notch: no overlay windows; AppDelegate creates a status item.

        // Wire up app-filter visibility
        appWatcher.onChange = { [weak self] bundleID in
            self?.updateVisibility(for: bundleID)
        }
        updateVisibility(for: appWatcher.frontmostBundleID)

        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.handleScreenChange() }
        }
    }

    /// Returns the first screen that has a notch (auxiliaryTopLeftArea), preferring the built-in display.
    private func notchScreen() -> NSScreen? {
        NSScreen.screens.first { $0.auxiliaryTopLeftArea != nil }
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

    private func makeOverlayWindow(side: Side, screen: NSScreen) -> (NSWindow, NSHostingView<AnyView>) {
        let window = NSWindow(
            contentRect: .zero,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false,
            screen: screen
        )
        window.level              = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.statusWindow)) + 1)
        window.backgroundColor    = .clear
        window.isOpaque           = false
        window.hasShadow          = false
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

        let hostingView = NSHostingView(rootView: rootView)
        window.contentView = hostingView
        // Don't show until frame is calculated in positionWindows
        return (window, hostingView)
    }

    private func positionWindows(screen: NSScreen) {
        guard
            let leftArea  = screen.auxiliaryTopLeftArea,
            let rightArea = screen.auxiliaryTopRightArea
        else {
            print("[token_hud] auxiliaryTopLeftArea is nil — no notch detected")
            return
        }

        let padding: CGFloat = 6
        let maxFraction: CGFloat = 0.4

        // auxiliaryTopLeft/RightArea are in the screen's local coordinate space.
        // Convert to global by adding screen.frame.origin.
        let ox = screen.frame.origin.x
        let oy = screen.frame.origin.y

        if let lw = leftWindow, let lhv = leftHostingView {
            lhv.layoutSubtreeIfNeeded()
            let contentWidth = lhv.intrinsicContentSize.width
            let maxWidth = leftArea.width * maxFraction
            let width = max(min(contentWidth, maxWidth), 20)

            // Right-align to notch left edge
            let frame = NSRect(
                x: ox + leftArea.maxX - width - padding,
                y: oy + leftArea.minY,
                width: width,
                height: leftArea.height
            )
            lw.setFrame(frame, display: true)
            lw.orderFrontRegardless()
            print("[token_hud] leftWindow.frame  = \(frame)  (contentWidth=\(contentWidth))")
        }

        if let rw = rightWindow, let rhv = rightHostingView {
            rhv.layoutSubtreeIfNeeded()
            let contentWidth = rhv.intrinsicContentSize.width
            let maxWidth = rightArea.width * maxFraction
            let width = max(min(contentWidth, maxWidth), 20)

            // Left-align to notch right edge
            let frame = NSRect(
                x: ox + rightArea.minX + padding,
                y: oy + rightArea.minY,
                width: width,
                height: rightArea.height
            )
            rw.setFrame(frame, display: true)
            rw.orderFrontRegardless()
            print("[token_hud] rightWindow.frame = \(frame)  (contentWidth=\(contentWidth))")
        }
    }

    private func handleScreenChange() {
        guard let screen = notchScreen() else {
            leftWindow?.orderOut(nil)
            rightWindow?.orderOut(nil)
            return
        }
        if leftWindow == nil {
            (leftWindow,  leftHostingView)  = makeOverlayWindow(side: .left,  screen: screen)
            (rightWindow, rightHostingView) = makeOverlayWindow(side: .right, screen: screen)
        }
        positionWindows(screen: screen)
        updateVisibility(for: appWatcher.frontmostBundleID)
    }

    // MARK: - App Filter Visibility

    private func updateVisibility(for bundleID: String?) {
        if appFilterStore.isAllowed(bundleID) {
            showWindows()
        } else {
            hideWindowsWithFade()
        }
    }

    private func showWindows() {
        leftWindow?.alphaValue = 1.0
        rightWindow?.alphaValue = 1.0
        leftWindow?.orderFrontRegardless()
        rightWindow?.orderFrontRegardless()
    }

    private func hideWindowsWithFade() {
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.3
            leftWindow?.animator().alphaValue = 0.0
            rightWindow?.animator().alphaValue = 0.0
        }, completionHandler: { [weak self] in
            Task { @MainActor [weak self] in
                self?.leftWindow?.orderOut(nil)
                self?.rightWindow?.orderOut(nil)
            }
        })
    }
}
