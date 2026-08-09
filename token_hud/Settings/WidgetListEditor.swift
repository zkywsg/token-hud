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
        metrics: [.remainingTime],
        presets: [
            WidgetConfig(service: "codex", metric: .remainingTime, style: .bar, quotaIndex: 0),
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
        metrics: [.creditsUsed],
        presets: [
            WidgetConfig(service: "mimo", metric: .creditsUsed, style: .bar),
        ]
    ),
]

/// Retired metrics are filtered out here so no picker, preset, or
/// recommendation can surface one. See `RetiredMetrics`.
private let presets: [WidgetPreset] = widgetCapabilities.flatMap { capability in
    capability.presets
        .filter { $0.metric.isSelectable }
        .map { WidgetPreset(config: $0) }
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
        // Window name comes from live data (see WidgetMetricComputer); without
        // state here, stay neutral rather than guessing from quotaIndex.
        return "限额剩余量"
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

            // Two-column workbench: content on the left, a live preview plus the
            // settings that shape it on the right, so editing and seeing the
            // result no longer live on opposite ends of a scroll.
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 14) {
                    contentColumn.frame(maxWidth: .infinity)
                    inspectorColumn.frame(maxWidth: .infinity)
                }
                VStack(alignment: .leading, spacing: 14) {
                    inspectorColumn
                    contentColumn
                }
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

    /// Left: what the HUD shows — search, the ordered active list, and
    /// everything that can still be added.
    private var contentColumn: some View {
        WidgetContentColumn(
            widgets: Bindable(store).widgets,
            recommendations: recommendedWidgets,
            state: watcher.effectiveState,
            recentlyDroppedIDs: $recentlyDroppedIDs,
            onAdd: addWidget,
            onCustom: { showCustomSheet = true }
        )
    }

    /// Right: the live card plus the settings that change how it looks.
    private var inspectorColumn: some View {
        VStack(alignment: .leading, spacing: 14) {
            WidgetPreviewPanel(widgets: Bindable(store).widgets, state: watcher.effectiveState)
                .onDrop(of: [.text], delegate: WidgetListDropDelegate(
                    widgets: Bindable(store).widgets,
                    recentlyDroppedIDs: $recentlyDroppedIDs
                ))
            WidgetDisplaySettingsPanel(widgets: store.widgets, state: watcher.effectiveState)
        }
    }

    private var header: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline) {
                headerCopy
                Spacer(minLength: 12)
                resetDefaultsButton
            }
            VStack(alignment: .leading, spacing: 8) {
                headerCopy
                resetDefaultsButton
            }
        }
    }

    private var headerCopy: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("小组件")
                .font(.headline)
            Text("配置会立即反映在上方预览和浮动面板中。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
    }

    private var resetDefaultsButton: some View {
        Button {
            store.resetToDefaults()
        } label: {
            Label("恢复默认", systemImage: "arrow.counterclockwise")
        }
        .font(.caption)
    }

    private func addWidget(_ config: WidgetConfig) {
        store.widgets.append(WidgetConfig(
            service: config.service,
            metric: config.metric,
            style: config.style,
            quotaIndex: config.quotaIndex
        ))
    }


    /// Recommendations come from core as raw descriptors and can still name
    /// retired metrics; filter them here too.
    private var recommendedWidgets: [WidgetConfig] {
        WidgetRecommendationEngine
            .recommendations(
                for: credentialSnapshot,
                state: watcher.effectiveState,
                includeCodexLocalAuth: isCodexConfigured
            )
            .compactMap(WidgetConfig.init(descriptor:))
            .filter { $0.metric.isSelectable }
    }


    private var isCodexConfigured: Bool {
        if case .configured = CodexAuthReader.status() {
            return true
        }
        return false
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

// MARK: - Left column: content

/// Search + the ordered active list + everything still addable, as one
/// continuous column. Replaces the old "推荐组件" panel and the 已添加/添加
/// segmented switch, which split closely-related actions across two views.
private struct WidgetContentColumn: View {
    @Binding var widgets: [WidgetConfig]
    let recommendations: [WidgetConfig]
    let state: StateFile?
    @Binding var recentlyDroppedIDs: Set<UUID>
    let onAdd: (WidgetConfig) -> Void
    let onCustom: () -> Void

    @State private var searchText = ""
    @State private var showsUnavailable = false

    /// Candidates not already added, matching the search field.
    private var addable: [WidgetConfig] {
        let existing = Set(widgets.map(\.descriptor.semanticKey))
        var seen = Set<String>()
        let pool = recommendations + presets.map(\.config)
        return pool.filter { config in
            let key = config.descriptor.semanticKey
            guard !existing.contains(key), seen.insert(key).inserted else { return false }
            guard !searchText.isEmpty else { return true }
            let needle = searchText.lowercased()
            return serviceDisplayName(config.service).lowercased().contains(needle)
                || metricTitle(config).lowercased().contains(needle)
        }
    }

    /// Candidates that would actually render a value right now. Asking the very
    /// computer the card uses is the honest test: providers missing from
    /// state.json, ones reporting an error, and metrics whose quota has no data
    /// all resolve to "—", and offering those just produces empty cards.
    private var available: [WidgetConfig] { addable.filter { Self.hasData($0, state) } }
    private var unavailable: [WidgetConfig] { addable.filter { !Self.hasData($0, state) } }

    static func hasData(_ config: WidgetConfig, _ state: StateFile?) -> Bool {
        let value = WidgetMetricComputer(config: config, state: state).formattedValue
        return value != "—" && !value.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                TextField("搜索平台或指标…", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(Color.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 7))

            ActiveWidgetsPanel(
                widgets: $widgets,
                state: state,
                recentlyDroppedIDs: $recentlyDroppedIDs
            )

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Label("可添加", systemImage: "plus.circle")
                        .font(.caption.weight(.semibold))
                    Spacer()
                    Button(action: onCustom) {
                        Label("自定义", systemImage: "slider.horizontal.3")
                    }
                    .font(.caption)
                }
                if available.isEmpty {
                    Text(searchText.isEmpty
                         ? "有数据的指标都已加上。"
                         : "没有匹配且有数据的指标。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 6)
                } else {
                    VStack(spacing: 4) {
                        ForEach(available, id: \.descriptor.semanticKey) { config in
                            AddableWidgetRow(config: config) { onAdd(config) }
                        }
                    }
                }

                // Metrics whose provider isn't connected or returns nothing are
                // kept out of the way rather than padding the list with options
                // that would render an empty card.
                if !unavailable.isEmpty {
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) { showsUnavailable.toggle() }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: showsUnavailable ? "chevron.down" : "chevron.right")
                                .font(.system(size: 8, weight: .semibold))
                            Text("暂无数据 \(unavailable.count)")
                            Spacer()
                        }
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 2)

                    if showsUnavailable {
                        VStack(spacing: 4) {
                            ForEach(unavailable, id: \.descriptor.semanticKey) { config in
                                AddableWidgetRow(config: config, isUnavailable: true) { onAdd(config) }
                            }
                        }
                        Text("这些平台未连接或未返回数据；在「平台」页配置后会自动出现在上面。")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(10)
            .background(Color.secondary.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.secondary.opacity(0.10), lineWidth: 0.8)
            )
        }
    }
}

