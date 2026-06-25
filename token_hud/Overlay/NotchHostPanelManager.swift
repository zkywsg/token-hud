import AppKit
import CoreGraphics
import SwiftUI

@MainActor
final class NotchHostPanelManager: NSObject, NSWindowDelegate {

    private var detachedWindow: NSPanel?
    private var overlayWindow: NSPanel?
    private let stateWatcher: StateWatcher
    private let widgetStore: WidgetStore
    private let codexFetcher: CodexFetcher
    private let apiPlatformFetcher: APIPlatformFetcher
    let hostState = NotchHostState()

    private var globalMouseMonitor: Any?
    private var localMouseMonitor: Any?
    private var isAnimating = false
    private var collapseTimer: DispatchWorkItem?
    private var mouseUpMonitor: Any?
    private var mouseDownMonitor: Any?
    private var hostedDragMonitor: Any?
    private var isDragging = false
    private var hasDetachedHostedDrag = false
    private var hostedDragStartLocation = CGPoint.zero
    private var hostedDragStartFrame = CGRect.zero
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
    private static let hostedTransitionAnimation = Animation.spring(response: 0.32, dampingFraction: 0.82)

    init(
        stateWatcher: StateWatcher,
        widgetStore: WidgetStore,
        codexFetcher: CodexFetcher,
        apiPlatformFetcher: APIPlatformFetcher
    ) {
        self.stateWatcher = stateWatcher
        self.widgetStore = widgetStore
        self.codexFetcher = codexFetcher
        self.apiPlatformFetcher = apiPlatformFetcher
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
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(hostedLayoutInputsChanged),
            name: UserDefaults.didChangeNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(hostedLayoutInputsChanged),
            name: WidgetStore.widgetsDidChangeNotification,
            object: widgetStore
        )
    }

    func teardown() {
        NotificationCenter.default.removeObserver(self)
        applyLifecycleCleanup(for: .teardown)
        saveState()
        detachedWindow?.close()
        overlayWindow?.close()
    }

    func toggle() {
        if isVisible {
            saveState()
            detachedWindow?.orderOut(nil)
            overlayWindow?.orderOut(nil)
            applyLifecycleCleanup(for: .hide)
        } else {
            NSApp.activate(ignoringOtherApps: true)
            if hostState.isDetached {
                detachedWindow?.orderFrontRegardless()
            } else {
                enterHostedCollapsed(label: "toggle hosted", display: false, persistState: false)
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
        panel.isMovableByWindowBackground = NotchWindowMovementPolicy.isMovableByWindowBackground(
            mode: role == .detached ? .detached : .collapsed
        )
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
                .environment(codexFetcher)
                .environment(apiPlatformFetcher)
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
        NotchGeometryCalculator.notchFrames(
            screenFrame: screen.frame,
            geometry: geometry,
            expandedBodyHeight: expandedLayoutMetrics(for: screen, geometry: geometry).bodyHeight
        )
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
        let expandedLayoutMetrics = expandedLayoutMetrics(for: screen, geometry: geo)
        hostState.geometry = geo
        hostState.frames = frames
        hostState.screenFrame = screen.frame
        hostState.gapWidth = geo.hasNotch ? geo.notchGapWidth : 0
        hostState.expandedBodyHeight = expandedLayoutMetrics.bodyHeight
        hostState.expandedLayoutMode = expandedLayoutMode
        hostState.expandedAllowsVerticalScrolling = expandedLayoutMetrics.allowsVerticalScrolling
        hostState.expandedContentScale = expandedLayoutMetrics.contentScale
    }

    private var expandedLayoutMode: NotchExpandedLayoutMode {
        NotchExpandedLayoutMode(
            rawStorageValue: UserDefaults.standard.string(forKey: Self.expandedLayoutModeKey) ?? ""
        )
    }

    private func expandedLayoutMetrics(for screen: NSScreen, geometry: NotchGeometry) -> NotchExpandedLayoutMetrics {
        let serviceCount = Set(widgetStore.widgets.map(\.service)).count
        return NotchExpandedLayoutPolicy.layout(
            mode: expandedLayoutMode,
            widgetCount: widgetStore.widgets.count,
            serviceCount: serviceCount,
            screenHeight: screen.frame.height,
            menuBarHeight: geometry.menuBarHeight
        )
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
            expansionProgress: hostState.expansionProgress,
            expandedBodyHeight: hostState.expandedBodyHeight
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

    private func applyLifecycleCleanup(for event: NotchPanelLifecycleEvent) {
        let cleanup = NotchPanelLifecyclePolicy.cleanup(for: event)
        if cleanup.cancelsCollapseTimer {
            cancelCollapseTimer()
        }
        if cleanup.removesMouseMoveMonitors {
            removeMouseMoveMonitors()
        }
        if cleanup.removesMouseDownMonitor {
            removeMouseDownMonitor()
        }
        if cleanup.removesMouseUpMonitor {
            removeMouseUpMonitor()
        }
        if event == .hide || event == .teardown {
            removeHostedDragMonitor()
        }
        if cleanup.resetsDraggingState {
            isDragging = false
            hasDetachedHostedDrag = false
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

    private func scheduleCollapse(after delay: TimeInterval = 0.25, onlyIfMouseOutside: Bool = false) {
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
            expansionProgress: hostState.expansionProgress,
            expandedBodyHeight: hostState.expandedBodyHeight
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
        isAnimating = true

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
        case (let sourceMode, .detached):
            switchToDetached(from: sourceMode)
        }
        isAnimating = false
    }

    private func animateToCollapsed() {
        guard let win = overlayWindow else { return }
        cancelCollapseTimer()
        refreshHostedGeometryAndFrame(display: false, reason: "collapse geometry refresh")
        detachedWindow?.orderOut(nil)
        reassertHostedFrame(reason: "animate collapsed", force: true)
        prepareOverlayForDisplay(label: "animate collapsed")
        win.isMovableByWindowBackground = NotchWindowMovementPolicy.isMovableByWindowBackground(mode: .collapsed)
        win.ignoresMouseEvents = NotchMouseEventPolicy.shouldIgnoreWindowMouseEvents(mode: .collapsed)
        removeMouseDownMonitor()

        withAnimation(Self.hostedTransitionAnimation) {
            hostState.expansionProgress = 0
        }
        installMouseMoveMonitors()
        saveState()
    }

    private func enterHostedCollapsed(
        label: String,
        display: Bool,
        persistState: Bool
    ) {
        cancelCollapseTimer()
        removeMouseDownMonitor()
        removeMouseUpMonitor()
        removeHostedDragMonitor()
        isDragging = false
        hasDetachedHostedDrag = false

        guard let screen = preferredScreen(preferredWindow: overlayWindow ?? detachedWindow) else { return }
        refreshGeometry(for: screen)
        guard let frames = hostState.frames, let win = overlayWindow else { return }

        detachedWindow?.orderOut(nil)
        applyHostedStyle()
        hostState.mode = .collapsed
        hostState.expansionProgress = 0
        isResettingHostedFrame = true
        win.setFrame(frames.expanded, display: display)
        isResettingHostedFrame = false
        prepareOverlayForDisplay(label: label)
        win.isMovableByWindowBackground = NotchWindowMovementPolicy.isMovableByWindowBackground(mode: .collapsed)
        win.ignoresMouseEvents = NotchMouseEventPolicy.shouldIgnoreWindowMouseEvents(mode: .collapsed)
        installMouseMoveMonitors()
        if persistState {
            saveState()
        }
    }

    private func animateToExpanded(collapseAfterFeedback: Bool = false) {
        guard let win = overlayWindow else { return }
        cancelCollapseTimer()
        refreshHostedGeometryAndFrame(display: true, reason: "expand geometry refresh")
        detachedWindow?.orderOut(nil)
        reassertHostedFrame(reason: "animate expanded", force: true)
        prepareOverlayForDisplay(label: "animate expanded")
        // Hosted surfaces stay pinned to the canonical frame. Dragging the
        // expanded body is handled explicitly and switches to detached.
        win.isMovableByWindowBackground = NotchWindowMovementPolicy.isMovableByWindowBackground(mode: .expanded)
        win.ignoresMouseEvents = NotchMouseEventPolicy.shouldIgnoreWindowMouseEvents(mode: .expanded)
        installMouseDownMonitorIfNeeded()

        withAnimation(Self.hostedTransitionAnimation) {
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
    private func reassertHostedFrame(reason: String, force: Bool = false) {
        guard let win = overlayWindow, let frames = hostState.frames else { return }
        if !force && win.frame.isClose(to: frames.expanded) { return }
        isResettingHostedFrame = true
        win.setFrame(frames.expanded, display: true)
        isResettingHostedFrame = false
        logNotchDiagnostics("reassert hosted frame: \(reason)", requestedFrame: frames.expanded, actualFrame: win.frame)
    }

    private func switchToDetached(from sourceMode: NotchHostMode) {
        guard let win = detachedWindow else { return }
        applyLifecycleCleanup(for: .switchToDetached)
        applyDetachedStyle()
        win.isMovableByWindowBackground = NotchWindowMovementPolicy.isMovableByWindowBackground(mode: .detached)
        win.ignoresMouseEvents = NotchMouseEventPolicy.shouldIgnoreWindowMouseEvents(mode: .detached)

        // Detach target: if we currently see an expanded body, hand the
        // detached window the body's actual screen rect (plus any drag
        // offset the user already applied). Otherwise fall back to the
        // saved frame, then to a default below the notch.
        let target = detachedTargetFrame(sourceMode: sourceMode)
        win.setFrame(target, display: true)
        win.orderFrontRegardless()
        overlayWindow?.orderOut(nil)
        savedDetachedFrame = target
        hostState.expansionProgress = 1
        logNotchDiagnostics("switch detached", requestedFrame: target, actualFrame: win.frame)
        saveState()
    }

    private func detachedTargetFrame(sourceMode: NotchHostMode) -> CGRect {
        guard let overlay = overlayWindow, let frames = hostState.frames else {
            return savedDetachedFrame ?? CGRect(x: 200, y: 200, width: 300, height: 60)
        }

        // Mid-drag detach: align the new detached frame with the body's
        // current screen position so the user's cursor stays on the panel.
        // We do NOT persist this size — it's transient. Saved frame is
        // updated only when the detached drag ends.
        if isDragging,
           sourceMode == .expanded,
           let target = hostedBodyDetachedFrame(surfaceFrame: overlay.frame) {
            return target
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

    private func hostedBodyDetachedFrame(surfaceFrame: CGRect) -> CGRect? {
        guard let geometry = hostState.geometry else { return nil }
        return NotchGeometryCalculator.hostedBodyDetachedFrame(
            surfaceFrame: surfaceFrame,
            screenFrame: hostState.screenFrame,
            geometry: geometry,
            expandedBodyHeight: hostState.expandedBodyHeight,
            minimumSize: PanelResizeCalculator.minimumSize
        )
    }

    private func snapToCollapsed() {
        guard let win = detachedWindow, let frames = hostState.frames else { return }
        transitionGate.advance()
        savedDetachedFrame = win.frame
        // Surface frame is always the expanded rect; collapse is visual.
        overlayWindow?.setFrame(frames.expanded, display: false)
        hostState.mode = .collapsed
        prepareOverlayForDisplay(label: "snap to collapsed")
        withAnimation(Self.hostedTransitionAnimation) {
            hostState.expansionProgress = 0
        }
        overlayWindow?.isMovableByWindowBackground = NotchWindowMovementPolicy.isMovableByWindowBackground(mode: .collapsed)
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
            switch NotchHostedResizePolicy.action(
                mode: hostState.mode,
                isResettingHostedFrame: isResettingHostedFrame,
                isDragging: isDragging
            ) {
            case .ignore:
                return
            case .reassertHostedFrame:
                reassertHostedFrame(reason: "windowDidResize", force: true)
            case .detach:
                transitionTo(.detached)
            }
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
                self.removeHostedDragMonitor()
                let wasDragging = self.isDragging
                let detachedFromHostedDrag = self.hasDetachedHostedDrag
                self.isDragging = false
                self.hasDetachedHostedDrag = false
                if self.hostState.isHosted {
                    // Drag finished without crossing the detach distance —
                    // any small offset gets snapped back to the canonical
                    // frame.
                    self.reassertHostedFrame(reason: "hosted drag end", force: true)
                } else if wasDragging || detachedFromHostedDrag || self.hostState.isDetached {
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
                guard self.hostState.isExpanded else { return }
                guard self.isPointInExpandedBody(event.locationInWindow) else { return }
                guard let bodyFrame = self.hostedBodyDetachedFrame(surfaceFrame: self.overlayWindow?.frame ?? .zero) else {
                    return
                }
                self.isDragging = true
                self.hasDetachedHostedDrag = false
                self.hostedDragStartLocation = self.overlayWindow?.convertPoint(toScreen: event.locationInWindow)
                    ?? NSEvent.mouseLocation
                self.hostedDragStartFrame = bodyFrame
                self.installHostedDragMonitorIfNeeded()
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

    private func installHostedDragMonitorIfNeeded() {
        guard hostedDragMonitor == nil else { return }

        hostedDragMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDragged) { [weak self] event in
            Task { @MainActor [weak self] in
                self?.handleHostedDrag(event)
            }
            return event
        }
    }

    private func removeHostedDragMonitor() {
        if let monitor = hostedDragMonitor {
            NSEvent.removeMonitor(monitor)
            hostedDragMonitor = nil
        }
    }

    private func handleHostedDrag(_ event: NSEvent) {
        guard isDragging else { return }

        let currentLocation = NSEvent.mouseLocation
        let delta = CGSize(
            width: currentLocation.x - hostedDragStartLocation.x,
            height: currentLocation.y - hostedDragStartLocation.y
        )
        let shouldDetach = hasDetachedHostedDrag ||
            max(abs(delta.width), abs(delta.height)) >= Self.dragDetachDistance
        guard shouldDetach else { return }

        if !hasDetachedHostedDrag {
            transitionTo(.detached)
            hasDetachedHostedDrag = true
        }

        guard hostState.isDetached, let win = detachedWindow else { return }
        let frame = hostedDragStartFrame.offsetBy(dx: delta.width, dy: delta.height)
        win.setFrame(frame, display: true)
        savedDetachedFrame = frame
    }

    private func isPointInExpandedBody(_ point: CGPoint) -> Bool {
        guard let geometry = hostState.geometry, hostState.isExpanded else { return false }
        let layout = NotchGeometryCalculator.hostedSurfaceLayout(
            screenFrame: hostState.screenFrame,
            geometry: geometry,
            expansionProgress: 1,
            expandedBodyHeight: hostState.expandedBodyHeight
        )
        return layout.body.contains(point)
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
            win.isMovableByWindowBackground = NotchWindowMovementPolicy.isMovableByWindowBackground(mode: hostState.mode)
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

    @objc private func hostedLayoutInputsChanged() {
        refreshHostedGeometryAndFrame(display: true, reason: "layout inputs changed")
    }

    private func refreshHostedGeometryAndFrame(display: Bool, reason: String) {
        guard let screen = preferredScreen(preferredWindow: overlayWindow ?? detachedWindow) else { return }
        refreshGeometry(for: screen)
        guard hostState.isHosted, let frames = hostState.frames, let win = overlayWindow else { return }
        isResettingHostedFrame = true
        win.setFrame(frames.expanded, display: display)
        isResettingHostedFrame = false
        logNotchDiagnostics(reason, requestedFrame: frames.expanded, actualFrame: win.frame)
    }

    // MARK: - State Persistence

    private static let modeKey = "notchHostMode"
    private static let detachedFrameKey = "notchHostDetachedFrame"
    private static let savedFreeFrameKey = "notchHostSavedFreeFrame"
    private static let expandedLayoutModeKey = "notchExpandedLayoutMode"

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

        let savedMode = UserDefaults.standard.string(forKey: Self.modeKey)
        var didDiscardStaleDetachedFrame = false
        print(
            """
            [NotchDiagnostics] restore state start
              savedMode: \(savedMode ?? "nil")
              frames.expanded: \(frames.expanded)
              frames.collapsed: \(frames.collapsed)
              frames.snapZone: \(frames.snapZone)
            """
        )

        // Restore detached frame if available — but discard if it looks
        // like leftover hosted geometry (frame sitting inside the snap
        // zone or near the hosted surface). A previous bug could persist
        // such a frame mid-drag.
        var savedDetachedCandidate: CGRect?
        if let dict = UserDefaults.standard.dictionary(forKey: Self.detachedFrameKey) as? [String: CGFloat],
           let x = dict["x"], let y = dict["y"],
           let w = dict["w"], let h = dict["h"] {
            let candidate = NSRect(x: x, y: y, width: w, height: h)
            savedDetachedCandidate = candidate
            let restoreMode = NotchRestorePolicy.restoreMode(
                savedMode: savedMode,
                savedDetachedFrame: candidate,
                screenFrame: screen.frame,
                frames: frames
            )
            let shouldDiscard = restoreMode == .hostedCollapsed && savedMode == "detached"
            print(
                """
                [NotchDiagnostics] restore detached frame candidate
                  frame: \(candidate)
                  shouldDiscard: \(shouldDiscard)
                """
            )
            if shouldDiscard {
                didDiscardStaleDetachedFrame = true
                savedDetachedFrame = nil
                UserDefaults.standard.removeObject(forKey: Self.detachedFrameKey)
            } else {
                savedDetachedFrame = candidate
            }
        }

        let restoreMode = NotchRestorePolicy.restoreMode(
            savedMode: savedMode,
            savedDetachedFrame: savedDetachedCandidate,
            screenFrame: screen.frame,
            frames: frames
        )

        switch restoreMode {
        case .hostedCollapsed:
            enterHostedCollapsed(label: "restore hosted", display: false, persistState: false)
        case .detached(let saved):
            savedDetachedFrame = saved
            hostState.mode = .detached
            hostState.expansionProgress = 1
            setFrameWithDiagnostics(saved, display: true, label: "restore detached saved", screen: screen, geometry: geo)
            applyDetachedStyle()
            detachedWindow?.isMovableByWindowBackground = NotchWindowMovementPolicy.isMovableByWindowBackground(mode: .detached)
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
