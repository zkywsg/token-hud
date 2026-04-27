import SwiftUI
import UniformTypeIdentifiers

// MARK: - Preset Definition

private struct WidgetPreset: Identifiable, Equatable {
    let id = UUID()
    let config: WidgetConfig

    var serviceDisplayName: String {
        switch config.service {
        case "claude":    return "Claude"
        case "openai":    return "OpenAI"
        case "codex":     return "Codex"
        case "gemini":    return "Gemini"
        case "deepseek":  return "DeepSeek"
        case "anthropic": return "Anthropic"
        case "minimax":   return "MiniMax"
        case "mimo":      return "MiMo"
        default:          return config.service
        }
    }

    var styleIcon: String {
        switch config.style {
        case .ring:             return "◯"
        case .bar:              return "▬"
        case .text:             return "T"
        case .aggregate:        return "Σ"
        case .multi:            return "⊞"
        case .countdown:        return "◎"
        case .status:           return "●"
        case .modelBreakdown:   return "⊞"
        }
    }
}

private let presets: [WidgetPreset] = [
    WidgetPreset(config: WidgetConfig(service: "claude",    metric: .remainingTime,   style: .ring)),
    WidgetPreset(config: WidgetConfig(service: "claude",    metric: .resetCountdown,  style: .text)),
    WidgetPreset(config: WidgetConfig(service: "claude",    metric: .sessionTokens,   style: .aggregate)),
    WidgetPreset(config: WidgetConfig(service: "openai",    metric: .balance,         style: .bar)),
    WidgetPreset(config: WidgetConfig(service: "openai",    metric: .costSpent,       style: .text)),
    WidgetPreset(config: WidgetConfig(service: "codex",     metric: .sessionTokens,   style: .bar)),
    WidgetPreset(config: WidgetConfig(service: "codex",     metric: .remainingTime,   style: .ring)),
    WidgetPreset(config: WidgetConfig(service: "gemini",    metric: .dailyTokens,     style: .ring)),
    WidgetPreset(config: WidgetConfig(service: "gemini",    metric: .dailyRequests,   style: .bar)),
    WidgetPreset(config: WidgetConfig(service: "deepseek",  metric: .balance,         style: .bar)),
    WidgetPreset(config: WidgetConfig(service: "deepseek",  metric: .monthlyTokens,   style: .ring)),
    WidgetPreset(config: WidgetConfig(service: "anthropic", metric: .costSpent,       style: .text)),
    WidgetPreset(config: WidgetConfig(service: "anthropic", metric: .monthlyRequests, style: .aggregate)),
    // New derived metrics & styles
    WidgetPreset(config: WidgetConfig(service: "claude",    metric: .sessionDuration, style: .countdown)),
    WidgetPreset(config: WidgetConfig(service: "claude",    metric: .tokensPerMinute, style: .text)),
    WidgetPreset(config: WidgetConfig(service: "claude",    metric: .rateLimitStatus, style: .status)),
    WidgetPreset(config: WidgetConfig(service: "claude",    metric: .sessionTokens,   style: .multi)),
    WidgetPreset(config: WidgetConfig(service: "claude",    metric: .remainingTime,   style: .countdown)),
    WidgetPreset(config: WidgetConfig(service: "openai",    metric: .costPerRequest,  style: .text)),
    WidgetPreset(config: WidgetConfig(service: "openai",    metric: .inputOutputRatio,style: .aggregate)),
    WidgetPreset(config: WidgetConfig(service: "codex",     metric: .rateLimitStatus, style: .status)),
    WidgetPreset(config: WidgetConfig(service: "gemini",    metric: .tokensPerMinute, style: .text)),
    WidgetPreset(config: WidgetConfig(service: "anthropic", metric: .sessionDuration, style: .countdown)),
    WidgetPreset(config: WidgetConfig(service: "anthropic", metric: .sessionTokens,   style: .modelBreakdown)),
    WidgetPreset(config: WidgetConfig(service: "minimax",   metric: .balance,         style: .bar)),
    WidgetPreset(config: WidgetConfig(service: "minimax",   metric: .monthlyTokens,   style: .ring)),
    WidgetPreset(config: WidgetConfig(service: "mimo",      metric: .dailyTokens,     style: .ring)),
    WidgetPreset(config: WidgetConfig(service: "mimo",      metric: .costSpent,       style: .text)),
]

// MARK: - Platform Grouped Presets

private struct PlatformPresetsView: View {
    let onAdd: (WidgetConfig) -> Void

