# Notch Docking

## 背景

本次实现浮动面板的刘海区域吸附基础能力。目标是当用户把浮窗拖到屏幕顶部中心附近时，松开鼠标后自动贴合到顶部刘海/HUD 区域，同时保留自由浮窗模式。

## 关键操作

- 新增 `Sources/token_hudCore/PanelDockingCalculator.swift`，把吸附检测和目标 frame 计算放到 core 层纯逻辑中。
- 新增 `Tests/token_hudCoreTests/PanelDockingCalculatorTests.swift`，覆盖顶部中心吸附、偏离不吸附、阈值边界、safe area 恢复边界、超宽面板 clamp。
- 修改 `token_hud/Overlay/FloatingPanelManager.swift`：
  - 使用 `NSEvent.addLocalMonitorForEvents(matching: .leftMouseUp)` 在鼠标释放后执行吸附判断。
  - 保存 `floatingPanelFrame` 和 `floatingPanelDocked`。
  - 恢复 docked 状态时直接用 `notchDockedFrame(...)` 重新计算当前屏幕上的吸附位置。
  - resize 时解除 docked 状态。
- 修改 `project.yml`，排除 `token_hud/.superpowers`，避免 brainstorm/mockup 临时文件进入 Xcode project。
- 同步更新 `token_hud.xcodeproj/project.pbxproj`，加入 `PanelDockingCalculator.swift`，并清理临时资源引用。

## 关键决策

- 第一版不使用私有刘海 API；用屏幕顶部中心、`NSScreen.safeAreaInsets.top` 和阈值推断吸附区域。
- 吸附发生在 mouse up 后，而不是拖动过程中即时吸附，避免窗口动画和用户拖动手势互相抢控制。
- docked 状态恢复不再通过触发阈值判断，因为保存后的 docked frame 可能位于 safe area 下方，已经不满足“靠近屏幕顶边”的触发条件。
- 超宽面板保持原尺寸，但水平位置 clamp 到屏幕左边界，避免产生负 `minX`。

## 验证结果

- `swift test` 通过：74 个测试通过。
- `xcodebuild -project token_hud.xcodeproj -scheme token_hud -destination 'platform=macOS' build` 通过。
- `rg "superpowers|server.pid|widget-settings-layout" token_hud.xcodeproj/project.pbxproj project.yml` 检查结果只剩 `project.yml` 中的 `.superpowers` exclude，pbxproj 不再包含临时文件。

## 后续注意事项

- 后续可增加吸附态视觉样式，例如隐藏 resize grip、使用更贴近刘海 HUD 的背景形状。
- 可加入磁吸预览，在用户拖近顶部中心时显示半透明目标位置。
- 当前 mouse up 通过 local event monitor 捕捉；如果后续发现特殊拖动路径不稳定，可考虑自定义拖动区域或更细的 window event 处理。
- 多屏策略仍可继续打磨，尤其是外接屏没有刘海时是否启用顶部中心吸附。
