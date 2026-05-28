# Notch Fusion State

## 背景

在基础刘海吸附能力完成后，本次继续优化浮动面板与刘海区域的融合感。目标是在面板吸附到刘海时呈现明确的 docked 视觉状态，并允许用户把面板向下拖离后恢复为普通自由浮窗。

## 关键操作

- 新增 `token_hud/Overlay/PanelDockState.swift`，作为 `FloatingPanelManager` 与 `FloatingPanelView` 之间的轻量 observable 状态通道。
- 扩展 `PanelDockingCalculator`：
  - 新增 `detachThreshold`。
  - 新增 `shouldDetachFromDock(panelFrame:dockedFrame:)`，用于判断 docked 面板是否被拖离。
- 扩展 `PanelDockingCalculatorTests`，新增拖离相关测试：
  - 向下拖离超过阈值会 detach。
  - 小幅向下拖动不会 detach。
  - 水平偏离超过阈值会 detach。
  - 向上拖动不会 detach。
- 修改 `FloatingPanelManager`：
  - 持有 `PanelDockState` 并注入 SwiftUI 环境。
  - 记录 `dockedFrame`，在 docked 状态的 `windowDidMove` 中即时判断拖离。
  - 拖离时立即切换 `isDockedVisual = false`，释放鼠标后继续执行已有吸附判断。
  - `NSPanel` 背景改为 clear，避免 AppKit 背景和 SwiftUI 背景叠加。
- 修改 `FloatingPanelView`：
  - docked 状态使用顶部直角、底部圆角的黑色背景，让面板更像刘海向下延伸。
  - free 状态保留普通圆角半透明浮窗外观。
  - docked 状态隐藏 resize grip，free 状态保留 resize grip。

## 关键决策

- docked/free 视觉状态通过 `PanelDockState` 从 AppKit manager 单向驱动 SwiftUI view，避免把 manager 本身塞进 view 环境。
- 拖离检测仍放在 core calculator 中，保持几何行为可测试。
- docked 状态只保存稳定状态；拖离过程中的视觉状态不单独持久化。
- docked 状态不支持 resize grip，避免视觉上看起来仍是普通浮窗。用户仍可通过拖拽背景把面板拉下来。

## 验证结果

- `swift test` 通过：78 个测试通过。
- `xcodebuild -project token_hud.xcodeproj -scheme token_hud -destination 'platform=macOS' build` 通过。
- `rg "superpowers|server.pid|widget-settings-layout" token_hud.xcodeproj/project.pbxproj project.yml` 检查结果只剩 `project.yml` 中的 `.superpowers` exclude，pbxproj 不包含临时 mockup 文件。

## 后续注意事项

- 还可以继续增强磁吸预览，在接近刘海但尚未释放时显示目标位置。
- 多屏策略仍可打磨，尤其是外接屏无刘海时是否启用同样的顶部中心融合态。
- 如果发现 local mouse-up monitor 在某些拖动路径下不稳定，可考虑自定义拖动区域或更细的 window event 处理。
- 后续替换 README 截图时，应分别展示 free 和 docked 两种状态。
