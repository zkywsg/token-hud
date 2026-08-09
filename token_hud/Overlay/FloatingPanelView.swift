import AppKit
import SwiftUI

struct FloatingPanelView: View {
    @Environment(StateWatcher.self) private var watcher
    @Environment(WidgetStore.self) private var store
    @AppStorage("widgetSizeScale") private var widgetSizeScale = 1.0
    @State private var gestureStartScale: CGFloat = 1.0

    var body: some View {
        GeometryReader { geometry in
            let adaptiveScale = calculateAdaptiveScale(for: geometry.size)
            ZStack(alignment: .bottomTrailing) {
                // The focus card draws its own glass + accent glow, so the panel
                // has no background of its own.
                overlayContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    // Pinching now drives the single shared content scale
                    // (`widgetSizeScale`) instead of a second panel-only zoom.
                    .gesture(
                        MagnificationGesture()
                            .onChanged { value in
                                widgetSizeScale = (gestureStartScale * value)
                                    .clamped(to: 0.6...2.0)
                            }
                            .onEnded { _ in
                                gestureStartScale = widgetSizeScale
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
        .onAppear { gestureStartScale = widgetSizeScale }
    }

    private var overlayContent: some View {
        OverlayFocusView(widgets: store.widgets, state: watcher.effectiveState)
    }

    private func calculateAdaptiveScale(for size: CGSize) -> CGFloat {
        // Detached panel content uses a fixed, readable scale; overflow
        // scrolls inside the list instead of shrinking the text.
        widgetSizeScale
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
