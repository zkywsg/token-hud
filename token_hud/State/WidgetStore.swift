// token_hud/State/WidgetStore.swift
import Foundation
import Observation

@Observable
@MainActor
final class WidgetStore {

    var widgets: [WidgetConfig] {
        didSet { save() }
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
            self.widgets = v
            return
        }

        // 2. Migrate from v2 left+right
        let left = Self.loadArray(forKey: Keys.leftV2, decoder: decoder)
               ?? Self.loadArray(forKey: Keys.leftV1, decoder: decoder).map { Self.migrateV1($0) }
               ?? Self.defaultWidgets
        let right = Self.loadArray(forKey: Keys.rightV2, decoder: decoder)
                ?? Self.loadArray(forKey: Keys.rightV1, decoder: decoder).map { Self.migrateV1($0) }
                ?? []

        self.widgets = left + right
        save()
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
        WidgetConfig(service: "codex",  metric: .remainingTime,  style: .bar, quotaIndex: 1),
        WidgetConfig(service: "codex",  metric: .subscriptionStatus,  style: .text),
    ]
}
