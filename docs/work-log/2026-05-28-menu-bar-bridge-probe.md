# Menu Bar Bridge Probe

## 背景

原先通过主 `NSPanel` 上推来进入顶部导航栏的路线已经确认不可行：panel 可以负责刘海下方内容，但不能可靠绘制到 macOS 菜单栏内部。因此本轮改为验证一个新的关键假设：使用公开的 `NSStatusBar` / `NSStatusItem` API 是否能在菜单栏层绘制一段黑色 bridge。

## 关键操作

- 新增 `Overlay/MenuBarBridgeProbe.swift`。
- 在 `AppDelegate` 中持有 `MenuBarBridgeProbe`，启动时调用 `setupIfNeeded()`，退出时调用 `teardown()`。
- `MenuBarBridgeProbe` 创建一个 120pt 的 `NSStatusItem`，并将其 button 背景设置为黑色测试条。
- probe 只在主屏幕存在 `auxiliaryTopLeftArea` 和 `auxiliaryTopRightArea` 时启用，避免非刘海屏幕误显示。
- 同步更新 Xcode 工程，将 `MenuBarBridgeProbe.swift` 加入 app target sources。

## 验证结果

- `swift test` 通过，97 个测试通过。
- `xcodebuild -project ../token_hud.xcodeproj -scheme token_hud -destination 'platform=macOS' build` 通过。

## 待验证事项

- 需要在带刘海 MacBook 上实际启动 app，确认 120pt 黑色测试条是否出现在菜单栏内部。
- 需要确认测试条是否能靠近刘海区域，还是只能被系统状态栏布局放到右侧状态项区域。
- 如果该公开 API 只能作为普通状态项显示，下一步应记录限制，并把视觉目标调整为“菜单栏状态项近似融合 + 刘海下方 body”，而不是继续尝试让普通 panel 进入菜单栏。

## 后续注意

这轮只是 spike，不应直接把业务 widget 迁入 `NSStatusItem`。只有当真机视觉验证证明 menu bar layer 可用后，才进入正式的左右 bridge layer 设计。
