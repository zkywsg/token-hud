// token_hud/State/AppFilterStore.swift
import Foundation
import Observation

struct AllowedApp: Codable, Identifiable, Hashable {
    var id: String { bundleIdentifier }
    let bundleIdentifier: String
    let name: String
}

@Observable @MainActor
final class AppFilterStore {

    private static let filterEnabledKey = "appFilterEnabled"
    private static let allowedAppsKey   = "allowedApps"

    var isFilterEnabled: Bool {
        didSet { UserDefaults.standard.set(isFilterEnabled, forKey: Self.filterEnabledKey) }
    }

    var allowedApps: [AllowedApp] {
        didSet { save() }
    }

    init() {
        isFilterEnabled = UserDefaults.standard.bool(forKey: Self.filterEnabledKey)
        if let data = UserDefaults.standard.data(forKey: Self.allowedAppsKey),
           let apps = try? JSONDecoder().decode([AllowedApp].self, from: data) {
            allowedApps = apps
        } else {
            allowedApps = []
        }
    }

    func addApp(_ app: AllowedApp) {
        guard !allowedApps.contains(where: { $0.bundleIdentifier == app.bundleIdentifier }) else { return }
        allowedApps.append(app)
    }

    func removeApp(_ bundleID: String) {
        allowedApps.removeAll { $0.bundleIdentifier == bundleID }
    }

    /// Returns true when filter is disabled OR bundleID is in the whitelist.
    func isAllowed(_ bundleID: String?) -> Bool {
        guard isFilterEnabled else { return true }
        guard let bundleID else { return false }
        return allowedApps.contains { $0.bundleIdentifier == bundleID }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(allowedApps) {
            UserDefaults.standard.set(data, forKey: Self.allowedAppsKey)
        }
    }
}
