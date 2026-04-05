// token_hud/State/WidgetStore.swift
import Foundation
import Observation

@Observable
@MainActor
final class WidgetStore {

    var leftWidgets: [WidgetConfig] {
        didSet { save() }
    }

    var rightWidgets: [WidgetConfig] {
        didSet { save() }
    }

    private enum Keys {
        static let left  = "leftWidgets_v1"
        static let right = "rightWidgets_v1"
    }

    init() {
        let decoder = JSONDecoder()
        if let d = UserDefaults.standard.data(forKey: Keys.left),
           let v = try? decoder.decode([WidgetConfig].self, from: d) {
            self.leftWidgets = v
        } else {
            self.leftWidgets = Self.defaultWidgets(side: .left)
        }
        if let d = UserDefaults.standard.data(forKey: Keys.right),
           let v = try? decoder.decode([WidgetConfig].self, from: d) {
            self.rightWidgets = v
        } else {
            self.rightWidgets = Self.defaultWidgets(side: .right)
        }
    }

    private func save() {
        let encoder = JSONEncoder()
        if let d = try? encoder.encode(leftWidgets)  { UserDefaults.standard.set(d, forKey: Keys.left) }
        if let d = try? encoder.encode(rightWidgets) { UserDefaults.standard.set(d, forKey: Keys.right) }
    }

    private enum Side { case left, right }

    private static func defaultWidgets(side: Side) -> [WidgetConfig] {
        switch side {
        case .left:
            return [
                WidgetConfig(service: "claude", metric: .remainingTime, style: .ring),
                WidgetConfig(service: "openai",  metric: .balance,      style: .bar),
                WidgetConfig(service: "codex",   metric: .balance,      style: .bar),
            ]
        case .right:
            return [
                WidgetConfig(service: "claude", metric: .resetCountdown, style: .text),
                WidgetConfig(service: "claude", metric: .sessionTokens,  style: .aggregate),
            ]
        }
    }
}
