import SwiftUI
import UniformTypeIdentifiers

// MARK: - Preset Definition

private struct WidgetPreset: Identifiable, Equatable {
    let id = UUID()
    let config: WidgetConfig
}

private struct WidgetCapability {
    let service: String
    let metrics: [WidgetMetric]
    let presets: [WidgetConfig]
}

private let widgetCapabilities: [WidgetCapability] = [
    WidgetCapability(
        service: "claude",
        metrics: [.remainingTime, .tokensRemaining, .sessionTokens],
        presets: [
            WidgetConfig(service: "claude", metric: .remainingTime, style: .bar),
            WidgetConfig(service: "claude", metric: .tokensRemaining, style: .bar),
            WidgetConfig(service: "claude", metric: .sessionTokens, style: .text),
        ]
    ),
    WidgetCapability(
        service: "codex",
        metrics: [.remainingTime, .subscriptionStatus],
        presets: [
            WidgetConfig(service: "codex", metric: .remainingTime, style: .bar, quotaIndex: 0),
            WidgetConfig(service: "codex", metric: .remainingTime, style: .bar, quotaIndex: 1),
            WidgetConfig(service: "codex", metric: .subscriptionStatus, style: .text),
        ]
    ),
    WidgetCapability(
        service: "deepseek",
        metrics: [.balance],
        presets: [
            WidgetConfig(service: "deepseek", metric: .balance, style: .text),
        ]
    ),
    WidgetCapability(
        service: "minimax",
        metrics: [.monthlyTokens, .tokensRemaining, .usagePercent, .balance],
        presets: [
            WidgetConfig(service: "minimax", metric: .monthlyTokens, style: .bar),
            WidgetConfig(service: "minimax", metric: .tokensRemaining, style: .text),
            WidgetConfig(service: "minimax", metric: .usagePercent, style: .text),
            WidgetConfig(service: "minimax", metric: .balance, style: .text),
        ]
    ),
    WidgetCapability(
        service: "mimo",
        metrics: [.creditsUsed, .planName, .resetCountdown],
        presets: [
            WidgetConfig(service: "mimo", metric: .creditsUsed, style: .bar),
            WidgetConfig(service: "mimo", metric: .planName, style: .text),
            WidgetConfig(service: "mimo", metric: .resetCountdown, style: .text),
        ]
    ),
]

private let presets: [WidgetPreset] = widgetCapabilities.flatMap { capability in
    capability.presets.map { WidgetPreset(config: $0) }
}

private func serviceDisplayName(_ id: String) -> String {
    switch id {
    case "claude":    return "Claude"
    case "openai":    return "OpenAI"
    case "codex":     return "Codex"
    case "gemini":    return "Gemini"
    case "deepseek":  return "DeepSeek"
    case "anthropic": return "Anthropic"
    case "minimax":   return "MiniMax"
    case "mimo":      return "MiMo"
    default:          return id
    }
}

private func metricTitle(_ widget: WidgetConfig) -> String {
    if widget.service == "codex", widget.metric == .remainingTime {
        return widget.quotaIndex == 1 ? "7 天剩余量" : "5 小时剩余量"
    }
    if widget.service == "mimo", widget.metric == .resetCountdown {
        return "Token Plan 到期时间"
    }
    if widget.service == "mimo", widget.metric == .remainingTime {
        return "Token Plan 到期时间"
    }
    return widget.metric.displayName
}

private func metricIcon(_ metric: WidgetMetric) -> String {
    switch metric {
    case .remainingTime:     return "clock"
    case .resetCountdown:    return "arrow.clockwise"
    case .tokensRemaining:   return "text.bubble"
    case .balance:           return "dollarsign.circle"
    case .sessionTokens:     return "arrow.up.circle"
    case .usagePercent:      return "chart.bar"
    case .inputTokens:       return "arrow.down.circle"
    case .outputTokens:      return "arrow.up.circle"
    case .dailyTokens:       return "calendar"
    case .monthlyTokens:     return "calendar.circle"
    case .costSpent:         return "dollarsign.circle.fill"
    case .dailyRequests:     return "number.circle"
    case .monthlyRequests:   return "number.circle.fill"
    case .sessionDuration:   return "timer"
    case .tokensPerMinute:   return "bolt"
    case .inputOutputRatio:  return "arrow.left.arrow.right"
    case .costPerRequest:    return "dollarsign.arrow.circlepath"
    case .rateLimitStatus:   return "exclamationmark.triangle"
    case .creditsRemaining:  return "creditcard"
    case .creditsUsed:       return "chart.pie"
    case .sessionCredits:    return "sum"
    case .subscriptionStatus:return "checkmark.seal"
    case .planName:          return "tag"
    }
}

