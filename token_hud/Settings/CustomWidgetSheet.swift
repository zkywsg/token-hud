import SwiftUI

struct CustomWidgetSheet: View {
    let store: WidgetStore
    @State private var selectedOptionID: String?
    @State private var serviceFilter = "all"
    @State private var searchText = ""
    @State private var style: WidgetStyle = .bar
    @Environment(\.dismiss) var dismiss

    private struct Option: Identifiable, Equatable {
        let service: String
        let metric: WidgetMetric

        var id: String { "\(service)-\(metric.rawValue)" }
    }

    private var options: [Option] {
        widgetCapabilities.flatMap { capability in
            capability.metrics.map { Option(service: capability.service, metric: $0) }
        }
    }

    private var serviceOptions: [String] {
        widgetCapabilities.map(\.service)
    }

    private var filteredOptions: [Option] {
        options.filter { option in
            let matchesService = serviceFilter == "all" || option.service == serviceFilter
            let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let matchesSearch = query.isEmpty ||
                serviceDisplayName(option.service).lowercased().contains(query) ||
                option.metric.displayName.lowercased().contains(query) ||
                metricTitle(WidgetConfig(service: option.service, metric: option.metric, style: style)).lowercased().contains(query)
            return matchesService && matchesSearch
        }
    }

    private var selectedOption: Option? {
        guard let selectedOptionID else { return filteredOptions.first ?? options.first }
        return options.first { $0.id == selectedOptionID }
    }

    private var availableStyles: [WidgetStyle] {
        guard let option = selectedOption else { return [.bar, .text] }
        switch option.metric {
        case .remainingTime, .tokensRemaining, .usagePercent, .creditsUsed, .dailyTokens, .monthlyTokens:
            return [.bar, .text]
        case .rateLimitStatus, .subscriptionStatus, .planName:
            return [.status, .text]
        default:
            return [.text, .bar]
        }
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                TextField("搜索平台或指标", text: $searchText)
                    .textFieldStyle(.roundedBorder)

                Picker("平台", selection: $serviceFilter) {
                    Text("全部平台").tag("all")
                    ForEach(serviceOptions, id: \.self) { service in
                        Text(serviceDisplayName(service)).tag(service)
                    }
                }
                .pickerStyle(.segmented)

                List(filteredOptions, selection: $selectedOptionID) { option in
                    HStack(spacing: 10) {
                        Image(systemName: option.metric.icon)
                            .foregroundStyle(.tint)
                            .frame(width: 18)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(metricTitle(WidgetConfig(service: option.service, metric: option.metric, style: style)))
                                .font(.system(size: 12, weight: .medium))
                            Text(serviceDisplayName(option.service))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if option.id == selectedOption?.id {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.tint)
                        }
                    }
                    .tag(option.id)
                }
                .frame(minHeight: 220)

                Picker("样式", selection: $style) {
                    ForEach(availableStyles, id: \.self) {
                        Text($0.displayName).tag($0)
                    }
                }
                .pickerStyle(.segmented)
            }
            .padding()
            .navigationTitle("自定义组件")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("添加") {
                        guard let selectedOption else { return }
                        store.widgets.append(WidgetConfig(
                            service: selectedOption.service,
                            metric: selectedOption.metric,
                            style: style
                        ))
                        dismiss()
                    }
                    .disabled(selectedOption == nil)
                }
            }
            .onAppear {
                if selectedOptionID == nil {
                    selectedOptionID = options.first?.id
                }
            }
            .onChange(of: serviceFilter) { _, _ in
                if let selectedOptionID,
                   !filteredOptions.contains(where: { $0.id == selectedOptionID }) {
                    self.selectedOptionID = filteredOptions.first?.id
                }
            }
            .onChange(of: searchText) { _, _ in
                if let selectedOptionID,
                   !filteredOptions.contains(where: { $0.id == selectedOptionID }) {
                    self.selectedOptionID = filteredOptions.first?.id
                }
            }
            .onChange(of: selectedOption?.id) { _, _ in
                if !availableStyles.contains(style) {
                    style = availableStyles.first ?? .text
                }
            }
        }
        .frame(width: 520, height: 420)
    }
}
