// token_hud/Settings/WidgetListEditor.swift
import SwiftUI

struct WidgetListEditor: View {
    @EnvironmentObject var store: WidgetStore
    @State private var showAddSheet: WidgetSide? = nil

    enum WidgetSide: Identifiable {
        case left, right
        var id: String { self == .left ? "left" : "right" }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            widgetColumn(title: "Left Side",  widgets: $store.leftWidgets,  side: .left)
            Divider()
            widgetColumn(title: "Right Side", widgets: $store.rightWidgets, side: .right)
        }
        .sheet(item: $showAddSheet) { side in
            AddWidgetSheet(side: side, store: store)
        }
    }

    @ViewBuilder
    private func widgetColumn(title: String, widgets: Binding<[WidgetConfig]>, side: WidgetSide) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title).font(.headline)
                Spacer()
                Button { showAddSheet = side } label: { Image(systemName: "plus") }
            }

            List {
                ForEach(widgets) { $widget in
                    HStack {
                        Image(systemName: metricIcon(widget.metric))
                            .frame(width: 20)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(widget.service).font(.body)
                            Text("\(widget.metric.rawValue) · \(widget.style.rawValue)")
                                .font(.caption).foregroundColor(.secondary)
                        }
                        Spacer()
                    }
                }
                .onMove { from, to in widgets.wrappedValue.move(fromOffsets: from, toOffset: to) }
                .onDelete { offsets in widgets.wrappedValue.remove(atOffsets: offsets) }
            }
            .frame(minHeight: 200)
        }
        .frame(maxWidth: .infinity)
    }

    private func metricIcon(_ metric: WidgetMetric) -> String {
        switch metric {
        case .remainingTime:   return "clock"
        case .resetCountdown:  return "arrow.clockwise"
        case .tokensRemaining: return "text.bubble"
        case .balance:         return "dollarsign.circle"
        case .sessionTokens:   return "arrow.up.circle"
        case .usagePercent:    return "chart.bar"
        }
    }
}

struct AddWidgetSheet: View {
    let side: WidgetListEditor.WidgetSide
    let store: WidgetStore

    @State private var service = "claude"
    @State private var metric: WidgetMetric = .remainingTime
    @State private var style: WidgetStyle   = .ring
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            Form {
                TextField("Service ID (e.g. claude, openai)", text: $service)
                Picker("Metric", selection: $metric) {
                    ForEach(WidgetMetric.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                Picker("Style", selection: $style) {
                    ForEach(WidgetStyle.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
            }
            .navigationTitle("Add Widget")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        let cfg = WidgetConfig(service: service, metric: metric, style: style)
                        switch side {
                        case .left:  store.leftWidgets.append(cfg)
                        case .right: store.rightWidgets.append(cfg)
                        }
                        dismiss()
                    }
                }
            }
        }
        .frame(width: 320, height: 220)
    }
}
