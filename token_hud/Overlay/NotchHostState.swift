import CoreGraphics
import SwiftUI

/// Observable state shared between NotchHostPanelManager and SwiftUI views.
@Observable
final class NotchHostState {
    var mode: NotchHostMode = .detached
    var geometry: NotchGeometry?
    var frames: NotchFrames?
    var screenFrame: CGRect = .zero
    var expansionProgress: CGFloat = 0

    /// Gap width within the collapsed window (0 when no notch).
    var gapWidth: CGFloat = 0

    var isHosted: Bool { mode == .collapsed || mode == .expanded }
    var isCollapsed: Bool { mode == .collapsed }
    var isExpanded: Bool { mode == .expanded }
    var isDetached: Bool { mode == .detached }

    var menuBarHeight: CGFloat { geometry?.menuBarHeight ?? 0 }
    var collapsedHeight: CGFloat { frames?.collapsed.height ?? 0 }
    var expandedHeight: CGFloat { frames?.expanded.height ?? 0 }
    var hasNotch: Bool { geometry?.hasNotch ?? false }
}
