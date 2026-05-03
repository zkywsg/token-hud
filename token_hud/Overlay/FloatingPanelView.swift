import AppKit
import SwiftUI

struct FloatingPanelView: View {
    @Environment(StateWatcher.self) private var watcher
    @Environment(WidgetStore.self) private var store
    @AppStorage("floatingPanelScale") private var scale = 1.0
    @AppStorage("overlayMode") private var overlayMode = "compact"
    @State private var gestureStartScale: CGFloat = 1.0

    var body: some View {
        GeometryReader { geometry in
            let adaptiveScale = calculateAdaptiveScale(for: geometry.size)
            ZStack(alignment: .bottomTrailing) {
                overlayContent
                    .padding(12 * adaptiveScale)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    .scaleEffect(scale, anchor: .center)
                    .gesture(
                        MagnificationGesture()
                            .onChanged { value in
                                scale = (gestureStartScale * value)
                                    .clamped(to: 0.5...3.0)
                            }
                            .onEnded { _ in
                                gestureStartScale = scale
                            }
                    )

                PanelResizeGrip()
                    .frame(width: 20 * adaptiveScale, height: 20 * adaptiveScale)
                    .padding(4 * adaptiveScale)
            }
            .frame(
                minWidth: PanelResizeCalculator.minimumSize.width,
                minHeight: PanelResizeCalculator.minimumSize.height
            )
            .contentShape(Rectangle())
            .environment(\.panelAdaptiveScale, adaptiveScale)
        }
        .onAppear { gestureStartScale = scale }
    }

    @ViewBuilder
    private var overlayContent: some View {
        if overlayMode == "grouped" {
            GroupedOverlayView(
                widgets: store.widgets,
                state: watcher.effectiveState
            )
        } else {
            compactOverlay
        }
    }

    @ViewBuilder
    private var compactOverlay: some View {
        CompactOverlayContent()
    }

    private func calculateAdaptiveScale(for size: CGSize) -> CGFloat {
        let baseHeight: CGFloat = 60
        let idealHeight: CGFloat
        if overlayMode == "grouped" {
            let serviceCount = Set(store.widgets.map(\.service)).count
            idealHeight = max(baseHeight, CGFloat(serviceCount) * 32 + 16)
        } else {
            idealHeight = baseHeight
        }
        return (size.height / idealHeight).clamped(to: 0.5...3.0)
    }
}

private struct CompactOverlayContent: View {
    @Environment(WidgetStore.self) private var store
    @Environment(StateWatcher.self) private var watcher
    @Environment(\.panelAdaptiveScale) private var scale

    var body: some View {
        HStack(spacing: 6 * scale) {
            ForEach(store.widgets) { config in
                WidgetRenderer(config: config, state: watcher.effectiveState, showServiceLabel: true)
            }
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

        let color = NSColor.white.withAlphaComponent(0.35)
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

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
