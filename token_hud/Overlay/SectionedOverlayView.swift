import SwiftUI

struct SectionedOverlayView: View {
    let widgets: [WidgetConfig]
    let state: StateFile?

    @Environment(\.panelAdaptiveScale) private var scale
    @State private var selectedService: String?

    private var orderedServices: [String] {
        var seen = Set<String>()
        return widgets.filter { seen.insert($0.service).inserted }.map(\.service)
    }

    private var activeService: String? {
        if let selectedService, orderedServices.contains(selectedService) {
            return selectedService
        }
        return orderedServices.first
    }

    private var activeWidgets: [WidgetConfig] {
        guard let activeService else { return [] }
        return widgets.filter { $0.service == activeService }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: max(8, 8 * scale)) {
            serviceTabs

            if let activeService {
                serviceContent(activeService)
            }
        }
        .onAppear(perform: normalizeSelection)
        .onChange(of: widgets) { _, _ in normalizeSelection() }
    }

    private var serviceTabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: max(6, 6 * scale)) {
                ForEach(orderedServices, id: \.self) { serviceID in
                    let isSelected = activeService == serviceID
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedService = serviceID
                        }
                    } label: {
                        Text(serviceLabel(for: serviceID))
                            .font(.system(size: 10 * scale, weight: .semibold, design: .rounded))
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .padding(.horizontal, max(8, 8 * scale))
                            .padding(.vertical, max(4, 4 * scale))
                            .foregroundColor(.white.opacity(isSelected ? 0.90 : 0.48))
                            .background(
                                Capsule()
                                    .fill(Color.white.opacity(isSelected ? 0.12 : 0.045))
                            )
                            .overlay(
                                Capsule()
                                    .stroke(Color.white.opacity(isSelected ? 0.12 : 0.06), lineWidth: 0.6)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func serviceContent(_ serviceID: String) -> some View {
        OverlayModelCard(
            serviceLabel: serviceLabel(for: serviceID),
            componentCount: activeWidgets.count,
            accessory: {
                OverlayServiceRefreshButton(serviceID: serviceID)
            },
            content: {
                OverlayMetricGrid(widgets: activeWidgets, state: state)
            }
        )
    }

    private func serviceLabel(for serviceID: String) -> String {
        state?.services[serviceID]?.label ?? serviceID
    }

    private func normalizeSelection() {
        if let selectedService, orderedServices.contains(selectedService) {
            return
        }
        selectedService = orderedServices.first
    }
}
