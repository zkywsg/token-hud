# Dual Window Notch Overlay

## 背景

此前单窗口路线把同一个 `NSPanel` 同时用于 detached 浮窗、吸附态 collapsed 和展开态 expanded。真机截图显示该路线会被压回屏幕工作区，导致刘海/菜单栏上方仍然空白，视觉上无法与刘海融合。

本轮改为双窗口架构：detached floating window 负责普通浮窗体验，dedicated notch overlay window 负责吸附后的刘海区域视觉。

## 关键决策

- 不再移动同一个窗口进入刘海区域。
- detached 状态保留可拖拽、可 resize 的 `FloatingPanelView`。
- hosted 状态使用独立 borderless / nonactivating overlay `NSPanel`。
- 吸附时保存 detached frame，隐藏 detached window，显示 overlay window。
- 脱离时隐藏 overlay window，恢复 detached window。
- `NSStatusItem` / `MenuBarBridgeProbe` 继续只作为诊断或增强路径，默认关闭，不作为主实现。

## 关键实现

- `NotchHostPanelManager` 同时维护 `detachedWindow` 和 `overlayWindow`。
- `NotchGeometryCalculator` 增加 overlay frame 语义：
  - collapsed overlay frame 包含 menu bar bridge + collapsed body。
  - expanded overlay frame 包含 menu bar bridge + expanded body。
  - notched display 上允许 overlay frame 的 `maxY` 对齐到辅助刘海区域推导出的顶部边界。
- `NotchFusionLayout` 增加 `topBridge`，用于绘制菜单栏/刘海高度内的黑色融合层。
- `NotchFusionView` 绘制顺序改为 top bridge 在上，body 在菜单栏高度下方，内容在展开中后段淡入。
- `windowDidMove` / `windowDidResize` 保持主 actor delegate 处理，避免 Swift 6 并发警告。

## 验证

- `swift test` 通过，98 个测试通过。
- `xcodebuild -project ../token_hud.xcodeproj -scheme token_hud -destination 'platform=macOS' build` 通过。

## 后续注意

- 必须在带刘海 MacBook 真机上确认 overlay 是否确实进入菜单栏/刘海视觉高度。
- 如果真机仍然看不到刘海左右两侧 top bridge，下一步应检查 window level、screen 选择、Spaces / fullscreen collection behavior，以及 Boring Notch / Atoll 类项目是否使用了额外窗口层级策略。
- 不应回退到单窗口 frame 魔改路线；该路线已经被截图证明无法稳定达成目标视觉。
