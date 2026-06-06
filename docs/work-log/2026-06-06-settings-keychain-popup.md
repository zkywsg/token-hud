# Settings Keychain Popup Fix

## 背景

用户反馈 Settings 里做各种操作时，macOS 会连续弹出 Keychain 授权框，需要输入多次密码，导致无法正常使用。

## 根因

上一轮 Settings 平台页重构后，Keychain 读取被放进了 SwiftUI 渲染路径：

- 左侧平台列表每个 row 会调用 `CredentialStatusReader.status(...)`。
- `CredentialStatusReader.status(...)` 直接调用 `KeychainHelper.load()`、`loadAPIKey(...)`、`loadMiMoConsoleCookie()`。
- 右侧 `PlatformCredentialPanel` 的 `body` 也直接调用 `KeychainHelper.load...` 来显示 masked secret。

SwiftUI 的 `body` 会因为选择、hover、刷新、布局变化频繁重算。macOS Keychain item 如果由旧签名创建、ACL 需要用户确认，频繁 `SecItemCopyMatching` 且 `kSecReturnData = true` 会触发连续授权弹窗。

## 修复

- 增加 `ProviderCredentialSnapshot`，UI 使用内存快照展示配置状态。
- `KeychainHelper` 增加 existence 查询：
  - `hasClaudeSessionKey()`
  - `hasAPIKey(for:)`
  - `hasMiMoConsoleCookie()`
  - 这些查询使用 `kSecReturnAttributes`，不读取 secret data。
- `PlatformListView` 打开时集中生成一次 snapshot。
- 左侧平台列表和右侧详情只读 snapshot，不再在 `body` 中读取 Keychain secret。
- 保存/删除凭据后显式 reload snapshot。
- UI 不再为了显示密钥后四位读取 secret，统一显示 `••••••••`。

## 验证

- `swift test`：133 个测试通过。
- `xcodebuild -project token_hud.xcodeproj -scheme token_hud -destination 'platform=macOS' build`：通过。

## 后续注意

- 不要在 SwiftUI `body`、computed view property、row rendering 中调用 `KeychainHelper.load...`。
- 如果需要展示“是否已配置”，优先使用 metadata existence 查询或上层缓存。
- 如果需要真实 secret，只在用户主动保存/刷新/发起平台请求时读取。
- 如果旧 Keychain item 仍因为 ACL 弹一次，用户可以点“始终允许”，或在 Settings 里重置认证后重新保存。