    private let platformOrder = ["claude", "openai", "codex", "gemini", "deepseek", "anthropic", "minimax", "mimo"]
    private var groupedPresets: [(String, [WidgetPreset])] {
        platformOrder.compactMap { service in
            let matching = presets.filter { $0.config.service == service }
            return matching.isEmpty ? nil : (service, matching)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("预设组件")
                .font(.caption)
                .foregroundColor(.secondary)

            ForEach(groupedPresets, id: \.0) { service, servicePresets in
                PlatformGroup(service: service, presets: servicePresets)
            }
        }
    }
}

private struct PlatformGroup: View {
    let service: String
    let presets: [WidgetPreset]
    @State private var isExpanded: Bool

    init(service: String, presets: [WidgetPreset]) {
        self.service = service
        self.presets = presets
        _isExpanded = State(initialValue: service == "claude")
    }

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(presets) { preset in
                        PresetCard(preset: preset)
                            .onDrag {
                                NSItemProvider(object: preset.config.id.uuidString as NSString)
                            }
                    }
                }
                .padding(.vertical, 4)
            }
        } label: {
            Text(platformDisplayName(service))
                .font(.system(size: 11, weight: .semibold))
        }
    }

    private func platformDisplayName(_ id: String) -> String {
        switch id {
        case "claude": return "Claude"
        case "openai": return "OpenAI"
        case "codex": return "Codex"
        case "gemini": return "Gemini"
        case "deepseek": return "DeepSeek"
        case "anthropic": return "Anthropic"
        case "minimax":   return "MiniMax"
        case "mimo":      return "MiMo"
        default: return id
        }
    }
}

// MARK: - Main Editor

struct WidgetListEditor: View {
    @Environment(WidgetStore.self) private var store
    @State private var showCustomSheet = false
    @State private var recentlyDroppedIDs = Set<UUID>()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("小组件").font(.headline)
                Spacer()
                Button("恢复默认") { store.resetToDefaults() }
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Top: Grouped presets
            PlatformPresetsView { config in
                store.widgets.append(config)
            }

            Divider()

            // Bottom: Active widgets
            Text("已添加组件")
                .font(.caption)
                .foregroundColor(.secondary)

            if store.widgets.isEmpty {
                Text("拖拽组件到此处")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 80)
                    .background(Color.secondary.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.secondary.opacity(0.15), style: StrokeStyle(lineWidth: 1, dash: [4]))
                    )
                    .onDrop(of: [.text], delegate: WidgetListDropDelegate(widgets: Bindable(store).widgets, recentlyDroppedIDs: $recentlyDroppedIDs))
            } else {
                List {
                    ForEach(store.widgets) { widget in
                        WidgetRow(widget: widget) {
                            store.widgets.removeAll { $0.id == widget.id }
                        }
                    }
                    .onMove { from, to in
                        store.widgets.move(fromOffsets: from, toOffset: to)
                    }
                }
                .listStyle(.bordered)
                .frame(minHeight: 120)
                .onDrop(of: [.text], delegate: WidgetListDropDelegate(widgets: Bindable(store).widgets, recentlyDroppedIDs: $recentlyDroppedIDs))
            }

            Button { showCustomSheet = true } label: {
                Label("自定义组件", systemImage: "plus")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding()
        .sheet(isPresented: $showCustomSheet) {
            CustomWidgetSheet(store: store)
        }
    }
}

// MARK: - Preset Card

private struct PresetCard: View {
    let preset: WidgetPreset

    var body: some View {
        VStack(spacing: 4) {
            Text(preset.serviceDisplayName)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.primary)
            Text(preset.config.metric.displayName)
                .font(.system(size: 9))
                .foregroundColor(.secondary)
                .lineLimit(1)
            HStack(spacing: 2) {
                Text(preset.styleIcon)
                    .font(.system(size: 10))
                Text(preset.config.style.displayName)
                    .font(.system(size: 8))
                    .foregroundColor(.secondary)
            }
        }
        .frame(width: 80, height: 60)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.15), lineWidth: 0.5)
        )
    }
}

// MARK: - Widget Row

