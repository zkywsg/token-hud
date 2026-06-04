# 2026-05-31 Notch Collapsed Status

## 背景

用户反馈 APP 启动后会看到两个 HUD 样式窗口，并且拖动吸附到刘海后，收起态会露出一条向屏幕内容区延伸的黑色长条。目标调整为：收起时只在刘海左右两侧保留少量用量状态，左侧显示进度条，右侧显示百分比；鼠标 hover 后再从刘海区域展开完整面板。

## 关键决策

- 收起态不再复用 `NotchFusionView`，因为它会绘制刘海下方 body 区域，即使内容透明也会留下黑色背景。
- 收起态新增专用 `NotchCollapsedStatusView`，只绘制菜单栏高度内的左右状态耳朵，中间 notch gap 保持透明。
- collapsed frame 高度改为菜单栏高度，不再包含 `collapsedBodyHeight`。
- collapsed frame 宽度改为 `notchGapWidth + collapsedStatusEarWidth * 2`，避免收起时变成长条。
- 拖拽吸附释放后直接进入 collapsed 状态，hover 时再展开，避免一吸附就弹出完整大框。
- 启动默认模式改为 detached，并移除 restore 时因鼠标已经停在刘海区域而自动展开的逻辑，降低启动双窗口感。

## 修改范围

- `Sources/token_hudCore/NotchGeometryCalculator.swift`
  - 新增 `collapsedStatusEarWidth`。
  - 调整 collapsed frame 的宽度、高度和 y 坐标。
- `Tests/token_hudCoreTests/NotchGeometryCalculatorTests.swift`
  - 更新 collapsed frame 相关测试，覆盖菜单栏高度、紧凑宽度和 expanded 差异。
- `token_hud/Overlay/NotchCollapsedView.swift`
  - 新增 collapsed 专用状态视图，左侧进度条、右侧百分比。
- `token_hud/Overlay/NotchHostRootView.swift`
  - `.collapsed` 改为渲染 `NotchCollapsedStatusView`。
- `token_hud/Overlay/NotchHostPanelManager.swift`
  - 吸附后直接进入 collapsed。
  - 默认 restore 模式改为 detached。
  - 移除 restore 后自动展开。

## 验证结果

- `swift test --filter NotchGeometryCalculator` 通过。
- `swift test` 通过，99 个测试通过。
- `xcodebuild -project ../token_hud.xcodeproj -scheme token_hud -destination 'platform=macOS' build` 通过。

## 后续注意

- 仍需要在带刘海 MacBook 真机上验证：收起态是否只显示左右状态，不向屏幕内容区露出黑条。
- 如果右侧状态耳朵与系统菜单栏图标冲突，下一步应使用 `auxiliaryTopLeftArea` / `auxiliaryTopRightArea` 做更精细的避让。
- SkyLight / CGS 私有 Space 路线未在本轮改动；如果菜单栏层级仍被系统限制，需要单独排查窗口层级和 Space delegation。