private struct AddableWidgetRow: View {
    let config: WidgetConfig
    var isUnavailable = false
    let onAdd: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: metricIcon(config.metric))
                .font(.system(size: 11))
                .foregroundStyle(serviceAccentSwiftUIColor(for: config.service))
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 1) {
                Text(metricTitle(config))
                    .font(.system(size: 11.5, weight: .medium))
                    .lineLimit(1)
                Text(serviceDisplayName(config.service))
                    .font(.system(size: 9.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 6)
            Button(action: onAdd) {
                Image(systemName: "plus")
                    .font(.system(size: 10, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
        .opacity(isUnavailable ? 0.45 : 1)
        .contentShape(Rectangle())
        .onTapGesture(perform: onAdd)
    }
}

// MARK: - Right column: display settings

/// The settings that change how the previewed card looks, sitting directly
/// under the preview instead of on a different page.
private struct WidgetDisplaySettingsPanel: View {
    let widgets: [WidgetConfig]
    let state: StateFile?

    @AppStorage("focusGaugeStyle") private var focusGaugeStyle = FocusGaugeStyle.default.rawValue
    @AppStorage("widgetSizeScale") private var widgetSizeScale = 1.0
    @AppStorage("notchCollapsedLeadingSource") private var leadingSource = NotchCollapsedSourceStore.autoRawValue
    @AppStorage("notchCollapsedTrailingSource") private var trailingSource = NotchCollapsedSourceStore.autoRawValue

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Label("显示", systemImage: "paintbrush")
                .font(.caption.weight(.semibold))

            LabeledContent("进度条样式") {
                Picker("", selection: $focusGaugeStyle) {
                    ForEach(FocusGaugeStyle.allCases, id: \.rawValue) { style in
                        Text(style.displayName).tag(style.rawValue)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
            }

            LabeledContent("内容大小") {
                Picker("", selection: $widgetSizeScale) {
                    Text("小").tag(0.75)
                    Text("中").tag(1.0)
                    Text("大").tag(1.25)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 150)
            }

            Divider().padding(.vertical, 1)

            // Without this the daily-usage feature is invisible until enough
            // history exists — there was no way to tell it was even running.
            UsageHistoryStatusRows()

            Divider().padding(.vertical, 1)

            Text("刘海收起态")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            LabeledContent("左侧") { collapsedPicker($leadingSource) }
            LabeledContent("右侧") { collapsedPicker($trailingSource) }
        }
        .font(.system(size: 11.5))
        .padding(10)
        .background(Color.secondary.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.10), lineWidth: 0.8)
        )
    }

    private func collapsedPicker(_ selection: Binding<String>) -> some View {
        Picker("", selection: selection) {
            Text("自动").tag(NotchCollapsedSourceStore.autoRawValue)
            ForEach(widgets) { widget in
                Text(label(for: widget))
                    .tag(NotchCollapsedSourceStore.rawValue(for: .widget(widget.id.uuidString)))
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
    }

    private func label(for widget: WidgetConfig) -> String {
        let computer = WidgetMetricComputer(config: widget, state: state)
        let title = computer.metricTitle
        return title.isEmpty ? computer.serviceLabel : "\(computer.serviceLabel) · \(title)"
    }
}

/// Shows which providers are having their daily usage recorded and how far
/// along each is, so the feature is legible before the chart can appear.
private struct UsageHistoryStatusRows: View {
    @Environment(UsageHistoryStore.self) private var history: UsageHistoryStore?

    var body: some View {
        if let history, !history.trackedServiceIDs.isEmpty {
            VStack(alignment: .leading, spacing: 5) {
                Text("每日用量记录")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                ForEach(history.trackedServiceIDs, id: \.self) { id in
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Theme.Palette.statusOK)
                            .frame(width: 5, height: 5)
                        Text(serviceDisplayName(id))
                            .font(.system(size: 11))
                        Spacer(minLength: 6)
                        Text(statusText(for: id, history: history))
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
                Text("上游只给本周期累计值，每日数据靠本地采样差分得出，历史无法回填。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func statusText(for id: String, history: UsageHistoryStore) -> String {
        let spanned = history.daysSinceFirstSample(for: id) ?? 0
        let withUsage = history.recordedDayCount(for: id)
        if withUsage >= UsageHistoryCalculator.minimumDaysForChart {
            return "已记录 \(spanned) 天 · 图表已启用"
        }
        return spanned <= 1 ? "今天开始记录" : "已记录 \(spanned) 天"
    }
}

// MARK: - Preview

private struct WidgetPreviewPanel: View {
    @Binding var widgets: [WidgetConfig]
    let state: StateFile

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("实时预览", systemImage: "rectangle.dashed")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(summaryText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            ZStack {
                GlassPanelBackground(
                    shape: RoundedRectangle(cornerRadius: 12, style: .continuous),
                    opacity: 0.6
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
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    OverlayFocusView(widgets: widgets, state: state)
                        .environment(\.panelAdaptiveScale, 1.0)
                        .padding(12)
                }
            }
            // Size the preview to its content instead of a fixed tall box, so a
            // single widget no longer leaves a large empty void below it.
            .frame(height: previewHeight)
        }
    }

    /// The preview shows one focus card at a time (swipe to change), so its
    /// height is the card's own height plus the dots row — not a function of how
    /// many widgets exist. The old per-row formula was sized for the retired
    /// stacked list and cropped the card.
    private var previewHeight: CGFloat {
        guard !widgets.isEmpty else { return 118 }
        let card = NotchGeometryCalculator.focusCardHeight
        let dots: CGFloat = widgets.count > 1 ? 14 : 0
        return card + dots + 24
    }

    private var summaryText: String {
        guard !widgets.isEmpty else { return "0 个组件" }
        return "\(widgets.count) 个组件 · 第一条为主指标 · 排序在下方"
    }
}

private struct ActiveWidgetsPanel: View {
    @Binding var widgets: [WidgetConfig]
    var state: StateFile?
    @Binding var recentlyDroppedIDs: Set<UUID>
    var showsHeader = true

    /// Height that hugs the rows, so a short list no longer sits in a tall
    /// half-empty table. Capped so a long list scrolls instead of pushing the
    /// rest of the column off-screen.
    private var listHeight: CGFloat {
        min(320, max(76, CGFloat(widgets.count) * 44 + 8))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if showsHeader {
                HStack {
                    Label("已添加", systemImage: "line.3.horizontal.decrease.circle")
                        .font(.caption.weight(.semibold))
                    Spacer()
                    Text("拖动调整顺序")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
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
                // Kept as a List purely for `.onMove` drag-reordering, but
                // stripped of its table chrome so it reads as part of the glass
                // card rather than a nested system control.
                List {
                    ForEach(widgets) { widget in
                        WidgetRow(
                            widget: widget,
                            hasData: WidgetContentColumn.hasData(widget, state)
                        ) {
                            widgets.removeAll { $0.id == widget.id }
                        }
                        .listRowInsets(EdgeInsets(top: 2, leading: 4, bottom: 2, trailing: 4))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    }
                    .onMove { from, to in
                        widgets.move(fromOffsets: from, toOffset: to)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .environment(\.defaultMinListRowHeight, 34)
                .frame(height: listHeight)
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
    var hasData = true
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
                HStack(spacing: 5) {
                    Text(serviceDisplayName(widget.service))
                    if !hasData {
                        // Explains an empty-looking card instead of leaving the
                        // user to wonder why it shows nothing.
                        Text("无数据")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(Theme.Palette.statusWarn)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Theme.Palette.statusWarn.opacity(0.16), in: Capsule())
                    }
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
            capability.metrics
                .filter(\.isSelectable)
                .map { Option(service: capability.service, metric: $0) }
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
        }
        .frame(width: 520, height: 420)
    }
}
