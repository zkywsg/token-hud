import SwiftUI

struct GroupedOverlayView: View {
    let widgets: [WidgetConfig]
    let state: StateFile?

    @Environment(\.panelAdaptiveScale) private var scale

    /// Ordered list of unique service IDs that have widgets, preserving order.
    private var orderedServices: [String] {
        var seen = Set<String>()
        return widgets.filter { seen.insert($0.service).inserted }.map(\.service)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(orderedServices.enumerated()), id: \.element) { index, serviceID in
                if index > 0 {
                    Divider()
                        .background(Color.white.opacity(0.1))
                        .frame(height: 0.5 * scale)
                }
                serviceRow(serviceID: serviceID)
            }
        }
    }

    @ViewBuilder
    private func serviceRow(serviceID: String) -> some View {
        let serviceWidgets = widgets.filter { $0.service == serviceID }
        let label = state?.services[serviceID]?.label ?? serviceID

        HStack(spacing: 8 * scale) {
            Text(label)
                .font(.system(size: 10 * scale, weight: .regular, design: .rounded))
                .foregroundColor(.white.opacity(0.4))
                .frame(width: 70 * scale, alignment: .leading)

            HStack(spacing: 6 * scale) {
                ForEach(serviceWidgets) { config in
                    WidgetRenderer(config: config, state: state)
                }
            }
        }
        .padding(.vertical, 3 * scale)
    }
}
