# Startup Collapse And Accessibility Prompt

## Context

用户反馈启动后顶部浮窗会以大尺寸状态卡在屏幕顶部，文字被刘海遮挡；同时系统反复弹出辅助功能授权提示。

## Root Cause

- 启动恢复逻辑默认 `notchHostMode` 缺失时按 `detached` 恢复，和产品主形态 hosted HUD 不一致。
- 历史 detached frame 虽然已有 stale guard，但恢复策略分散在 `NotchHostPanelManager.restoreState()` 内，缺少纯逻辑测试保护。
- hosted 恢复时窗口 frame 显示和 `expansionProgress` 设置顺序不够保守，存在首帧显示大面板的风险。
- `AppDelegate.applicationDidFinishLaunching` 无条件调用 `GlobalHotkeyManager.requestAccessibility()`。
- `GlobalHotkeyManager.setup()` 无论是否配置全局快捷键都会安装 global key monitor，增加系统辅助功能提示触发概率。

## Decision

- 新增 `NotchRestorePolicy` 作为 core 纯逻辑恢复策略：
  - 没有 saved mode 时默认 `.hostedCollapsed`。
  - saved mode 为 `detached` 但 saved frame 靠近 hosted/notch surface 时恢复 `.hostedCollapsed`。
  - 只有远离顶部工作区的 detached frame 才恢复 detached。
- `restoreState()` 先设置 `hostState.mode = .collapsed` 和 `expansionProgress = 0`，再显示 overlay，避免启动首帧大面板。
- 启动时不再主动请求辅助功能权限。
- Global hotkey manager 只在“已配置快捷键且已授权辅助功能”时安装 global monitor；local monitor 保留用于 app 前台。
- 设置页浮动面板区域在需要时显示“授权”按钮，只有用户点击时才触发系统辅助功能提示。

## Verification

- `swift test --filter NotchGeometryCalculator`：50 tests passed。
- `swift test --filter Widget`：37 tests passed。
- `swift test`：150 tests passed。
- `xcodebuild -project token_hud.xcodeproj -scheme token_hud -destination 'platform=macOS' build`：BUILD SUCCEEDED。

## Notes

- 本轮没有清空所有 detached 状态；远离顶部的自由浮窗仍会保留恢复能力。
- 如果用户刻意把 detached 浮窗贴近刘海，重启会更倾向恢复 hosted collapsed，这是为避免启动遮挡刘海做的取舍。
- 如果后续仍有密码弹窗，需要用新截图区分是否来自 Keychain，而不是辅助功能权限。
