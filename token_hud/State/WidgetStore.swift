// token_hud/State/WidgetStore.swift
import Foundation
import Observation

@Observable
@MainActor
final class WidgetStore {
    var leftWidgets: [WidgetConfig] = [
        WidgetConfig(service: "claude", metric: .remainingTime, style: .ring),
        WidgetConfig(service: "openai",  metric: .balance,       style: .bar),
    ]
    var rightWidgets: [WidgetConfig] = [
        WidgetConfig(service: "claude", metric: .resetCountdown, style: .text),
        WidgetConfig(service: "claude", metric: .sessionTokens,  style: .aggregate),
    ]
}
