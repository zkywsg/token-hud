# Keychain Status Check Silent

## Context

用户反馈在 Settings 小组件页会连续弹出 macOS Keychain 授权框，内容为 `token_hud` 想访问钥匙串 `com.tokenHud.sessionKey` 中的机密信息。用户指出合理体验应是首次使用时授权一次，而不是点击拒绝后连续弹出多次。

## Root Cause

本轮排查确认当前挂载的 Settings 路径是：

- `SettingsWindow` -> `WidgetListEditor`
- `WidgetListEditor.task` -> `reloadCredentialSnapshot()`
- `reloadCredentialSnapshot()` -> `KeychainHelper.hasClaudeSessionKey()` 等 `has...` 状态检查

平台页 `PlatformListView.task` 也有相同的 credential snapshot 路径。旧的 `PlatformRowView` / `ServiceConfigView` 仍在 target 中，但当前 `SettingsWindow` 未挂载它们，因此这次截图更可能来自 snapshot 状态检查。

此前修复已经避免 UI body 直接读取 secret data，但 `KeychainHelper.exists(account:)` 没有设置非交互 `LAContext`。对于旧签名或 ACL 需要确认的 Keychain item，存在性查询也可能触发系统授权。用户点击“拒绝”只拒绝当前一次 `SecItemCopyMatching`，后续页面任务、快照刷新或多项凭据检查仍会继续发起新的访问，所以表现为连续弹窗。

## Fix

- 新增 core 策略 `KeychainAccessPolicy`：
  - `.statusCheck` 永远不允许用户交互。
  - `.secretRead(allowUserInteraction:)` 遵循调用方显式参数。
- `KeychainHelper.load(account:allowUserInteraction:)` 使用该策略判断是否设置非交互 `LAContext`。
- `KeychainHelper.exists(account:)` 设置 `LAContext.interactionNotAllowed = true`，使所有 `has...` 状态检查静默执行。
- 保留 `allowUserInteraction: true` 的主动读取路径，避免破坏用户主动授权刷新真实 key/cookie 的能力。

## Verification

- TDD RED：`swift test --filter KeychainAccessPolicy` 先因缺少策略类型失败。
- `swift test --filter KeychainAccessPolicy`：2 tests passed.
- `swift test`：169 tests passed.
- `xcodebuild -project token_hud.xcodeproj -scheme token_hud -destination 'platform=macOS' build`：BUILD SUCCEEDED.

## Manual Checks Still Needed

- 打开 Settings 小组件页时不再连续弹 Claude session key 授权框。
- 切换 Settings tab 或重复打开小组件页时不再重复弹。
- 用户主动刷新需要真实 Keychain secret 的平台时，仍能按需弹出授权。
