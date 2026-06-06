# Codex Auth Entry

## 背景

Settings 平台页之前只展示 Codex 本地认证状态，并提示用户运行 `codex login`。这对状态展示是安全的，但缺少可操作入口，用户在 Codex/OpenAI 认证过期或需要切换账号时无法从 Settings 重新配置。

## 改动

- `ProviderResetAction` 增加 `localAuth`。
- Codex capability 从只支持 `serviceData` 改为支持 `localAuth + serviceData`。
- Codex 认证区域新增：
  - `重新登录 Codex`：使用 Terminal 执行 `codex login`。
  - `打开 ~/.codex`：打开或创建 Codex 本地配置目录。
- Codex reset 区域新增：
  - `移除本地认证`：二次确认后只删除 `~/.codex/auth.json`。
- 删除认证不会删除 `~/.codex/sessions`。

## 决策

- 不把 Codex auth 放进 token-hud 的 Keychain。Codex CLI 仍然拥有自己的登录态。
- Settings 只提供入口和受控删除，不接管 Codex 登录流程。
- Terminal 自动执行失败时退化为复制 `codex login` 并打开 Terminal。

## 验证

- `swift test`：133 个测试通过。
- `xcodebuild -project token_hud.xcodeproj -scheme token_hud -destination 'platform=macOS' build`：通过。

## 后续注意

- 如果 macOS 拦截 AppleScript 控制 Terminal，需要用户授权自动化权限；失败时用户仍可从剪贴板粘贴命令。
- `移除本地认证` 会让 Codex CLI 退出登录，必须保持 destructive 确认。
