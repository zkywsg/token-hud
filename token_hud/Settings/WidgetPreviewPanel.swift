import SwiftUI

struct WidgetPreviewPanel: View {
    @Binding var widgets: [WidgetConfig]
    let state: StateFile

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("当前效果", systemImage: "rectangle.dashed")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(summaryText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(CompactBlackTheme.surface)
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(CompactBlackTheme.hairline, lineWidth: 0.8)
                    .shadow(color: Color.black.opacity(0.22), radius: 14, y: 8)

                if widgets.isEmpty {
                    VStack(spacing: 6) {
                        Image(systemName: "rectangle.3.group")
                            .font(.system(size: 22))
                            .foregroundStyle(HUDTextStyle.placeholder)
                        Text("还没有小组件")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.white.opacity(0.75))
                        Text("从下方预设添加，或拖拽预设到这里。")
                            .font(.caption2)
                            .foregroundStyle(HUDTextStyle.placeholder)
                    }
                } else {
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(groupedWidgets) { group in
                                WidgetPreviewGroupView(
                                    group: group,
                                    state: state,
                                    onRemove: removeWidget
                                )
                            }
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                }
            }
            .frame(height: widgets.isEmpty ? 118 : 224)
            .animation(.easeInOut(duration: 0.25), value: widgets.isEmpty)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .environment(\.panelAdaptiveScale, 1.15)
        }
    }

    private var summaryText: String {
        guard !widgets.isEmpty else { return "0 个组件" }
        return "\(groupedWidgets.count) 组 · \(widgets.count) 个组件 · 排序在下方"
    }

    private var groupedWidgets: [WidgetPreviewGroup] {
        let configsByID = Dictionary(uniqueKeysWithValues: widgets.map { ($0.id.uuidString, $0) })
        return WidgetServiceGrouping
            .groups(for: widgets.map(\.descriptor))
            .map { group in
                WidgetPreviewGroup(
                    service: group.service,
                    widgets: group.widgets.compactMap { configsByID[$0.id] }
                )
            }
            .filter { !$0.widgets.isEmpty }
    }

    private func removeWidget(_ config: WidgetConfig) {
        widgets.removeAll { $0.id == config.id }
    }
}

// MARK: - Group

struct WidgetPreviewGroup: Identifiable {
    let service: String
    let widgets: [WidgetConfig]

    var id: String { service }
}

// MARK: - Group View

struct WidgetPreviewGroupView: View {
    let group: WidgetPreviewGroup
    let state: StateFile
    let onRemove: (WidgetConfig) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(serviceDisplayName(group.service, state: state))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(HUDTextStyle.secondary)
                Text("\(group.widgets.count)")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(HUDTextStyle.subtle)
                Spacer(minLength: 0)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(group.widgets) { config in
                        WidgetPreviewItem(config: config, state: state) {
                            onRemove(config)
                        }
                    }
                }
                .padding(.trailing, 2)
            }
        }
    }
}

// MARK: - Item

struct WidgetPreviewItem: View {
    let config: WidgetConfig
    let state: StateFile
    let onRemove: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            WidgetRenderer(config: config, state: state, showServiceLabel: false)
                .padding(.vertical, 6)
                .padding(.leading, 8)
                .padding(.trailing, 24)

            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.48))
                    .frame(width: 16, height: 16)
                    .padding(6)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("移除")
            .padding(.top, 2)
            .padding(.trailing, 2)
        }
        .background(CompactBlackTheme.inset)
        .clipShape(RoundedRectangle(cornerRadius: CompactBlackTheme.cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: CompactBlackTheme.cornerRadius, style: .continuous)
                .stroke(CompactBlackTheme.hairlineSoft, lineWidth: 0.7)
        )
    }
}
