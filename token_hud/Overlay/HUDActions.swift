// token_hud/Overlay/HUDActions.swift
import Foundation

/// HUD control-button actions, delivered as notifications so the display
/// surfaces (focus card etc.) stay decoupled from fetchers, the settings
/// window, and the panel lifecycle. Observers live in `AppDelegate`, the
/// fetchers, and `NotchHostPanelManager`.
extension Notification.Name {
    /// Trigger a silent (non-interactive) data refresh across fetchers.
    static let hudRefreshNow = Notification.Name("TokenHUD.refreshNow")
    /// Open the Settings window.
    static let hudOpenSettings = Notification.Name("TokenHUD.openSettings")
    /// Collapse / dismiss the currently shown HUD surface.
    static let hudCollapse = Notification.Name("TokenHUD.collapseHUD")
}
