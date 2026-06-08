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
        service: "openai",
        metrics: [.costSpent, .dailyRequests, .monthlyRequests],
        presets: []
    ),
    WidgetCapability(
        service: "gemini",
        metrics: [.dailyRequests, .dailyTokens, .sessionTokens],
        presets: []
    ),
    WidgetCapability(
        service: "deepseek",
        metrics: [.balance],
        presets: [
            WidgetConfig(service: "deepseek", metric: .balance, style: .text),
        ]
    ),
    WidgetCapability(
        service: "anthropic",
        metrics: [.costSpent, .monthlyRequests, .sessionTokens],
        presets: []
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
    @State private var credentialSnapshot = ProviderCredentialSnapshot.empty

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            ConfiguredWidgetRecommendationPanel(
                currentWidgets: store.widgets,
                recommendations: recommendedWidgets,
                configuredCount: configuredProviderCount,
                onAdd: prependWidget,
                onPrependMissing: prependMissingRecommendations
            )

            WidgetPreviewPanel(widgets: store.widgets, state: watcher.effectiveState)
                .onDrop(of: [.text], delegate: WidgetListDropDelegate(
                    widgets: Bindable(store).widgets,
                    recentlyDroppedIDs: $recentlyDroppedIDs
                ))

            NotchCollapsedSettingsPanel(
                widgets: store.widgets,
                recommendations: recommendedWidgets,
                state: watcher.effectiveState
            )

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
        .task {
            reloadCredentialSnapshot()
            populateEmptyWidgetListIfNeeded()
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

    private func prependWidget(_ config: WidgetConfig) {
        let key = config.descriptor.semanticKey
        guard !store.widgets.contains(where: { $0.descriptor.semanticKey == key }) else { return }
        store.widgets.insert(WidgetConfig(
            service: config.service,
            metric: config.metric,
            style: config.style,
            quotaIndex: config.quotaIndex
        ), at: 0)
    }

    private var recommendedWidgets: [WidgetConfig] {
        WidgetRecommendationEngine
            .recommendations(
                for: credentialSnapshot,
                state: watcher.effectiveState,
                includeCodexLocalAuth: isCodexConfigured
            )
            .compactMap(WidgetConfig.init(descriptor:))
    }

    private var configuredProviderCount: Int {
        ProviderCapability.all.filter { provider in
            switch provider.credentialKind {
            case .codexLocalAuth:
                return isCodexConfigured
            default:
                return credentialSnapshot.status(for: provider) == .configured
            }
        }.count
    }

    private var isCodexConfigured: Bool {
        if case .configured = CodexAuthReader.status() {
            return true
        }
        return false
    }

    private func prependMissingRecommendations() {
        let existingKeys = Set(store.widgets.map { $0.descriptor.semanticKey })
        let missing = recommendedWidgets.filter { !existingKeys.contains($0.descriptor.semanticKey) }
        guard !missing.isEmpty else { return }
        store.widgets = missing + store.widgets
    }

    private func populateEmptyWidgetListIfNeeded() {
        guard store.widgets.isEmpty else { return }
        let recommended = recommendedWidgets
        store.widgets = recommended.isEmpty ? WidgetStore.defaultWidgets : recommended
    }

    private func reloadCredentialSnapshot() {
        var apiKeys: [String: String] = [:]
        for provider in ProviderCapability.all {
            switch provider.credentialKind {
            case .apiKey, .apiKeyAndConsoleCookie:
                if KeychainHelper.hasAPIKey(for: provider.id) {
                    apiKeys[provider.id] = provider.id == "mimo"
                        ? MiMoAPIKeyRoleStore.snapshotValue()
                        : "saved"
                }
            case .sessionKey, .codexLocalAuth:
                break
            }
        }

        credentialSnapshot = ProviderCredentialSnapshot(
            claudeSessionKey: KeychainHelper.hasClaudeSessionKey() ? "saved" : nil,
            apiKeys: apiKeys,
            mimoConsoleCookie: KeychainHelper.hasMiMoConsoleCookie() ? "saved" : nil,
            codexAdminKey: KeychainHelper.hasCodexAdminKey() ? "saved" : nil
        )
    }
}

// MARK: - Configured Recommendations

private struct ConfiguredWidgetRecommendationPanel: View {
    let currentWidgets: [WidgetConfig]
    let recommendations: [WidgetConfig]
    let configuredCount: Int
    let onAdd: (WidgetConfig) -> Void
    let onPrependMissing: () -> Void

    private let columns = [
        GridItem(.adaptive(minimum: 210, maximum: 280), spacing: 8)
    ]

    private var existingKeys: Set<String> {
        Set(currentWidgets.map { $0.descriptor.semanticKey })
    }

    private var missingCount: Int {
        recommendations.filter { !existingKeys.contains($0.descriptor.semanticKey) }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 3) {
                    Label("可添加的小组件推荐", systemImage: "plus.square.on.square")
                        .font(.caption.weight(.semibold))
                    Text(configuredCount > 0
                         ? "来自 \(configuredCount) 个已配置平台，可加入当前小组件。"
                         : "配置平台后，这里会显示可直接加入的小组件。")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    onPrependMissing()
                } label: {
                    Label("补齐缺失", systemImage: "text.insert")
                }
                .font(.caption)
                .disabled(missingCount == 0)
            }

            if recommendations.isEmpty {
                Text("暂无可推荐组件")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 54)
                    .background(Color.secondary.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.secondary.opacity(0.12), lineWidth: 0.5)
                    )
            } else {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                    ForEach(recommendations, id: \.descriptor.semanticKey) { widget in
                        RecommendationChip(
                            widget: widget,
                            isAdded: existingKeys.contains(widget.descriptor.semanticKey),
                            onAdd: { onAdd(widget) }
                        )
                    }
                }
            }
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.12), lineWidth: 0.8)
        )
    }
}

