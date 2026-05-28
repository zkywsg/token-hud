import AppKit
import CoreGraphics
import SwiftUI

@MainActor
final class NotchHostPanelManager: NSObject, NSWindowDelegate {

    private var detachedWindow: NSPanel?
    private var overlayWindow: NSPanel?
    private let stateWatcher: StateWatcher
    private let widgetStore: WidgetStore
    let hostState = NotchHostState()

    private var globalMouseMonitor: Any?
    private var isAnimating = false
    private var collapseTimer: DispatchWorkItem?
    private var mouseUpMonitor: Any?
    private var mouseDownMonitor: Any?
    private var isDragging = false
    private var savedDetachedFrame: CGRect?
    private var targetDisplayID: CGDirectDisplayID?
    private var surfaceStrategy: NotchSurfaceStrategy = .publicPanel
    private var isOverlayDelegatedToSkyLight = false

    private enum WindowRole {
        case detached
        case notchSurface
    }

    private static let hostedStyleMask: NSWindow.StyleMask = [
        .borderless,
        .nonactivatingPanel,
        .utilityWindow,
        .hudWindow
    ]
    private static let detachedStyleMask: NSWindow.StyleMask = [.borderless, .resizable, .nonactivatingPanel]

    init(stateWatcher: StateWatcher, widgetStore: WidgetStore) {
        self.stateWatcher = stateWatcher
        self.widgetStore = widgetStore
        super.init()
    }

