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
    private var localMouseMonitor: Any?
    private var isAnimating = false
    private var collapseTimer: DispatchWorkItem?
    private var mouseUpMonitor: Any?
    private var mouseDownMonitor: Any?
    private var isDragging = false
    private var isResettingHostedFrame = false
    private var savedDetachedFrame: CGRect?
    private var targetDisplayID: CGDirectDisplayID?
    private var surfaceStrategy: NotchSurfaceStrategy = .publicPanel
    private var isOverlayDelegatedToSkyLight = false
    private var transitionGate = NotchTransitionGate()

    private enum WindowRole {
        case detached
        case notchSurface
    }

    // `.hudWindow` is intentionally omitted — HUD-style panels can trigger
    // system-driven repositioning that fights our pinned hosted frame.
    private static let hostedStyleMask: NSWindow.StyleMask = [
        .borderless,
        .nonactivatingPanel
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
        removeMouseMoveMonitors()
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
            removeMouseMoveMonitors()
        } else {
            NSApp.activate(ignoringOtherApps: true)
            if hostState.isDetached {
                detachedWindow?.orderFrontRegardless()
            } else {
                hostState.mode = .collapsed
                hostState.expansionProgress = 0
                if let frames = hostState.frames {
                    overlayWindow?.setFrame(frames.expanded, display: false)
                }
                prepareOverlayForDisplay(label: "toggle hosted")
                installMouseMoveMonitors()
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
        panel.acceptsMouseMovedEvents = true
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
            if !isOverlayDelegatedToSkyLight {
                surfaceStrategy = .publicPanel
                overlay.level = surfaceStrategy.windowLevel
                print(
                    """
                    [NotchDiagnostics] SkyLight delegation failed; falling back to publicPanel
                      skyLight: \(SkyLightNotchSpace.shared.diagnosticsDescription)
                    """
                )
            }
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

    // MARK: - Hit testing for transparent surface

    /// Returns the rectangle within the hosted overlay's content view where
    /// clicks should actually be received. Anything outside this rectangle
    /// passes through to underlying windows (menu bar, desktop, apps).
    ///
    /// Returns `nil` when the overlay should accept the full surface
    /// (e.g. detached panel, or when geometry isn't known yet).
    func hostedHitMask(in bounds: NSRect) -> NSRect? {
        guard hostState.isHosted else { return nil }
        guard let geometry = hostState.geometry else { return nil }

        let layout = NotchGeometryCalculator.hostedSurfaceLayout(
            screenFrame: hostState.screenFrame,
            geometry: geometry,
            expansionProgress: hostState.expansionProgress
        )

        // Collapsed: the whole top cap is the interactive target. It is
        // intentionally one continuous rect instead of two small side pills.
        if hostState.isCollapsed {
            return layout.topCap.isEmpty ? nil : layout.topCap
        }

        // Expanded: clicks on transparent area above / beside the body
        // should pass through; only the top cap and body are live.
        let liveArea = layout.topCap.union(layout.body)
        return liveArea.isEmpty ? nil : liveArea
    }

    // MARK: - Mouse Move Monitors (notch region hover)

    private enum MouseMoveSource: String {
        case global
        case local
    }

    private func installMouseMoveMonitors() {
        installGlobalMouseMonitor()
        installLocalMouseMonitor()
    }

    private func removeMouseMoveMonitors() {
        removeGlobalMouseMonitor()
        removeLocalMouseMonitor()
    }

    private func installGlobalMouseMonitor() {
        guard globalMouseMonitor == nil else { return }
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] event in
            Task { @MainActor [weak self] in
                self?.handleMouseMove(event, source: .global)
            }
        }
    }

    private func installLocalMouseMonitor() {
        guard localMouseMonitor == nil else { return }
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved) { [weak self] event in
            Task { @MainActor [weak self] in
                self?.handleMouseMove(event, source: .local)
            }
            return event
        }
    }

    private func removeGlobalMouseMonitor() {
        if let monitor = globalMouseMonitor {
            NSEvent.removeMonitor(monitor)
            globalMouseMonitor = nil
        }
    }

    private func removeLocalMouseMonitor() {
        if let monitor = localMouseMonitor {
            NSEvent.removeMonitor(monitor)
            localMouseMonitor = nil
        }
    }

    private func handleMouseMove(_ event: NSEvent, source: MouseMoveSource) {
        guard hostState.isHosted, !isDragging else { return }
        let isInside = isMouseInNotchRegion()

        switch NotchTransitionPolicy.hoverAction(isMouseInside: isInside, mode: hostState.mode) {
        case .expand:
            logHoverDecision(action: "expand", source: source, isInside: isInside)
            cancelCollapseTimer()
            transitionTo(.expanded)
        case .scheduleCollapse:
            if collapseTimer == nil {
                logHoverDecision(action: "scheduleCollapse", source: source, isInside: isInside)
                scheduleCollapse()
            }
        case .cancelCollapse:
            if collapseTimer != nil {
                logHoverDecision(action: "cancelCollapse", source: source, isInside: isInside)
                cancelCollapseTimer()
            }
        case .none:
            break
        }
    }

    private func logHoverDecision(action: String, source: MouseMoveSource, isInside: Bool) {
        print(
            """
            [NotchDiagnostics] hover decision
              source: \(source.rawValue)
              action: \(action)
              mode: \(hostState.mode)
              mouseInsideNotchRegion: \(isInside)
            """
        )
    }

    // MARK: - Collapse Timer

    private func scheduleCollapse(after delay: TimeInterval = 0.15, onlyIfMouseOutside: Bool = false) {
        cancelCollapseTimer(invalidateGeneration: false)
        let token = transitionGate.advance()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            guard self.transitionGate.isCurrent(token) else { return }
            if onlyIfMouseOutside && self.isMouseInNotchRegion() { return }
            self.transitionTo(.collapsed)
        }
        collapseTimer = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func cancelCollapseTimer(invalidateGeneration: Bool = true) {
        collapseTimer?.cancel()
        collapseTimer = nil
        if invalidateGeneration {
            transitionGate.advance()
        }
    }

    private func isMouseInNotchRegion() -> Bool {
        guard let screen = preferredScreen(preferredWindow: overlayWindow ?? detachedWindow) else { return false }
        guard let geo = hostState.geometry else { return false }
        let mouseLocation = NSEvent.mouseLocation
        let hoverRegions = NotchGeometryCalculator.notchHoverRegions(screenFrame: screen.frame, geometry: geo)
        let isInsideCollapsedHoverRegion = hoverRegions.contains { $0.contains(mouseLocation) }
        let isInsideExpandedSurface = isMouse(mouseLocation, inExpandedSurfaceFor: geo)

        return NotchHoverRegionPolicy.isMouseInsideNotchRegion(
            mode: hostState.mode,
            isInsideCollapsedHoverRegion: isInsideCollapsedHoverRegion,
            isInsideExpandedSurface: isInsideExpandedSurface
        )
    }

    private func isMouse(_ mouseLocation: CGPoint, inExpandedSurfaceFor geo: NotchGeometry) -> Bool {
        guard hostState.isExpanded,
              let overlay = overlayWindow
        else { return false }
        let layout = NotchGeometryCalculator.hostedSurfaceLayout(
            screenFrame: hostState.screenFrame,
            geometry: geo,
            expansionProgress: hostState.expansionProgress
        )
        let surfaceRegion = layout.topCap.union(layout.body)
        guard !surfaceRegion.isEmpty else { return false }
        let screenRegion = CGRect(
            x: overlay.frame.minX + surfaceRegion.minX,
            y: overlay.frame.minY + surfaceRegion.minY,
            width: surfaceRegion.width,
            height: surfaceRegion.height
        ).insetBy(dx: -NotchGeometryCalculator.collapsedHoverPadding, dy: -NotchGeometryCalculator.collapsedHoverPadding)

        return screenRegion.contains(mouseLocation)
    }

    // MARK: - State Machine

    private func transitionTo(_ newMode: NotchHostMode) {
        guard hostState.mode != newMode, !isAnimating else { return }

        transitionGate.advance()
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
        guard let win = overlayWindow else { return }
        cancelCollapseTimer()
        detachedWindow?.orderOut(nil)
        reassertHostedFrame(reason: "animate collapsed")
        prepareOverlayForDisplay(label: "animate collapsed")
        win.isMovableByWindowBackground = false
        win.ignoresMouseEvents = NotchMouseEventPolicy.shouldIgnoreWindowMouseEvents(mode: .collapsed)
        removeMouseDownMonitor()

        withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
            hostState.expansionProgress = 0
        }
        installMouseMoveMonitors()
        saveState()
    }

    private func animateToExpanded(collapseAfterFeedback: Bool = false) {
        guard let win = overlayWindow else { return }
        cancelCollapseTimer()
        detachedWindow?.orderOut(nil)
        reassertHostedFrame(reason: "animate expanded")
        prepareOverlayForDisplay(label: "animate expanded")
        // Expanded surface is draggable; once the user drags more than a
        // few pixels the windowDidMove handler immediately detaches and
        // hands the rest of the drag to the detached window.
        win.isMovableByWindowBackground = true
        win.ignoresMouseEvents = NotchMouseEventPolicy.shouldIgnoreWindowMouseEvents(mode: .expanded)
        installMouseDownMonitorIfNeeded()

        withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
            hostState.expansionProgress = 1
        }
        installMouseMoveMonitors()
        if collapseAfterFeedback {
            scheduleCollapse(after: 1.0, onlyIfMouseOutside: true)
        }
    }

    /// Force the hosted overlay back to the canonical expanded frame.
    /// Used after any external factor (Spaces, SkyLight, system reposition,
    /// or a stray drag) may have shifted it.
    private func reassertHostedFrame(reason: String) {
        guard let win = overlayWindow, let frames = hostState.frames else { return }
        if win.frame.isClose(to: frames.expanded) { return }
        isResettingHostedFrame = true
        win.setFrame(frames.expanded, display: true)
        isResettingHostedFrame = false
        logNotchDiagnostics("reassert hosted frame: \(reason)", requestedFrame: frames.expanded, actualFrame: win.frame)
    }

    private func switchToDetached() {
        guard let win = detachedWindow else { return }
        removeMouseMoveMonitors()
        cancelCollapseTimer()
        removeMouseDownMonitor()
        applyDetachedStyle()
        win.isMovableByWindowBackground = true
        win.ignoresMouseEvents = NotchMouseEventPolicy.shouldIgnoreWindowMouseEvents(mode: .detached)

        // Detach target: if we currently see an expanded body, hand the
        // detached window the body's actual screen rect (plus any drag
        // offset the user already applied). Otherwise fall back to the
        // saved frame, then to a default below the notch.
        let target = detachedTargetFrame()
        win.setFrame(target, display: true)
        win.orderFrontRegardless()
        overlayWindow?.orderOut(nil)
        savedDetachedFrame = target
        hostState.expansionProgress = 1
        logNotchDiagnostics("switch detached", requestedFrame: target, actualFrame: win.frame)
        saveState()
    }

    private func detachedTargetFrame() -> CGRect {
        guard let overlay = overlayWindow, let frames = hostState.frames else {
            return savedDetachedFrame ?? CGRect(x: 200, y: 200, width: 300, height: 60)
        }

        // Mid-drag detach: align the new detached frame with the body's
        // current screen position so the user's cursor stays on the panel.
        // We do NOT persist this size — it's transient. Saved frame is
        // updated only when the detached drag ends.
        if isDragging,
           let geometry = hostState.geometry,
           hostState.isExpanded {
            let layout = NotchGeometryCalculator.hostedSurfaceLayout(
                screenFrame: hostState.screenFrame,
                geometry: geometry,
                expansionProgress: 1
            )
            let bodySize = CGSize(
                width: max(PanelResizeCalculator.minimumSize.width, layout.body.width),
                height: max(PanelResizeCalculator.minimumSize.height, layout.body.height)
            )
            return CGRect(
                x: overlay.frame.minX + layout.body.minX,
                y: overlay.frame.minY + layout.body.minY,
                width: bodySize.width,
                height: bodySize.height
            )
        }

        if let saved = savedDetachedFrame {
            return saved
        }
        let offset = frames.collapsed.height + 40
        return NSRect(
            x: frames.collapsed.midX - 150,
            y: frames.collapsed.minY - offset,
            width: 300,
            height: 60
        )
    }

    private func snapToCollapsed() {
        guard let win = detachedWindow, let frames = hostState.frames else { return }
        transitionGate.advance()
        savedDetachedFrame = win.frame
        // Surface frame is always the expanded rect; collapse is visual.
        overlayWindow?.setFrame(frames.expanded, display: false)
        hostState.mode = .collapsed
        hostState.expansionProgress = 0
        prepareOverlayForDisplay(label: "snap to collapsed")
        overlayWindow?.isMovableByWindowBackground = false
        overlayWindow?.ignoresMouseEvents = NotchMouseEventPolicy.shouldIgnoreWindowMouseEvents(mode: .collapsed)
        win.orderOut(nil)
        installMouseMoveMonitors()
        saveState()
    }

    // MARK: - NSWindowDelegate

    func windowDidMove(_ notification: Notification) {
        let movedWindow = notification.object as? NSWindow
        let movedWindowNumber = movedWindow?.windowNumber

        if hostState.isHosted, movedWindowNumber == overlayWindow?.windowNumber {
            guard !isResettingHostedFrame else { return }

            if isDragging, hostState.isExpanded {
                // User is dragging the expanded panel. The moment we
                // detect non-trivial displacement, detach so the rest of
                // the drag is owned by the detached window (which has
                // `isMovableByWindowBackground = true` and tracks the
                // cursor natively). This minimises the time the
                // transparent hosted surface is visibly "floating".
                if let frames = hostState.frames,
                   let win = overlayWindow,
                   shouldDetachDuringDrag(currentFrame: win.frame, canonical: frames.expanded) {
                    transitionTo(.detached)
                }
                return
            }

            // No drag in progress — anything that shifts the frame
            // (Spaces, SkyLight, styleMask reflow) is bounced back.
            reassertHostedFrame(reason: "windowDidMove")
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

    private static let dragDetachDistance: CGFloat = 8

    private func shouldDetachDuringDrag(currentFrame: CGRect, canonical: CGRect) -> Bool {
        let dx = abs(currentFrame.midX - canonical.midX)
        let dy = abs(currentFrame.midY - canonical.midY)
        return max(dx, dy) >= Self.dragDetachDistance
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

    // MARK: - Mouse-Up Detection

    private func installMouseUpMonitorIfNeeded() {
        guard mouseUpMonitor == nil else { return }

        mouseUpMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseUp) { [weak self] event in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.removeMouseUpMonitor()
                let wasDragging = self.isDragging
                self.isDragging = false
                if self.hostState.isHosted {
                    // Drag finished without crossing the detach distance —
                    // any small offset gets snapped back to the canonical
                    // frame.
                    self.reassertHostedFrame(reason: "hosted drag end")
                } else if wasDragging || self.hostState.isDetached {
                    self.evaluateSnap()
                }
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

    // MARK: - Mouse-Down Detection (track drag state)

    private func installMouseDownMonitorIfNeeded() {
        guard mouseDownMonitor == nil else { return }

        mouseDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard event.windowNumber == self.overlayWindow?.windowNumber else { return }
                self.isDragging = true
                self.installMouseUpMonitorIfNeeded()
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
            // Surface frame is always expanded; visual state is driven by progress.
            prepareOverlayForDisplay(label: "screen change hosted")
            win.isMovableByWindowBackground = hostState.isExpanded
            win.ignoresMouseEvents = NotchMouseEventPolicy.shouldIgnoreWindowMouseEvents(mode: hostState.mode)
            logNotchDiagnostics(
                "screen change hosted requested",
                requestedFrame: frames.expanded,
                screen: screen,
                geometry: geo
            )
            win.setFrame(frames.expanded, display: true)
            installMouseMoveMonitors()
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
        // Persisting during an in-flight drag would write a transient
        // frame (e.g. the body-sized mid-drag detached frame) and the
        // user would see that on next launch. Defer until mouseUp.
        guard !isDragging else { return }

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

        let savedMode = UserDefaults.standard.string(forKey: Self.modeKey) ?? "detached"
        var shouldRestoreHosted = savedMode == "hosted"
        var didDiscardStaleDetachedFrame = false
        print(
            """
            [NotchDiagnostics] restore state start
              savedMode: \(savedMode)
              frames.expanded: \(frames.expanded)
              frames.collapsed: \(frames.collapsed)
              frames.snapZone: \(frames.snapZone)
            """
        )

        // Restore detached frame if available — but discard if it looks
        // like leftover hosted geometry (frame sitting inside the snap
        // zone or near the hosted surface). A previous bug could persist
        // such a frame mid-drag.
        if let dict = UserDefaults.standard.dictionary(forKey: Self.detachedFrameKey) as? [String: CGFloat],
           let x = dict["x"], let y = dict["y"],
           let w = dict["w"], let h = dict["h"] {
            let candidate = NSRect(x: x, y: y, width: w, height: h)
            let shouldDiscard = NotchGeometryCalculator.shouldDiscardSavedDetachedFrame(
                candidate,
                screenFrame: screen.frame,
                frames: frames
            )
            print(
                """
                [NotchDiagnostics] restore detached frame candidate
                  frame: \(candidate)
                  shouldDiscard: \(shouldDiscard)
                """
            )
            if shouldDiscard {
                didDiscardStaleDetachedFrame = true
                shouldRestoreHosted = true
                savedDetachedFrame = nil
                UserDefaults.standard.removeObject(forKey: Self.detachedFrameKey)
            } else {
                savedDetachedFrame = candidate
            }
        }

        if shouldRestoreHosted {
            detachedWindow?.orderOut(nil)
            hostState.mode = .collapsed
            setFrameWithDiagnostics(
                frames.expanded,
                display: true,
                label: "restore hosted surface",
                screen: screen,
                geometry: geo
            )
            hostState.expansionProgress = 0
            applyHostedStyle()
            overlayWindow?.isMovableByWindowBackground = false
            overlayWindow?.ignoresMouseEvents = NotchMouseEventPolicy.shouldIgnoreWindowMouseEvents(mode: .collapsed)
            prepareOverlayForDisplay(label: "restore hosted")
            installMouseMoveMonitors()
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

        print(
            """
            [NotchDiagnostics] restore state complete
              mode: \(hostState.mode)
              expansionProgress: \(hostState.expansionProgress)
              didDiscardStaleDetachedFrame: \(didDiscardStaleDetachedFrame)
              detachedVisible: \(detachedWindow?.isVisible ?? false)
              overlayVisible: \(overlayWindow?.isVisible ?? false)
            """
        )

        // Restore saved free frame for snap-back
        if let dict = UserDefaults.standard.dictionary(forKey: Self.savedFreeFrameKey) as? [String: CGFloat],
           let x = dict["x"], let y = dict["y"],
           let w = dict["w"], let h = dict["h"] {
            savedDetachedFrame = NSRect(x: x, y: y, width: w, height: h)
        }

        // Hover expansion starts from actual mouse movement after restore.
    }
}

// MARK: - Tracking Area Container

/// NSView subclass that forwards mouse events from the body panel.
///
/// In hosted mode the overlay window's frame matches the expanded surface
/// (≈560×142). To avoid the large transparent area swallowing clicks meant
/// for the menu bar / desktop, `hitTest` rejects points that are not inside
/// the currently-visible content rectangles.
final class NotchTrackingContainerView: NSView {
    weak var manager: NotchHostPanelManager?

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let manager else { return super.hitTest(point) }
        guard let hitMask = manager.hostedHitMask(in: bounds) else {
            return super.hitTest(point)
        }
        return hitMask.contains(point) ? super.hitTest(point) : nil
    }
}

private extension CGRect {
    func isClose(to other: CGRect, tolerance: CGFloat = 0.5) -> Bool {
        abs(minX - other.minX) <= tolerance &&
            abs(minY - other.minY) <= tolerance &&
            abs(width - other.width) <= tolerance &&
            abs(height - other.height) <= tolerance
    }
}
