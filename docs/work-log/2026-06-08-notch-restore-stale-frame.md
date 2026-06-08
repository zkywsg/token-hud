# 2026-06-08 Notch Restore Stale Frame

## 背景

用户反馈 App 一打开时，刘海/浮窗区域会出现一个重叠形状，而且视觉像旧版浮窗样式。

排查后确认旧 `NotchFusionView` / `NotchCollapsedView` / `NotchExpandedView` / `NotchEarView` 没有被继续引用。当前更可能的根因是启动恢复逻辑把贴近刘海或顶部 hosted surface 的历史 detached frame 当成普通自由浮窗恢复，导致 `FloatingPanelView` 的旧圆角卡片、阴影和 resize grip 出现在顶部。

## 关键决策

- 不把所有顶部附近 detached frame 都删除，避免误伤用户故意放在屏幕顶部的自由浮窗。
- 只针对明显像 hosted 残留的 frame：
  - top-center 落入 snap zone。
  - frame 与 expanded hosted surface 扩展 guard zone 相交。
  - frame 与刘海横向范围内的菜单栏 band 相交。
- 如果命中 stale frame，不再 fallback 到默认 detached 浮窗，而是恢复 hosted collapsed，避免启动时再次出现旧浮窗样式。

## 修改范围

- `Sources/token_hudCore/NotchGeometryCalculator.swift`
  - 新增 `shouldDiscardSavedDetachedFrame(...)`。
- `Tests/token_hudCoreTests/NotchGeometryCalculatorTests.swift`
  - 新增顶部 stale frame 识别测试。
  - 新增普通工作区 detached frame 不误判测试。
- `token_hud/Overlay/NotchHostPanelManager.swift`
  - `restoreState()` 使用新的 stale frame 判定。
  - stale frame 命中后恢复 hosted collapsed。
  - 增加 `[NotchDiagnostics] restore...` 日志，输出 saved mode、candidate frame、discard 决策和最终窗口可见性。

## 验证

- `swift test --filter NotchGeometryCalculator`：通过，47 个测试通过。
- `swift test --filter NotchSurfacePolicyTests`：通过，16 个测试通过。
- `swift test`：通过，146 个测试通过。
- `xcodebuild -project token_hud.xcodeproj -scheme token_hud -destination 'platform=macOS' build`：通过。

## 后续注意

- 如果用户仍看到两个窗口同时出现，下一步优先检查两个 `NSPanel` 共享 `NotchHostRootView` 的首帧渲染时序，必要时把 root view 按 window role 拆分。
- 如果用户希望自由浮窗可以贴在屏幕顶端常驻，需要进一步缩窄 stale guard zone，或提供显式“锁定为浮窗”状态。