private struct RecommendationChip: View {
    let widget: WidgetConfig
    let isAdded: Bool
    let onAdd: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: metricIcon(widget.metric))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(isAdded ? Color.secondary : Color.accentColor)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(serviceDisplayName(widget.service))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(isAdded ? .secondary : .primary)
                Text(metricTitle(widget))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)

            if isAdded {
                Label("已添加", systemImage: "checkmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .labelStyle(.titleAndIcon)
            } else {
                Button {
                    onAdd()
                } label: {
                    Label("添加", systemImage: "plus")
                }
                .font(.system(size: 10, weight: .semibold))
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(isAdded ? Color.secondary.opacity(0.06) : Color.accentColor.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .stroke(isAdded ? Color.secondary.opacity(0.10) : Color.accentColor.opacity(0.14), lineWidth: 0.6)
        )
    }
}

// MARK: - Notch Collapsed Settings

private struct NotchCollapsedSettingsPanel: View {
    let widgets: [WidgetConfig]
    let recommendations: [WidgetConfig]
    let state: StateFile

    @AppStorage("notchCollapsedLeadingSource") private var leadingSource = NotchCollapsedSourceStore.autoRawValue
    @AppStorage("notchCollapsedTrailingSource") private var trailingSource = NotchCollapsedSourceStore.autoRawValue

    private var status: NotchCollapsedStatusDisplay {
        NotchCollapsedStatusEngine.value(
            widgets: widgets.map(\.descriptor),
            state: state,
            configuration: NotchCollapsedStatusConfiguration(
                leading: NotchCollapsedSourceStore.source(from: leadingSource),
                trailing: NotchCollapsedSourceStore.source(from: trailingSource)
            )
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("刘海收起态", systemImage: "rectangle.compress.vertical")
                    .font(.caption.weight(.semibold))
                Spacer()
                compactPreview
            }

            HStack(spacing: 12) {
                sourcePicker(title: "左侧", selection: $leadingSource)
                sourcePicker(title: "右侧", selection: $trailingSource)
            }
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.12), lineWidth: 0.8)
        )
    }

    private var compactPreview: some View {
        HStack(spacing: 8) {
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.16))
                Capsule()
                    .fill(progressColor(for: status.leadingFraction))
                    .frame(width: 42 * status.leadingFraction.clamped(to: 0...1))
            }
            .frame(width: 42, height: 5)

            Text(status.trailingText)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.92))
                .frame(width: 34, alignment: .trailing)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.black.opacity(0.92))
        .clipShape(Capsule())
    }

    private func sourcePicker(title: String, selection: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Picker(title, selection: selection) {
                Text("自动").tag(NotchCollapsedSourceStore.autoRawValue)
                if !widgets.isEmpty {
                    Section("当前小组件") {
                        ForEach(widgets) { widget in
                            Text("\(serviceDisplayName(widget.service)) · \(metricTitle(widget))")
                                .tag(NotchCollapsedSourceStore.rawValue(for: .widget(widget.id.uuidString)))
                        }
                    }
                }
                if !recommendations.isEmpty {
                    Section("已配置推荐") {
                        ForEach(recommendations, id: \.descriptor.semanticKey) { widget in
                            Text("\(serviceDisplayName(widget.service)) · \(metricTitle(widget))")
                                .tag(NotchCollapsedSourceStore.rawValue(for: .metric(
                                    service: widget.service,
                                    metric: widget.metric.rawValue,
                                    quotaIndex: widget.quotaIndex
                                )))
                        }
                    }
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func progressColor(for fraction: Double) -> Color {
        if fraction >= 0.85 { return Color(red: 1.0, green: 0.28, blue: 0.34) }
        if fraction >= 0.65 { return Color(red: 1.0, green: 0.76, blue: 0.20) }
        return Color(red: 0.30, green: 0.86, blue: 0.55)
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
                    .fill(Color(red: 0.015, green: 0.017, blue: 0.02).opacity(0.96))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.white.opacity(0.10), lineWidth: 0.8)
                    )
                    .shadow(color: Color.black.opacity(0.16), radius: 14, y: 8)

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
                        Image(systemName: metricIcon(option.metric))
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