private func styleIcon(_ style: WidgetStyle) -> String {
    switch style {
    case .ring:           return "circle"
    case .bar:            return "chart.bar.xaxis"
    case .text:           return "textformat"
    case .aggregate:      return "sum"
    case .multi:          return "square.grid.2x2"
    case .countdown:      return "timer"
    case .status:         return "smallcircle.filled.circle"
    case .modelBreakdown: return "list.bullet.rectangle"
    }
}

// MARK: - Main Editor

struct WidgetListEditor: View {
    @Environment(WidgetStore.self) private var store
    @Environment(StateWatcher.self) private var watcher
    @State private var showCustomSheet = false
    @State private var recentlyDroppedIDs = Set<UUID>()

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            WidgetPreviewPanel(widgets: store.widgets, state: watcher.effectiveState)
                .onDrop(of: [.text], delegate: WidgetListDropDelegate(
                    widgets: Bindable(store).widgets,
                    recentlyDroppedIDs: $recentlyDroppedIDs
                ))

            HStack(alignment: .top, spacing: 14) {
                ActiveWidgetsPanel(
                    widgets: Bindable(store).widgets,
                    recentlyDroppedIDs: $recentlyDroppedIDs
                )
                AddWidgetsPanel(
                    onAdd: addWidget,
                    onCustom: { showCustomSheet = true }
                )
            }
        }
        .padding()
        .sheet(isPresented: $showCustomSheet) {
            CustomWidgetSheet(store: store)
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("小组件")
                    .font(.headline)
                Text("配置会立即反映在上方预览和浮动面板中。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                store.resetToDefaults()
            } label: {
                Label("恢复默认", systemImage: "arrow.counterclockwise")
            }
            .font(.caption)
        }
    }

    private func addWidget(_ config: WidgetConfig) {
        store.widgets.append(WidgetConfig(
            service: config.service,
            metric: config.metric,
            style: config.style,
            quotaIndex: config.quotaIndex
        ))
    }
}

// MARK: - Preview

private struct WidgetPreviewPanel: View {
    let widgets: [WidgetConfig]
    let state: StateFile

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("当前效果", systemImage: "rectangle.dashed")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(widgets.count) 个组件")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(nsColor: .black).opacity(0.90),
                                Color(red: 0.08, green: 0.09, blue: 0.12).opacity(0.96)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    )

                if widgets.isEmpty {
                    VStack(spacing: 6) {
                        Image(systemName: "rectangle.3.group")
                            .font(.system(size: 22))
                            .foregroundStyle(.white.opacity(0.45))
                        Text("还没有小组件")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.white.opacity(0.75))
                        Text("从下方预设添加，或拖拽预设到这里。")
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.45))
                    }
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(widgets) { config in
                                WidgetRenderer(config: config, state: state, showServiceLabel: true)
                                    .padding(.vertical, 4)
                            }
                        }
                        .padding(.horizontal, 16)
                        .frame(maxWidth: .infinity, alignment: .center)
                    }
                }
            }
            .frame(height: 118)
            .environment(\.panelAdaptiveScale, 1.15)
        }
    }
}

// MARK: - Active Widgets