private struct WidgetRow: View {
    let widget: WidgetConfig
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: metricIcon(widget.metric))
                .font(.system(size: 10))
                .frame(width: 16)
            Text(widget.service)
                .font(.system(size: 12, weight: .medium))
            Text(widget.metric.displayName)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            Text("· \(widget.style.displayName)")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            Spacer()
            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }

    private func metricIcon(_ metric: WidgetMetric) -> String {
        switch metric {
        case .remainingTime:    return "clock"
        case .resetCountdown:   return "arrow.clockwise"
        case .tokensRemaining:  return "text.bubble"
        case .balance:          return "dollarsign.circle"
        case .sessionTokens:    return "arrow.up.circle"
        case .usagePercent:     return "chart.bar"
        case .inputTokens:      return "arrow.down.circle"
        case .outputTokens:     return "arrow.up.circle"
        case .dailyTokens:      return "calendar"
        case .monthlyTokens:    return "calendar.circle"
        case .costSpent:        return "dollarsign.circle.fill"
        case .dailyRequests:    return "number.circle"
        case .monthlyRequests:  return "number.circle.fill"
        case .sessionDuration:  return "timer"
        case .tokensPerMinute:  return "bolt"
        case .inputOutputRatio: return "arrow.left.arrow.right"
        case .costPerRequest:   return "dollarsign.arrow.circlepath"
        case .rateLimitStatus:  return "exclamationmark.triangle"
        }
    }
}

// MARK: - Drop Delegate

private struct WidgetListDropDelegate: DropDelegate {
    @Binding var widgets: [WidgetConfig]
    @Binding var recentlyDroppedIDs: Set<UUID>

    func performDrop(info: DropInfo) -> Bool {
        guard let item = info.itemProviders(for: [.text]).first else { return false }
        item.loadItem(forTypeIdentifier: "public.text", options: nil) { data, _ in
            guard let data = data as? Data,
                  let uuidString = String(data: data, encoding: .utf8),
                  let uuid = UUID(uuidString: uuidString)
            else { return }

            DispatchQueue.main.async {
                guard !recentlyDroppedIDs.contains(uuid) else { return }
                recentlyDroppedIDs.insert(uuid)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    recentlyDroppedIDs.remove(uuid)
                }

                if let preset = presets.first(where: { $0.config.id == uuid }) {
                    let newWidget = WidgetConfig(
                        service: preset.config.service,
                        metric: preset.config.metric,
                        style: preset.config.style
                    )
                    widgets.append(newWidget)
                }
            }
        }
        return true
    }

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [.text])
    }
}

// MARK: - Custom Widget Sheet

private struct CustomWidgetSheet: View {
    let store: WidgetStore
    @State private var service = "claude"
    @State private var metric: WidgetMetric = .remainingTime
    @State private var style: WidgetStyle = .ring
    @Environment(\.dismiss) var dismiss

    private var availableMetrics: [WidgetMetric] {
        let derived: [WidgetMetric] = [.sessionDuration, .tokensPerMinute, .inputOutputRatio, .costPerRequest, .rateLimitStatus]
        switch service {
        case "codex":     return [.sessionTokens, .remainingTime, .resetCountdown, .usagePercent, .sessionDuration, .rateLimitStatus]
        case "openai":    return [.balance, .inputTokens, .outputTokens, .costSpent, .dailyRequests, .monthlyRequests, .usagePercent] + derived
        case "gemini":    return [.inputTokens, .outputTokens, .dailyTokens, .dailyRequests, .costSpent, .usagePercent] + derived
        case "deepseek":  return [.balance, .inputTokens, .outputTokens, .monthlyTokens, .costSpent, .monthlyRequests, .usagePercent] + derived
        case "anthropic": return [.balance, .inputTokens, .outputTokens, .costSpent, .monthlyRequests, .usagePercent] + derived
        case "minimax":   return [.balance, .inputTokens, .outputTokens, .monthlyTokens, .costSpent, .usagePercent] + derived
        case "mimo":      return [.balance, .inputTokens, .outputTokens, .dailyTokens, .costSpent, .dailyRequests, .usagePercent] + derived
        default:          return WidgetMetric.allCases
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Picker("服务", selection: $service) {
                    Text("Claude").tag("claude")
                    Text("OpenAI").tag("openai")
                    Text("Codex").tag("codex")
                    Text("Gemini").tag("gemini")
                    Text("DeepSeek").tag("deepseek")
                    Text("Anthropic API").tag("anthropic")
                    Text("MiniMax").tag("minimax")
                    Text("MiMo").tag("mimo")
                }
                .onChange(of: service) { _, _ in
                    if !availableMetrics.contains(metric) {
                        metric = availableMetrics.first ?? .sessionTokens
                    }
                }
                Picker("指标", selection: $metric) {
                    ForEach(availableMetrics, id: \.self) {
                        Text($0.displayName).tag($0)
                    }
                }
                Picker("样式", selection: $style) {
                    ForEach(WidgetStyle.allCases, id: \.self) {
                        Text($0.displayName).tag($0)
                    }
                }
            }
            .navigationTitle("自定义组件")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("添加") {
                        let cfg = WidgetConfig(service: service, metric: metric, style: style)
                        store.widgets.append(cfg)
                        dismiss()
                    }
                }
            }
        }
        .frame(width: 320, height: 240)
    }
}
