import AppKit
import SwiftUI

struct FloatingPanelView: View {
    @Environment(StateWatcher.self) private var watcher
    @Environment(WidgetStore.self) private var store
    @AppStorage("floatingPanelScale") private var persistedScale = 1.0
    @AppStorage("overlayMode") private var overlayMode = "compact"
    @State private var gestureStartScale: CGFloat = 1.0
    @State private var gestureScale: CGFloat = 1.0

    var body: some View {
        GeometryReader { geometry in
            let contentBehavior = calculateContentBehavior(for: geometry.size)
            let adaptiveScale = contentBehavior.adaptiveScale
            ZStack(alignment: .bottomTrailing) {
                RoundedRectangle(cornerRadius: CompactBlackTheme.cornerRadius)
                    .fill(Color.black)
                RoundedRectangle(cornerRadius: CompactBlackTheme.cornerRadius)
                    .stroke(Color.white.opacity(0.16), lineWidth: 0.8)
                    .shadow(color: .black.opacity(0.28), radius: 12, y: 6)

                scrollableOverlayContent(allowsVerticalScrolling: contentBehavior.allowsVerticalScrolling)
                    .padding(12 * adaptiveScale)
                    .frame(
                        maxWidth: .infinity,
                        maxHeight: .infinity,
                        alignment: alignment(for: FloatingPanelContentLayoutPolicy.layout().verticalPlacement)
                    )
                    .scaleEffect(
                        gestureScale,
                        anchor: unitPoint(for: FloatingPanelContentLayoutPolicy.layout().scaleAnchor)
                    )
                    .gesture(
                        MagnificationGesture()
                            .onChanged { value in
                                gestureScale = (gestureStartScale * value)
                                    .clamped(to: 0.5...3.0)
                            }
                            .onEnded { _ in
                                gestureStartScale = gestureScale
                                persistedScale = gestureScale
                            }
                    )

                PanelResizeGrip()
                    .frame(width: max(16, 20 * adaptiveScale), height: max(16, 20 * adaptiveScale))
                    .padding(max(3, 4 * adaptiveScale))
            }
            .frame(
                minWidth: PanelResizeCalculator.minimumSize.width,
                minHeight: PanelResizeCalculator.minimumSize.height
            )
            .contentShape(Rectangle())
            .environment(\.panelAdaptiveScale, adaptiveScale)
        }
        .onAppear {
            gestureScale = persistedScale
            gestureStartScale = persistedScale
        }
    }

    @ViewBuilder
    private var overlayContent: some View {
        if overlayMode == "grouped" {
            GroupedOverlayView(
                widgets: store.widgets,
                state: watcher.effectiveState
            )
        } else {
            CompactOverlayContent()
        }
    }

    @ViewBuilder
    private func scrollableOverlayContent(allowsVerticalScrolling: Bool) -> some View {
        if allowsVerticalScrolling {
            ScrollView(.vertical, showsIndicators: false) {
                overlayContent
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .scrollClipDisabled(false)
        } else {
            overlayContent
        }
    }

    private func calculateAdaptiveScale(for size: CGSize) -> CGFloat {
        calculateContentBehavior(for: size).adaptiveScale
    }

    private func calculateContentBehavior(for size: CGSize) -> FloatingPanelContentOverflowBehavior {
        let serviceCount = Set(store.widgets.map(\.service)).count
        if overlayMode == "grouped" {
            return FloatingPanelContentLayoutPolicy.groupedOverflowBehavior(
                panelHeight: size.height,
                serviceCount: serviceCount,
                widgetCount: store.widgets.count
            )
        }
        return FloatingPanelContentOverflowBehavior(
            adaptiveScale: FloatingPanelContentLayoutPolicy.adaptiveScale(
                panelHeight: size.height,
                overlayMode: overlayMode,
                serviceCount: serviceCount,
                widgetCount: store.widgets.count
            ),
            allowsVerticalScrolling: false
        )
    }

    private func alignment(for anchor: FloatingPanelContentAnchor) -> Alignment {
        switch anchor {
        case .top:
            return .top
        case .center:
            return .center
        }
    }

    private func unitPoint(for anchor: FloatingPanelContentAnchor) -> UnitPoint {
        switch anchor {
        case .top:
            return .top
        case .center:
            return .center
        }
    }
}

private struct PanelResizeGrip: NSViewRepresentable {
    func makeNSView(context: Context) -> ResizeGripView {
        ResizeGripView()
    }

    func updateNSView(_ nsView: ResizeGripView, context: Context) {}
}

private final class ResizeGripView: NSView {
    private var initialFrame = CGRect.zero
    private var initialLocation = CGPoint.zero

    override var acceptsFirstResponder: Bool { true }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        initialFrame = window.frame
        initialLocation = window.convertPoint(toScreen: event.locationInWindow)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window else { return }
        let currentLocation = window.convertPoint(toScreen: event.locationInWindow)
        let dragDelta = CGSize(
            width: currentLocation.x - initialLocation.x,
            height: currentLocation.y - initialLocation.y
        )
        let frame = PanelResizeCalculator.bottomRightFrame(
            from: initialFrame,
            dragDelta: dragDelta
        )

        window.setFrame(frame, display: true)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let color = NSColor.white.withAlphaComponent(0.22)
        color.setStroke()

        let path = NSBezierPath()
        path.lineWidth = 1.2
        for offset in stride(from: CGFloat(4), through: CGFloat(12), by: CGFloat(4)) {
            path.move(to: CGPoint(x: bounds.maxX - offset, y: bounds.minY + 3))
            path.line(to: CGPoint(x: bounds.maxX - 3, y: bounds.minY + offset))
        }
        path.stroke()
    }
}