private struct ActiveWidgetsPanel: View {
    @Binding var widgets: [WidgetConfig]
    @Binding var recentlyDroppedIDs: Set<UUID>

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("已添加", systemImage: "line.3.horizontal.decrease.circle")
                    .font(.caption.weight(.semibold))
                Spacer()
                Text("拖动调整顺序")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if widgets.isEmpty {
                Text("拖拽组件到此处")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 150)
                    .background(Color.secondary.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.secondary.opacity(0.18), style: StrokeStyle(lineWidth: 1, dash: [4]))
                    )
                    .onDrop(of: [.text], delegate: WidgetListDropDelegate(
                        widgets: $widgets,
                        recentlyDroppedIDs: $recentlyDroppedIDs
                    ))
            } else {
                List {
                    ForEach(widgets) { widget in
                        WidgetRow(widget: widget) {
                            widgets.removeAll { $0.id == widget.id }
                        }
                    }
                    .onMove { from, to in
                        widgets.move(fromOffsets: from, toOffset: to)
                    }
                }
                .listStyle(.bordered)
                .frame(minHeight: 220)
                .onDrop(of: [.text], delegate: WidgetListDropDelegate(
                    widgets: $widgets,
                    recentlyDroppedIDs: $recentlyDroppedIDs
                ))
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

private struct WidgetRow: View {
    let widget: WidgetConfig
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: metricIcon(widget.metric))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(metricTitle(widget))
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Text(serviceDisplayName(widget.service))
                    Text("·")
                    Image(systemName: styleIcon(widget.style))
                    Text(widget.style.displayName)
                }
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }

            Spacer()

            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary)
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .help("移除")
        }
        .padding(.vertical, 5)
    }
}

// MARK: - Add Widgets

private struct AddWidgetsPanel: View {
    let onAdd: (WidgetConfig) -> Void
    let onCustom: () -> Void

    private let columns = [
        GridItem(.adaptive(minimum: 104, maximum: 132), spacing: 8)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("添加组件", systemImage: "plus.circle")
                    .font(.caption.weight(.semibold))
                Spacer()
                Button(action: onCustom) {
                    Label("自定义", systemImage: "slider.horizontal.3")
                }
                .font(.caption)
            }

            ScrollView {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                    ForEach(presets) { preset in
                        PresetCard(preset: preset) {
                            onAdd(preset.config)
                        }
                        .onDrag {
                            NSItemProvider(object: preset.config.id.uuidString as NSString)
                        }
                    }
                }
                .padding(1)
            }
            .frame(minHeight: 220)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

private struct PresetCard: View {
    let preset: WidgetPreset
    let onAdd: () -> Void

    var body: some View {
        Button(action: onAdd) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: metricIcon(preset.config.metric))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.tint)
                    Text(serviceDisplayName(preset.config.service))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.primary)
                    Spacer(minLength: 0)
                }

                Text(metricTitle(preset.config))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                HStack(spacing: 4) {
                    Image(systemName: styleIcon(preset.config.style))
                    Text(preset.config.style.displayName)
                }
                .font(.system(size: 10))
                .foregroundColor(.secondary)
            }
            .padding(10)
            .frame(maxWidth: .infinity, minHeight: 76, alignment: .leading)
            .background(Color.secondary.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.secondary.opacity(0.14), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .help("点击添加，也可以拖到预览或已添加列表")
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
                    widgets.append(WidgetConfig(
                        service: preset.config.service,
                        metric: preset.config.metric,
                        style: preset.config.style,
                        quotaIndex: preset.config.quotaIndex
                    ))
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
    @State private var service = widgetCapabilities.first?.service ?? "claude"
    @State private var metric: WidgetMetric = .remainingTime
    @State private var style: WidgetStyle = .bar
    @Environment(\.dismiss) var dismiss

    private var availableMetrics: [WidgetMetric] {
        widgetCapabilities.first { $0.service == service }?.metrics ?? []
    }

    private let availableStyles: [WidgetStyle] = [.bar, .text]

    private var serviceOptions: [String] {
        widgetCapabilities.map(\.service)
    }

    var body: some View {
        NavigationStack {
            Form {
                Picker("服务", selection: $service) {
                    ForEach(serviceOptions, id: \.self) { service in
                        Text(serviceDisplayName(service)).tag(service)
                    }
                }
                .onChange(of: service) { _, _ in
                    if !availableMetrics.contains(metric) {
                        metric = availableMetrics.first ?? .sessionTokens
                    }
                }
                Picker("指标", selection: $metric) {
                    ForEach(availableMetrics, id: \.self) {
                        Text(metricTitle(WidgetConfig(service: service, metric: $0, style: style))).tag($0)
                    }
                }
                Picker("样式", selection: $style) {
                    ForEach(availableStyles, id: \.self) {
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
                        store.widgets.append(WidgetConfig(service: service, metric: metric, style: style))
                        dismiss()
                    }
                }
            }
        }
        .frame(width: 320, height: 240)
    }
}
