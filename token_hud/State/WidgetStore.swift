// token_hud/State/WidgetStore.swift
import Foundation
import Observation

@Observable
@MainActor
final class WidgetStore {

    /// Retired metrics are rejected here rather than at each call site — the
    /// store is the one place every write passes through (defaults, reset,
    /// migration, the editor, drag-and-drop), so filtering anywhere else just
    /// leaves gaps.
    var widgets: [WidgetConfig] {
        didSet {
            let cleaned = Self.dropRetired(widgets)
            if cleaned != widgets {
                widgets = cleaned // re-enters didSet once; then falls through to save
                return
            }
            save()
        }
    }

    private enum Keys {
        static let v3     = "widgets_v3"
        static let leftV2 = "leftWidgets_v2"
        static let rightV2 = "rightWidgets_v2"
        static let leftV1 = "leftWidgets_v1"
        static let rightV1 = "rightWidgets_v1"
    }

    init() {
        let decoder = JSONDecoder()

        // 1. Try v3 (unified)
        if let d = UserDefaults.standard.data(forKey: Keys.v3),
           let v = try? decoder.decode([WidgetConfig].self, from: d) {
            let cleaned = Self.dropRetired(v)
            self.widgets = cleaned
            // didSet doesn't fire during init, so persist the cleanup here.
            if cleaned.count != v.count { save() }
            return
        }

        // 2. Migrate from v2 left+right
        let left = Self.loadArray(forKey: Keys.leftV2, decoder: decoder)
               ?? Self.loadArray(forKey: Keys.leftV1, decoder: decoder).map { Self.migrateV1($0) }
               ?? Self.defaultWidgets
        let right = Self.loadArray(forKey: Keys.rightV2, decoder: decoder)
                ?? Self.loadArray(forKey: Keys.rightV1, decoder: decoder).map { Self.migrateV1($0) }
                ?? []

        self.widgets = Self.dropRetired(left + right)
        save()
    }

    /// Silently discards widgets whose metric has been withdrawn. The enum
    /// cases still exist so decoding never fails; this is where they stop being
    /// shown. See `RetiredMetrics`.
    private static func dropRetired(_ configs: [WidgetConfig]) -> [WidgetConfig] {
        collapseCodexRateLimitWindows(configs.filter { $0.metric.isSelectable })
    }

    /// Codex used to expose two rate-limit windows (5 hours at quotaIndex 0,
    /// 7 days at 1). Upstream dropped the 5-hour window, so both indexes now
    /// resolve to the same quota and saved configs show the identical value
    /// twice. Normalise the index and keep one.
    private static func collapseCodexRateLimitWindows(_ configs: [WidgetConfig]) -> [WidgetConfig] {
        var seenCodexRateLimit = false
        return configs.compactMap { config in
            guard config.service == "codex", config.metric == .remainingTime else { return config }
            guard !seenCodexRateLimit else { return nil }
            seenCodexRateLimit = true
            guard config.quotaIndex != 0 else { return config }
            return WidgetConfig(
                id: config.id,
                service: config.service,
                metric: config.metric,
                style: config.style,
                quotaIndex: 0
            )
        }
    }

    private static func loadArray(forKey key: String, decoder: JSONDecoder) -> [WidgetConfig]? {
        guard let d = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? decoder.decode([WidgetConfig].self, from: d)
    }

    private static func migrateV1(_ widgets: [WidgetConfig]) -> [WidgetConfig] {
        widgets.map { w in
            if w.service == "codex", w.metric == .balance {
                return WidgetConfig(id: w.id, service: w.service, metric: .sessionTokens, style: w.style)
            }
            return w
        }
    }

    func resetToDefaults() {
        widgets = Self.defaultWidgets
    }

    private func save() {
        if let d = try? JSONEncoder().encode(widgets) {
            UserDefaults.standard.set(d, forKey: Keys.v3)
        }
    }

    static let defaultWidgets: [WidgetConfig] = [
        WidgetConfig(service: "claude", metric: .remainingTime,  style: .bar),
        WidgetConfig(service: "claude", metric: .sessionTokens,  style: .text),
        WidgetConfig(service: "codex",  metric: .remainingTime,  style: .bar, quotaIndex: 0),
    ]
}
