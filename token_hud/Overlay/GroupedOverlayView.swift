import SwiftUI

struct GroupedOverlayView: View {
    let leftWidgets: [WidgetConfig]
    let rightWidgets: [WidgetConfig]
    let state: StateFile?

    /// Ordered list of unique service IDs that have widgets, preserving left-then-right order.
    private var orderedServices: [String] {
        var seen = Set<String>()
        var result: [String] = []
        for w in leftWidgets + rightWidgets {
            if seen.insert(w.service).inserted {
                result.append(w.service)
            }
        }
        return result
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(orderedServices.enumerated()), id: \.element) { index, serviceID in
                if index > 0 {
                    Divider()
                        .background(Color.white.opacity(0.1))
                        .frame(height: 0.5)
                }
                serviceRow(serviceID: serviceID)
            }
        }
    }

    @ViewBuilder
    private func serviceRow(serviceID: String) -> some View {
        let serviceLeft = leftWidgets.filter { $0.service == serviceID }
        let serviceRight = rightWidgets.filter { $0.service == serviceID }
        let label = state?.services[serviceID]?.label ?? serviceID

        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 10, weight: .regular, design: .rounded))
                .foregroundColor(.white.opacity(0.4))
                .frame(width: 70, alignment: .leading)

            HStack(spacing: 6) {
                ForEach(serviceLeft) { config in
                    WidgetRenderer(config: config, state: state)
                }
                if !serviceLeft.isEmpty && !serviceRight.isEmpty {
                    Divider().frame(height: 16)
                }
                ForEach(serviceRight) { config in
                    WidgetRenderer(config: config, state: state)
                }
            }
        }
        .padding(.vertical, 3)
    }
}
