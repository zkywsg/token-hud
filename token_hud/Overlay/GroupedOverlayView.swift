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
        OverlayServiceCardGrid {
            ForEach(orderedServices, id: \.self) { serviceID in
                serviceCard(serviceID: serviceID)
            }
        }
    }

    @ViewBuilder
    private func serviceCard(serviceID: String) -> some View {
        let serviceWidgets = widgets.filter { $0.service == serviceID }
        let label = state?.services[serviceID]?.label ?? serviceID

        if !serviceWidgets.isEmpty {
            OverlayModelCard(serviceLabel: label, componentCount: serviceWidgets.count) {
                OverlayServiceRefreshButton(serviceID: serviceID)
            } content: {
                OverlayMetricGrid(widgets: serviceWidgets, state: state)
            }
        }
    }
}

struct OverlayServiceRefreshButton: View {
    let serviceID: String

    @Environment(StateWatcher.self) private var stateWatcher
    @Environment(CodexFetcher.self) private var codexFetcher
    @Environment(APIPlatformFetcher.self) private var apiPlatformFetcher
    @Environment(\.panelAdaptiveScale) private var scale
    @State private var isRefreshing = false

    private var isSupported: Bool {
        switch serviceID {
        case "codex", "deepseek", "minimax", "mimo":
            return true
        default:
            return false
        }
    }

    var body: some View {
        if isSupported {
            Button {
                refresh()
            } label: {
                Group {
                    if isRefreshing {
                        ProgressView()
                            .controlSize(.mini)
                            .scaleEffect(max(0.65, 0.78 * scale))
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 8.5 * scale, weight: .semibold))
                    }
                }
                .frame(width: 18 * scale, height: 18 * scale)
                .foregroundStyle(.white.opacity(isRefreshing ? 0.45 : 0.50))
                .background(
                    Circle()
                        .fill(Color.white.opacity(isRefreshing ? 0.055 : 0.035))
                )
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(isRefreshing ? 0.12 : 0.075), lineWidth: max(0.5, 0.7 * scale))
                )
                .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(isRefreshing)
            .help("刷新 \(serviceID)")
        }
    }

    private func refresh() {
        guard !isRefreshing else { return }
        isRefreshing = true
        Task { @MainActor in
            defer {
                stateWatcher.readNow()
                isRefreshing = false
            }

            if serviceID == "codex" {
                await codexFetcher.fetch(allowUserInteraction: false)
            } else {
                _ = await apiPlatformFetcher.fetchSingle(
                    platform: serviceID,
                    allowUserInteraction: false
                )
            }
        }
    }
}