    func setup() {
        let detached = makeWindow(styleMask: Self.detachedStyleMask, role: .detached)
        let overlay = makeWindow(styleMask: Self.hostedStyleMask, role: .notchSurface)
        detachedWindow = detached
        overlayWindow = overlay
        configureSurfaceStrategy(for: overlay)
        restoreState()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    func teardown() {
        NotificationCenter.default.removeObserver(self)
        removeGlobalMouseMonitor()
        removeMouseUpMonitor()
        removeMouseDownMonitor()
        saveState()
        detachedWindow?.close()
        overlayWindow?.close()
    }

    func toggle() {
        if isVisible {
            saveState()
            detachedWindow?.orderOut(nil)
            overlayWindow?.orderOut(nil)
            removeGlobalMouseMonitor()
        } else {
            NSApp.activate(ignoringOtherApps: true)
            if hostState.isDetached {
                detachedWindow?.orderFrontRegardless()
            } else {
                prepareOverlayForDisplay(label: "toggle hosted")
                transitionTo(.collapsed)
            }
        }
    }

    var isVisible: Bool {
        (detachedWindow?.isVisible ?? false) || (overlayWindow?.isVisible ?? false)
    }

    // MARK: - Window Creation

    private func makeWindow(styleMask: NSWindow.StyleMask, role: WindowRole) -> NSPanel {
        let defaultRect = NSRect(x: 200, y: 200, width: 300, height: 60)
        let panel: NSPanel
        switch role {
        case .detached:
            panel = NSPanel(
                contentRect: defaultRect,
                styleMask: styleMask,
                backing: .buffered,
                defer: false
            )
            panel.level = .screenSaver
        case .notchSurface:
            panel = NotchSurfaceWindow(
                contentRect: defaultRect,
                styleMask: styleMask,
                backing: .buffered,
                defer: false
            )
            panel.level = NotchSurfaceStrategy.skyLightSpace.windowLevel
        }
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = false
        panel.isMovableByWindowBackground = role == .detached
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = true
        panel.isReleasedWhenClosed = false
        panel.minSize = role == .detached ? PanelResizeCalculator.minimumSize : .zero
        panel.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        panel.becomesKeyOnlyIfNeeded = true
        panel.delegate = self

        let rootView = AnyView(
            NotchHostRootView()
                .environment(stateWatcher)
                .environment(widgetStore)
                .environment(hostState)
        )
        let hosting = NSHostingView(rootView: rootView)
        let containerView = NotchTrackingContainerView(frame: NSRect(origin: .zero, size: defaultRect.size))
        hosting.frame = containerView.bounds
        hosting.autoresizingMask = [.width, .height]
        containerView.addSubview(hosting)
        containerView.manager = self
        panel.contentView = containerView

        return panel
    }

    private func configureSurfaceStrategy(for overlay: NSPanel) {
        if SkyLightNotchSpace.shared.isAvailable {
            surfaceStrategy = .skyLightSpace
        } else {
            surfaceStrategy = .publicPanel
        }

        overlay.level = surfaceStrategy.windowLevel
        print(
            """
            [NotchDiagnostics] surface strategy configured
              strategy: \(surfaceStrategy.rawValue)
              skyLight: \(SkyLightNotchSpace.shared.diagnosticsDescription)
            """
        )
    }

    private func prepareOverlayForDisplay(label: String) {
        guard let overlay = overlayWindow else { return }
        applyHostedStyle()
        overlay.level = surfaceStrategy.windowLevel
        overlay.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        overlay.orderFrontRegardless()

        if surfaceStrategy == .skyLightSpace {
            isOverlayDelegatedToSkyLight = SkyLightNotchSpace.shared.delegateWindow(overlay)
        } else {
            isOverlayDelegatedToSkyLight = false
        }

        logNotchDiagnostics(
            "\(label) surface prepared",
            requestedFrame: nil,
            actualFrame: overlay.frame
        )
    }

    // MARK: - Style Masks

    private func applyHostedStyle() {
        guard let win = overlayWindow else { return }
        win.styleMask = Self.hostedStyleMask
        win.minSize = .zero
        win.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
    }

    private func applyDetachedStyle() {
        guard let win = detachedWindow else { return }
        win.styleMask = Self.detachedStyleMask
        win.minSize = PanelResizeCalculator.minimumSize
        win.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
    }

    // MARK: - Geometry

    private func computeGeometry(for screen: NSScreen) -> NotchGeometry {
        let leftAux = screen.auxiliaryTopLeftArea ?? .null
        let rightAux = screen.auxiliaryTopRightArea ?? .null
        if leftAux == .null && rightAux == .null {
            return NotchGeometryCalculator.noNotchFallback(screenFrame: screen.frame)
        }
        return NotchGeometryCalculator.notchGeometry(
            screenFrame: screen.frame,
            safeAreaInsetTop: screen.safeAreaInsets.top,
            auxiliaryTopLeftArea: leftAux,
            auxiliaryTopRightArea: rightAux
        )
    }

    private func computeFrames(for screen: NSScreen, geometry: NotchGeometry) -> NotchFrames {
        NotchGeometryCalculator.notchFrames(screenFrame: screen.frame, geometry: geometry)
    }

    private func preferredScreen(preferredWindow: NSWindow? = nil) -> NSScreen? {
        if let targetDisplayID,
           let screen = NSScreen.screens.first(where: { $0.tokenHUDDisplayID == targetDisplayID }) {
            return screen
        }

        if let screen = preferredWindow?.screen, screen.tokenHUDHasNotch {
            rememberTargetScreen(screen)
            return screen
        }

        if let main = NSScreen.main, main.tokenHUDHasNotch {
            rememberTargetScreen(main)
            return main
        }

        if let notched = NSScreen.screens.first(where: { $0.tokenHUDHasNotch }) {
            rememberTargetScreen(notched)
            return notched
        }

        if let screen = preferredWindow?.screen {
            rememberTargetScreen(screen)
            return screen
        }

        if let main = NSScreen.main {
            rememberTargetScreen(main)
            return main
        }

        return NSScreen.screens.first
    }

    private func rememberTargetScreen(_ screen: NSScreen) {
        targetDisplayID = screen.tokenHUDDisplayID
    }

    private func refreshGeometry(for screen: NSScreen) {
        rememberTargetScreen(screen)
        let geo = computeGeometry(for: screen)
        let frames = computeFrames(for: screen, geometry: geo)
        applyGeometry(geo, frames: frames, screen: screen)
    }

    private func applyGeometry(_ geo: NotchGeometry, frames: NotchFrames, screen: NSScreen) {
        hostState.geometry = geo
        hostState.frames = frames
        hostState.screenFrame = screen.frame
        hostState.gapWidth = geo.hasNotch ? geo.notchGapWidth : 0
    }

    private func logNotchDiagnostics(
        _ label: String,
        requestedFrame: CGRect?,
        actualFrame: CGRect? = nil,
        screen: NSScreen? = nil,
        geometry: NotchGeometry? = nil
    ) {
        let diagnosticWindow = hostState.isDetached ? detachedWindow : overlayWindow
        let targetScreen = screen ?? preferredScreen(preferredWindow: diagnosticWindow)
        let geo = geometry ?? hostState.geometry
        let leftAux = targetScreen?.auxiliaryTopLeftArea ?? .null
        let rightAux = targetScreen?.auxiliaryTopRightArea ?? .null
        let safeInsets = targetScreen?.safeAreaInsets ?? NSEdgeInsetsZero
        let collection = diagnosticWindow?.collectionBehavior.rawValue ?? 0
        let level = diagnosticWindow?.level.rawValue ?? 0

        print(
            """
            [NotchDiagnostics] \(label)
              requestedFrame: \(String(describing: requestedFrame))
              actualFrame: \(String(describing: actualFrame ?? diagnosticWindow?.frame))
              screen.frame: \(String(describing: targetScreen?.frame))
              screen.visibleFrame: \(String(describing: targetScreen?.visibleFrame))
              screen.safeAreaInsets: \(safeInsets)
              auxiliaryTopLeftArea: \(leftAux)
              auxiliaryTopRightArea: \(rightAux)
              geometry: \(String(describing: geo))
              window.level: \(level)
              collectionBehavior.rawValue: \(collection)
              notchSurfaceStrategy: \(surfaceStrategy.rawValue)
              overlayDelegatedToSkyLight: \(isOverlayDelegatedToSkyLight)
              skyLight: \(SkyLightNotchSpace.shared.diagnosticsDescription)
            """
        )
    }

    private func setFrameWithDiagnostics(
        _ frame: CGRect,
        display: Bool,
        label: String,
        screen: NSScreen? = nil,
        geometry: NotchGeometry? = nil
    ) {
        let win = hostState.isDetached ? detachedWindow : overlayWindow
        guard let win else { return }
        logNotchDiagnostics("\(label) requested", requestedFrame: frame, screen: screen, geometry: geometry)
        win.setFrame(frame, display: display)
        logNotchDiagnostics("\(label) actual", requestedFrame: frame, actualFrame: win.frame, screen: screen, geometry: geometry)
    }

    // MARK: - Global Mouse Monitor (notch region hover)

    private func installGlobalMouseMonitor() {
        guard globalMouseMonitor == nil else { return }
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] event in
            Task { @MainActor [weak self] in
                self?.handleGlobalMouseMove(event)
            }
        }
    }

    private func removeGlobalMouseMonitor() {
        if let monitor = globalMouseMonitor {
            NSEvent.removeMonitor(monitor)
            globalMouseMonitor = nil
        }
    }

    private func handleGlobalMouseMove(_ event: NSEvent) {
        guard hostState.isHosted, !isDragging else { return }
        let isInside = isMouseInNotchRegion()

        if isInside && hostState.isCollapsed {
            cancelCollapseTimer()
            transitionTo(.expanded)
        } else if !isInside && hostState.isExpanded {
            scheduleCollapse()
        }
    }

    // MARK: - Collapse Timer

    private func scheduleCollapse(after delay: TimeInterval = 0.15, onlyIfMouseOutside: Bool = false) {
        cancelCollapseTimer()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            if onlyIfMouseOutside && self.isMouseInNotchRegion() { return }
            self.transitionTo(.collapsed)
        }
        collapseTimer = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func cancelCollapseTimer() {
        collapseTimer?.cancel()
        collapseTimer = nil
    }

    private func isMouseInNotchRegion() -> Bool {
        guard let screen = preferredScreen(preferredWindow: overlayWindow ?? detachedWindow) else { return false }
        guard let geo = hostState.geometry else { return false }
        let notchRegion = NotchGeometryCalculator.notchRegion(screenFrame: screen.frame, geometry: geo)
        return notchRegion.contains(NSEvent.mouseLocation)
    }

    // MARK: - State Machine

    private func transitionTo(_ newMode: NotchHostMode) {
        guard hostState.mode != newMode, !isAnimating else { return }

        let oldMode = hostState.mode
        hostState.mode = newMode

        switch (oldMode, newMode) {
        case (.detached, .collapsed):
            snapToCollapsed()
        case (_, .collapsed):
            animateToCollapsed()
        case (_, .expanded):
            animateToExpanded()
        case (_, .detached):
            switchToDetached()
        }
    }

    private func animateToCollapsed() {
        guard let win = overlayWindow, let frames = hostState.frames else { return }
        cancelCollapseTimer()
        isAnimating = true
        detachedWindow?.orderOut(nil)
        prepareOverlayForDisplay(label: "animate collapsed")
        win.isMovableByWindowBackground = false
        win.ignoresMouseEvents = true
        removeMouseDownMonitor()

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            hostState.expansionProgress = 0
            self.logNotchDiagnostics("animate collapsed requested", requestedFrame: frames.collapsed)
            win.animator().setFrame(frames.collapsed, display: true)
        } completionHandler: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.logNotchDiagnostics("animate collapsed actual", requestedFrame: frames.collapsed, actualFrame: win.frame)
                self.isAnimating = false
                self.installGlobalMouseMonitor()
                self.saveState()
            }
        }
    }

    private func animateToExpanded(collapseAfterFeedback: Bool = false) {
        guard let win = overlayWindow, let frames = hostState.frames else { return }
        cancelCollapseTimer()
        isAnimating = true
        detachedWindow?.orderOut(nil)
        prepareOverlayForDisplay(label: "animate expanded")
        win.isMovableByWindowBackground = true
        win.ignoresMouseEvents = false
        installMouseDownMonitorIfNeeded()

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.25
            hostState.expansionProgress = 1
            self.logNotchDiagnostics("animate expanded requested", requestedFrame: frames.expanded)
            win.animator().setFrame(frames.expanded, display: true)
        } completionHandler: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.logNotchDiagnostics("animate expanded actual", requestedFrame: frames.expanded, actualFrame: win.frame)
                self.isAnimating = false
                self.installGlobalMouseMonitor()
                if collapseAfterFeedback {
                    self.scheduleCollapse(after: 1.0, onlyIfMouseOutside: true)
                }
            }
        }
    }

    private func switchToDetached() {
        guard let win = detachedWindow else { return }
        removeGlobalMouseMonitor()
        cancelCollapseTimer()
        removeMouseDownMonitor()
        overlayWindow?.orderOut(nil)
        applyDetachedStyle()
        win.isMovableByWindowBackground = true
        win.ignoresMouseEvents = false
        win.orderFrontRegardless()

        // Position below the notch area
        if let saved = savedDetachedFrame {
            setFrameWithDiagnostics(saved, display: true, label: "switch detached saved")
        } else if let frames = hostState.frames {
            let offset = frames.collapsed.height + 40
            let newFrame = NSRect(
                x: frames.collapsed.midX - 150,
                y: frames.collapsed.minY - offset,
                width: 300,
                height: 60
            )
            setFrameWithDiagnostics(newFrame, display: true, label: "switch detached default")
        }
        saveState()
    }

    private func snapToCollapsed() {
        guard let win = detachedWindow else { return }
        savedDetachedFrame = win.frame
        win.orderOut(nil)
        hostState.mode = .expanded
        animateToExpanded(collapseAfterFeedback: true)
    }

    // MARK: - NSWindowDelegate

    func windowDidMove(_ notification: Notification) {
        let movedWindow = notification.object as? NSWindow
        let movedWindowNumber = movedWindow?.windowNumber
        let movedFrame = movedWindow?.frame

        guard !isAnimating else { return }

        if hostState.isHosted {
            // Check for detach
            if let movedWindowNumber,
               let movedFrame,
               movedWindowNumber == overlayWindow?.windowNumber,
               let collapsedFrame = hostState.frames?.collapsed {
                if NotchGeometryCalculator.shouldDetachFromCollapsed(
                    panelFrame: movedFrame,
                    collapsedFrame: collapsedFrame
                ) {
                    transitionTo(.detached)
                }
            }
        } else if hostState.isDetached,
                  let movedWindowNumber,
                  movedWindowNumber == detachedWindow?.windowNumber {
            if let screen = movedWindow?.screen {
                refreshGeometry(for: screen)
            }
            saveDetachedFrame()
            installMouseUpMonitorIfNeeded()
        }
    }

    func windowDidResize(_ notification: Notification) {
        guard !isAnimating else { return }
        if hostState.isHosted {
            // Resize while hosted should not happen (style mask prevents it)
            transitionTo(.detached)
        } else {
            saveDetachedFrame()
        }
    }

    // MARK: - Mouse-Up Detection (for snap-on-release)

    private func installMouseUpMonitorIfNeeded() {
        guard mouseUpMonitor == nil else { return }

        mouseUpMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseUp) { [weak self] event in
            Task { @MainActor [weak self] in
                self?.removeMouseUpMonitor()
                self?.isDragging = false
                self?.evaluateSnap()
            }
            return event
        }
    }

    private func removeMouseUpMonitor() {
        if let monitor = mouseUpMonitor {
            NSEvent.removeMonitor(monitor)
            mouseUpMonitor = nil
        }
    }

    // MARK: - Mouse-Down Detection (for drag state)

    private func installMouseDownMonitorIfNeeded() {
        guard mouseDownMonitor == nil else { return }

        mouseDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            Task { @MainActor [weak self] in
                self?.isDragging = true
            }
            return event
        }
    }

    private func removeMouseDownMonitor() {
        if let monitor = mouseDownMonitor {
            NSEvent.removeMonitor(monitor)
            mouseDownMonitor = nil
        }
    }

    private func evaluateSnap() {
        guard hostState.isDetached, let win = detachedWindow, let frames = hostState.frames else { return }
        if NotchGeometryCalculator.shouldSnapToNotch(
            panelFrame: win.frame,
            snapZone: frames.snapZone
        ) {
            snapToCollapsed()
        }
    }

    // MARK: - Drag Detection

    /// Call from a local event monitor to track drag state.
    func handleMouseDown() {
        isDragging = true
    }

    func handleMouseUp() {
        isDragging = false
    }

    // MARK: - Screen Changes

    @objc private func screenParametersChanged() {
        guard let screen = preferredScreen(preferredWindow: overlayWindow ?? detachedWindow) else { return }
        refreshGeometry(for: screen)
        guard let frames = hostState.frames, let geo = hostState.geometry else { return }

        if hostState.isHosted {
            guard let win = overlayWindow else { return }
            isAnimating = true
            prepareOverlayForDisplay(label: "screen change hosted")
            win.ignoresMouseEvents = true
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.2
                self.logNotchDiagnostics(
                    "screen change collapsed requested",
                    requestedFrame: frames.collapsed,
                    screen: screen,
                    geometry: geo
                )
                win.animator().setFrame(frames.collapsed, display: true)
            } completionHandler: { [weak self] in
                Task { @MainActor in
                    guard let self else { return }
                    self.logNotchDiagnostics(
                        "screen change collapsed actual",
                        requestedFrame: frames.collapsed,
                        actualFrame: win.frame
                    )
                    self.isAnimating = false
                    self.installGlobalMouseMonitor()
                }
            }
        }
    }

    // MARK: - State Persistence

    private static let modeKey = "notchHostMode"
    private static let detachedFrameKey = "notchHostDetachedFrame"
    private static let savedFreeFrameKey = "notchHostSavedFreeFrame"

    private func saveDetachedFrame() {
        guard let win = detachedWindow, hostState.isDetached else { return }
        let f = win.frame
        let dict: [String: CGFloat] = [
            "x": f.origin.x, "y": f.origin.y,
            "w": f.size.width, "h": f.size.height
        ]
        UserDefaults.standard.set(dict, forKey: Self.detachedFrameKey)
    }

    private func saveState() {
        if hostState.isDetached {
            saveDetachedFrame()
            UserDefaults.standard.set("detached", forKey: Self.modeKey)
        } else {
            UserDefaults.standard.set("hosted", forKey: Self.modeKey)
            if let frame = savedDetachedFrame {
                let dict: [String: CGFloat] = [
                    "x": frame.origin.x, "y": frame.origin.y,
                    "w": frame.size.width, "h": frame.size.height
                ]
                UserDefaults.standard.set(dict, forKey: Self.savedFreeFrameKey)
            }
        }
    }

    private func restoreState() {
        guard let screen = preferredScreen(preferredWindow: detachedWindow ?? overlayWindow) else { return }
        refreshGeometry(for: screen)
        guard let frames = hostState.frames, let geo = hostState.geometry else { return }

        let savedMode = UserDefaults.standard.string(forKey: Self.modeKey) ?? "hosted"

        // Restore detached frame if available
        if let dict = UserDefaults.standard.dictionary(forKey: Self.detachedFrameKey) as? [String: CGFloat],
           let x = dict["x"], let y = dict["y"],
           let w = dict["w"], let h = dict["h"] {
            savedDetachedFrame = NSRect(x: x, y: y, width: w, height: h)
        }

        if savedMode == "hosted" {
            detachedWindow?.orderOut(nil)
            hostState.mode = .collapsed
            setFrameWithDiagnostics(
                frames.collapsed,
                display: true,
                label: "restore hosted collapsed",
                screen: screen,
                geometry: geo
            )
            hostState.expansionProgress = 0
            applyHostedStyle()
            overlayWindow?.isMovableByWindowBackground = false
            overlayWindow?.ignoresMouseEvents = true
            prepareOverlayForDisplay(label: "restore hosted")
            installGlobalMouseMonitor()
        } else {
            if let saved = savedDetachedFrame {
                setFrameWithDiagnostics(saved, display: true, label: "restore detached saved", screen: screen, geometry: geo)
            }
            hostState.mode = .detached
            hostState.expansionProgress = 1
            applyDetachedStyle()
            detachedWindow?.isMovableByWindowBackground = true
            overlayWindow?.orderOut(nil)
            detachedWindow?.orderFrontRegardless()
        }

        // Restore saved free frame for snap-back
        if let dict = UserDefaults.standard.dictionary(forKey: Self.savedFreeFrameKey) as? [String: CGFloat],
           let x = dict["x"], let y = dict["y"],
           let w = dict["w"], let h = dict["h"] {
            savedDetachedFrame = NSRect(x: x, y: y, width: w, height: h)
        }

        // Check if mouse is already over the notch region
        let mouseLocation = NSEvent.mouseLocation
        if hostState.isCollapsed, let geo = hostState.geometry {
            let notchRegion = NotchGeometryCalculator.notchRegion(screenFrame: screen.frame, geometry: geo)
            if notchRegion.contains(mouseLocation) {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                    self?.transitionTo(.expanded)
                }
            }
        }
    }
}

// MARK: - Tracking Area Container

/// NSView subclass that forwards mouse events from the body panel.
final class NotchTrackingContainerView: NSView {
    weak var manager: NotchHostPanelManager?
}
