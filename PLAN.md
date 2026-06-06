# 短期计划

这个文件跟踪当前项目正在进行的实现工作。保持内容小而可执行；可长期保留的决策沉淀到 `docs/`。

## 当前重点：Settings 已配置可见性、小组件默认添加与刘海收起态配置（待确认）

### 问题

用户反馈当前 Settings 和小组件体验还有三类问题：

- Settings 里不够清楚哪些平台已经配置好，用户需要自己判断绿色状态点和标签含义。
- 已配置平台对应的小组件没有被优先展示或自动加入当前小组件列表，导致用户配置完平台后还要再去找组件。
- 小组件整体字体和颜色“不好看”，当前 Settings 预览、添加卡片和 HUD widget 的视觉层级偏弱。
- 刘海 hosted 收起态只从 `WidgetStore.widgets` 中取第一个可计算百分比的组件，用户无法单独调整左侧进度条、右侧百分比显示来源。

本轮已阅读：

- `docs/work-log/2026-05-10-widget-settings-preview.md`
- `docs/work-log/2026-06-04-notch-compact-pills.md`
- `docs/notch-dynamic-island-implementation-reference.md`
- `Settings/WidgetListEditor.swift`
- `Settings/PlatformListView.swift`
- `State/WidgetStore.swift`
- `Overlay/NotchHostedSurfaceView.swift`

关键约束：

- 刘海收起态应继续保持“单一 hosted surface + 左右 compact slot”，不能回到两个独立窗口或整条黑条。
- 收起态可见内容只能是少量摘要：左侧一小格进度/状态，右侧一小格数字/文本。
- Settings 不能在 SwiftUI `body` 里频繁读取 Keychain；已配置判断继续使用 `ProviderCredentialSnapshot`。

### 本轮目标

- Settings → 平台页显式展示“已配置”平台，并把已配置平台排在平台列表更靠前的位置或提供清晰分组。
- Settings → 小组件页默认优先展示/加入当前已配置平台的推荐组件：
  - 对已有用户小组件列表，提供一键“添加已配置平台推荐组件”，避免无提示地重排用户现有配置。
  - 对新用户或空列表，自动填充已配置平台的推荐组件；如果没有已配置平台，则保留现有默认。
- 优化小组件视觉：
  - 改善 Settings 预览区、已添加列表、添加卡片和 HUD widget 的字体层级、颜色、对比度。
  - 使用更克制的暗色表面、状态色和 monospaced digits，避免大面积单色或廉价渐变。
- 增加“刘海收起态显示”配置：
  - 左侧 slot 可选择显示来源：自动、指定小组件、指定平台指标。
  - 右侧 slot 可选择显示来源：自动、指定小组件、指定平台指标。
  - 配置立即影响 `NotchHostedSurfaceView` 的 compact 左右 slot。

### 实施步骤

1. **抽出推荐组件和已配置匹配规则**
   - 将 `WidgetListEditor.swift` 中的 `widgetCapabilities` / presets 规则整理为可复用 helper。
   - 基于 `ProviderCredentialSnapshot` 判断已配置平台，生成推荐组件列表。
   - 推荐优先级：
     - Codex：5h rate-limit bar、7d rate-limit bar、订阅状态。
     - Claude：剩余时间、会话 Token。
     - DeepSeek：余额。
     - MiniMax：Token Plan / remains 相关组件。
     - MiMo：Credit 用量、套餐名、到期时间。
     - OpenAI/Gemini/Anthropic：如果仅普通 API key 可验证但不可稳定查用量，默认只显示“已配置但用量能力有限”的标识，不强行添加无数据组件。

2. **Settings 平台页强化已配置可见性**
   - 平台侧边栏增加“已配置 / 未配置”视觉分组或排序。
   - row 内保留凭据状态与数据状态，但让“已配置”更直观，例如绿色标签、已配置数量摘要。
   - 不在 row 渲染时读取 Keychain，只使用现有 `credentialSnapshot`。

3. **Settings 小组件页默认添加和推荐入口**
   - `WidgetListEditor` 接入 `ProviderCredentialSnapshot` 或等价 snapshot。
   - 顶部显示“已配置平台推荐组件”区域，放在添加组件之前。
   - 增加按钮：
     - “添加已配置推荐”
     - “仅补齐缺失推荐”
   - 空小组件列表首次打开时自动补齐已配置平台推荐；避免覆盖用户已有列表。

4. **小组件视觉重整**
   - 调整 `WidgetRenderer` 及 `BarWidget` / `TextWidget` / `AggregateWidget` 等子组件的字号、字重、透明度、状态色。
   - Settings 预览区使用更像真实 HUD 的尺寸和背景，减少粗糙渐变。
   - 添加卡片改为更清晰的信息结构：平台、指标、样式、是否已配置/是否可用。
   - 保证小尺寸下文本不溢出，百分比和数字使用 `monospacedDigit()`。

5. **新增刘海收起态配置模型**
   - 新增轻量配置，例如：
     - `notchCollapsedLeadingSource`
     - `notchCollapsedTrailingSource`
   - 建议用 JSON 字符串或明确 enum rawValue 存入 `UserDefaults`，避免破坏 `WidgetConfig` 持久化格式。
   - 支持来源：
     - `auto`
     - `widget:<uuid>`
     - `metric:<service>:<metric>:<quotaIndex>`

6. **Settings 增加收起态配置 UI**
   - 在小组件页或通用外观页新增“刘海收起态”区域。
   - 左右两个 slot 各一个 Picker：
     - 自动
     - 当前小组件列表中的组件
     - 已配置平台推荐指标
   - 提供一个 compact 预览，直接看到左侧进度条和右侧百分比/文本。

7. **接入 `NotchHostedSurfaceView`**
   - `NotchCollapsedStatusComputer` 改为接收 collapsed 配置。
   - 左侧输出 `fraction`，右侧输出 `text`；不再假设左右都来自同一个自动 fraction。
   - 保留自动回退：配置的组件无数据时，回退到当前自动逻辑，避免收起态空白。

8. **测试**
   - 为推荐组件生成逻辑补测试：
     - 已配置 Codex/DeepSeek/MiMo 时生成对应推荐。
     - OpenAI/Gemini/Anthropic 普通 key 不自动生成无数据组件。
     - 已有组件不重复添加。
   - 为刘海收起态计算补测试：
     - auto 与指定 widget 的输出。
     - 指定 widget 无数据时回退 auto。
     - 左右 slot 可分别配置。

### 验证

- `swift test --filter Widget`
- `swift test --filter ProviderCapability`
- `swift test --filter NotchSurfacePolicy`
- `swift test`
- `xcodebuild -project token_hud.xcodeproj -scheme token_hud -destination 'platform=macOS' build`
- 手动验证：
  - Settings → 平台页能一眼看到哪些平台已配置。
  - Settings → 小组件页最前面能看到已配置平台推荐组件。
  - 空小组件列表会自动加入已配置平台推荐组件；已有列表不会被覆盖。
  - 点击“补齐推荐”不会重复添加已有组件。
  - 小组件视觉在 Settings 预览、展开 HUD、刘海收起态都更统一。
  - 刘海收起态左右 slot 可分别调整，hover 展开/收起逻辑不回归。

### 风险

- 自动添加组件如果过于激进，会打乱用户现有配置；本轮只在空列表自动填充，已有列表用明确按钮补齐。
- 如果把 OpenAI/Gemini/Anthropic 普通 API key 也自动生成用量组件，可能继续出现“已配置但无数据”的困惑；本轮默认不自动添加这些不稳定用量来源。
- 刘海收起态可配置项过多会让 Settings 复杂；第一版只做左右 slot 来源选择，不做字体、颜色、宽度等细粒度调节。
- 视觉优化会影响多个 widget 子组件，需要防止小尺寸下文本溢出或导致刘海 compact slot 变宽。

---

## 当前重点：修复 MiniMax 无 Token Plan 时误显示查询异常（已实现，待手动体验验证）

### 问题

用户反馈 MiniMax 显示“查询异常”。

本轮排查确认：

- 当前 `~/.token-hud/state.json` 中 MiniMax 数据为：
  - `"label": "MiniMax"`
  - `"error": "no active token plan subscription"`
  - `"quotas": []`
- `ProviderDataStatus.status(for:)` 目前只识别：
  - network
  - invalid api key / 403
  - expired
  - no sessions
  - `ProviderQueryError.*` 规范错误码
- `"no active token plan subscription"` 不是规范错误码，也不匹配现有字符串规则，所以落入 `.error`，UI 显示“查询异常”。
- 结合 `docs/model-usage-query-practices.md`，MiniMax 的真实业务边界是：
  - Token Plan key 才能查 `GET https://www.minimax.io/v1/token_plan/remains`。
  - 普通 Open Platform key 只能验证 `/v1/models`，不能代表有 Token Plan 套餐。
  - “no active token plan subscription” 应该是“无套餐/用量不支持”或“暂无套餐数据”，不应是平台异常。

### 本轮目标

- MiniMax 遇到 `no active token plan subscription` 时，不再显示红色“查询异常”。
- fetcher 不再把这类业务文案原样写进 `state.json`，改为规范错误码 `usageUnsupported`。
- 对已有 state 中的 legacy 字符串做兼容，用户不需要手动清空数据。
- 保留真正异常的语义：
  - `Invalid API key` => 权限不足/凭据无效。
  - network error => 网络错误。
  - parse error / 未知业务错误 => 查询异常。

### 实施步骤

1. **补状态分类回归测试**
   - 在 `ProviderCapabilityTests.serviceDataStatusClassifiesLegacyFetcherErrorStrings` 增加：
     - `Service(error: "no active token plan subscription")` 应映射为 `.usageUnsupported`。
   - 可选增加大小写/标点兼容，例如包含 `token plan subscription` 的文案。

2. **修状态解析兼容**
   - 在 `ProviderDataStatus.status(for:)` 中识别：
     - `no active token plan subscription`
     - 或更泛化的 `token plan subscription`
   - 映射为 `.usageUnsupported`。

3. **修 MiniMax fetcher 写入值**
   - 在 `fetchMiniMax()` 处理 `base_resp.status_msg` 时，新增判断：
     - 如果 message 表示没有 active token plan subscription，则返回：
       - `Service(label: "MiniMax", quotas: [], currentSession: nil, error: ProviderQueryError.usageUnsupported.rawValue)`
   - `fetchMiniMaxViaModels()` 如果普通 key 验证成功但没有 Token Plan remains，也应返回 `usageUnsupported`，而不是 `error: nil` 导致“暂无数据”语义不明确。

4. **文案校准**
   - `ProviderDataStatus.usageUnsupported.detail` 当前是泛用文案，本轮可先保持；如果需要更准确，后续再做 provider-specific detail。
   - Settings 的 MiniMax 帮助文案已经写明“Token Plan key 可查询 remains；普通 key 只做调用验证”，本轮不改大布局。

5. **验证**
   - `swift test --filter ProviderCapability`
   - `swift test --filter StateModel`
   - `swift test`
   - `xcodebuild -project token_hud.xcodeproj -scheme token_hud -destination 'platform=macOS' build`
   - 手动验证：
     - 当前已有 `"no active token plan subscription"` state 时，MiniMax 显示“用量不支持”，不再显示“查询异常”。
     - 点击 MiniMax 刷新后，`state.json` 中 MiniMax error 更新为 `usageUnsupported`。

### 风险

- 如果用户确实配置的是 Token Plan key，但 MiniMax 后端仍返回 no active subscription，则 UI 会显示“用量不支持”；这符合后端语义，但可能需要用户换成正确 Token Plan key。
- MiniMax 返回码可能不稳定，本轮优先基于 message 兼容；后续如果拿到具体状态码，再把状态码也写进判断。

### 本轮实现结果（2026-06-07）

- `ProviderDataStatus.status(for:)` 已兼容 MiniMax legacy business error：
  - `no active token plan subscription`
  - 包含 `token plan subscription` / `no active token plan` 的文案
  - 统一映射为 `.usageUnsupported`。
- `APIPlatformFetcher.fetchMiniMax()` 在 `base_resp.status_msg` 表示没有 active Token Plan 时，写入规范错误码 `usageUnsupported`。
- `fetchMiniMaxViaModels()` 在普通 key 验证成功但没有 Token Plan 用量时，也返回 `usageUnsupported`，不再返回 `error: nil`。
- 新增回归测试，确保旧 state 里的 `no active token plan subscription` 不再被显示为“查询异常”。

### 验证结果

- `swift test --filter ProviderCapabilityTests/serviceDataStatusClassifiesLegacyFetcherErrorStrings`：通过。
- `swift test --filter ProviderCapability`：通过，10 个 ProviderCapability 测试通过。
- `swift test --filter StateModel`：通过，18 个 StateModel 测试通过。
- `swift test`：通过，138 个测试通过。
- `xcodebuild -project token_hud.xcodeproj -scheme token_hud -destination 'platform=macOS' build`：通过。

### 待手动验证

- 当前已有 `"no active token plan subscription"` 的 MiniMax state 应显示“用量不支持”，不再显示“查询异常”。
- 点击 MiniMax 刷新后，`~/.token-hud/state.json` 中 MiniMax `error` 应更新为 `usageUnsupported`。

---

## 当前重点：Codex 套餐/限额查询与 Keychain 弹窗降噪（已实现，待手动体验验证）

### 问题

用户反馈两个问题：

1. Codex 已显示本地认证存在，但 Plan 仍是 `Unknown`，当前数据为“暂无数据”，查不到套餐和限额。
2. 每次运行或操作 Settings 时，macOS 仍会反复弹 Keychain 授权框要求输入密码，体验不可接受。

本轮排查确认：

- `~/.codex/auth.json` 的 JWT 中，plan 位于 `https://api.openai.com/auth.chatgpt_plan_type`，不是当前代码读取的 `payload["auth"]["chatgpt_plan_type"]`，所以 UI 显示 `Unknown`。
- 当前 `~/.token-hud/state.json` 的 Codex service 是 `error: noLocalSessions`，说明不是 UI 误判，而是 fetcher 没拿到可展示用量。
- 当前 `~/.codex/sessions/2026/06` 没有本月 JSONL 文件；只扫本地 session 时自然会显示“暂无数据”。
- 网上调研和本机只输出字段名的探测都指向同一条路径：
  - `GET https://chatgpt.com/backend-api/wham/usage` 可用，当前返回 200，并包含 `plan_type`、`rate_limit.primary_window`、`rate_limit.secondary_window`、`credits`。
  - `GET https://chatgpt.com/backend-api/codex/usage` 当前返回 403，不能作为第一路径。
  - `codex-cli-usage`、CodexBar/openai/codex issue、VS Code Codex Usage Monitor 都使用 `~/.codex/auth.json` 的 access token 调 ChatGPT/Codex 后端 usage 接口。
- Keychain 弹窗仍可能来自后台路径：
  - `APIPlatformFetcher.init()` 启动时立即 `fetchAll()`，并定时 `fetchAll()`。
  - `fetchAll()` 通过 `hasCredential` 和各平台 fetch 多次 `KeychainHelper.load...`，这些是 `kSecReturnData = true` 的 secret 读取。
  - `CodexFetcher.fetch()` 每次也会尝试 `KeychainHelper.loadCodexAdminKey()` 读取 extras key；Codex 本地套餐/限额本身不需要这个 key。

### 本轮目标

- Codex 平台优先显示真实套餐和 5h/7d 限额：
  - 从 `auth.json` JWT 正确读取 plan。
  - 优先调用 `https://chatgpt.com/backend-api/wham/usage` 获取 `plan_type`、5h/7d 使用率、reset 时间和 credits。
  - `wham/usage` 失败时，回退本地 session JSONL 扫描。
- 不把 `codex/usage` 的 403 当成失败主路径；本轮只把它作为后续可选兼容，不阻塞功能。
- 后台自动刷新不应主动弹 Keychain 密码框：
  - 后台/定时/启动 fetch 使用“不允许用户交互”的 Keychain 读取。
  - 只有用户明确保存 key、手动刷新某个平台、点击连接控制台等主动操作，才允许读取 secret 并弹系统授权。
- Codex 本地 usage 查询不依赖 Codex Admin/API extras key；没有 extras key 不应读取它、不应弹框。

### 实施步骤

1. **补 Codex plan 解析**
   - 抽出 JWT auth claim 读取 helper：
     - 优先读 `payload["https://api.openai.com/auth"]`。
     - 兼容旧的 `payload["auth"]`。
   - `CodexFetcher.readCodexIdentity()` 和 `CodexAuthReader.status()` 共用同一解析规则或保持一致实现。

2. **新增 Codex wham usage 查询**
   - 从 `~/.codex/auth.json` 读取 `tokens.access_token` 和 `tokens.account_id`。
   - 请求：
     - `GET https://chatgpt.com/backend-api/wham/usage`
     - Header: `Authorization: Bearer <access_token>`
     - Header: `ChatGPT-Account-Id: <account_id>`（存在时）
     - Header: `User-Agent: codex-cli`
   - 解析：
     - `plan_type` => subscription quota / label。
     - `rate_limit.primary_window` => 5h quota。
     - `rate_limit.secondary_window` => 7d quota。
     - `credits.balance` / `credits.has_credits` => credits quota（如果有）。
   - 401/token expired => `tokenExpired`。
   - 403/网络失败/结构不匹配 => 只记录并回退本地 JSONL，不直接覆盖为“查询异常”。

3. **调整 Codex fetch 合并策略**
   - `wham/usage` 成功：优先写入含 plan、5h/7d、credits 的 Codex service。
   - 本地 JSONL 成功：追加本地月度 token / session 信息。
   - 本地 JSONL 没有本月数据：不再把整体状态写成 `noLocalSessions`，只保留线上 usage 结果。
   - wham 和本地都失败时，才显示对应错误状态。

4. **降低 Keychain 弹窗**
   - `KeychainHelper.load...` 增加 `allowUserInteraction` 参数，默认保留当前行为。
   - 新增静默读取路径：查询里加入 `kSecUseAuthenticationUI: kSecUseAuthenticationUIFail`。
   - `APIPlatformFetcher.fetchAll()`、后台 timer、Codex extras 自动补充使用静默读取；遇到 `errSecInteractionNotAllowed` 直接跳过，不弹系统框。
   - `hasCredential(for:)` 改用 `hasAPIKey` / `hasMiMoConsoleCookie` metadata existence，不读取 secret。
   - 用户点击某个平台 `刷新` 或保存凭据后触发的 `fetchSingle` 仍允许用户交互，因为这是明确主动动作。
   - Codex 的 Admin/API extras 只在用户保存了 extras key 且手动刷新 Codex 时读取；启动自动刷新不读取。

5. **测试**
   - 核心测试：
     - Codex JWT plan 解析支持 `https://api.openai.com/auth`。
     - wham usage parser 能解析 primary/secondary window、plan、credits。
     - wham 成功 + 本地无 sessions => `ready`，不是 `noUsageData`。
   - Keychain 相关尽量做可测试的 query builder / policy 测试，避免单元测试直接访问系统 Keychain。

6. **文档沉淀**
   - 更新 `docs/model-usage-query-practices.md` 的 Codex 段落：
     - 记录 `wham/usage` 是当前更可用主路径。
     - `codex/usage` 可能 403，不能作为唯一实现。
   - 更新 work-log，记录 Keychain 背景读取必须静默，避免后续回归。

### 验证

- `swift test --filter Codex`
- `swift test --filter ProviderCapability`
- `swift test`
- `xcodebuild -project token_hud.xcodeproj -scheme token_hud -destination 'platform=macOS' build`
- 手动验证：
  - 打开 Settings → 平台 → Codex，Plan 显示 `plus` 或对应套餐，不再是 `Unknown`。
  - 点击 Codex 刷新后，显示 5h/7d 使用率或 credits，不再只是“暂无数据”。
  - 重启 app 后，后台自动刷新不弹 Keychain 密码框。
  - 切换 Settings 平台、hover、点击列表，不弹 Keychain 密码框。
  - 只有手动刷新需要 secret 的 API 平台时，才可能弹一次系统授权；用户点“始终允许”后后续不应反复弹。

### 风险

- `wham/usage` 是 ChatGPT/Codex 后端接口，不属于稳定公开 OpenAI API；需要保留本地 JSONL 回退。
- access token 过期时需要用户重新 `codex login`；本轮不实现 refresh token 自动续期，避免接管 Codex CLI auth。
- 不允许后台 Keychain UI 后，部分 API 平台在旧 ACL 状态下可能后台不自动刷新；这是有意取舍，优先避免打断用户。
- 如果用户保存过 Codex Admin/API extras key，旧 Keychain item ACL 仍可能在手动刷新时弹一次；但不应在启动和普通 Settings 操作中反复弹。

### 本轮实现结果（2026-06-07）

- `CodexJWT` 增加：
  - `codexAuthClaim(from:)`，优先读取 `https://api.openai.com/auth.chatgpt_plan_type`。
  - `CodexWhamUsageParser`，解析 `plan_type`、5h/7d rate-limit window 和 credits。
- `CodexFetcher` 改为：
  - 启动/定时刷新优先请求 `https://chatgpt.com/backend-api/wham/usage`。
  - `wham/usage` 成功时写入 Codex Plus/Team 等套餐标签和 5h/7d quota。
  - 本地 JSONL 成功时追加本地 token/session；本地无 sessions 不再覆盖线上 usage。
  - `wham/usage` 401 时写 `tokenExpired`；403/网络/解析失败时回退本地 sessions。
- Settings Codex 面板修复 Plan 读取字段，文案改为“优先 usage 限额，回退本地 sessions”。
- `KeychainHelper` 增加 `allowUserInteraction` 读取参数，并用 `LAContext.interactionNotAllowed` 实现后台静默读取。
- `APIPlatformFetcher`：
  - 启动/定时 `fetchAll` 使用静默 secret 读取。
  - `hasCredential` 改用 metadata existence 查询，不再为了判断是否配置读取 secret。
  - OpenAI/Anthropic/Gemini 这类 usage unsupported 平台只查 metadata。
  - 手动 `fetchSingle` 仍允许用户交互。
- 已更新：
  - `docs/model-usage-query-practices.md`
  - `docs/work-log/2026-06-07-codex-wham-keychain-silent.md`

### 验证结果

- `swift test --filter CodexJWT`：通过，15 个 CodexJWT 测试通过。
- `swift test --filter ProviderCapability`：通过，10 个 ProviderCapability 测试通过。
- `swift test`：通过，138 个测试通过。
- `xcodebuild -project token_hud.xcodeproj -scheme token_hud -destination 'platform=macOS' build`：通过。
- 联网字段探测：
  - `https://chatgpt.com/backend-api/wham/usage` 当前返回 200，并包含 `plan_type`、`rate_limit.primary_window`、`rate_limit.secondary_window`、`credits`。
  - `https://chatgpt.com/backend-api/codex/usage` 当前返回 403。

### 待手动验证

- 重启 app，确认启动和打开 Settings 不再连续弹 Keychain 授权框。
- Settings → 平台 → Codex 显示 `Plan: Plus` 或对应套餐。
- 点击 Codex 刷新后，当前数据区域显示 5h / 7d 限额，不再只是“暂无数据”。
- 手动刷新 DeepSeek/MiniMax/MiMo 这类需要 secret 的平台时，如旧 Keychain ACL 仍要求授权，最多是用户主动操作触发，不应在后台反复弹。

---

## 当前重点：修复 Codex 无 sessions 时误显示查询异常（已实现，待手动体验验证）

### 问题

用户反馈：Settings → 平台 → Codex 依然显示“查询异常”。

本轮排查确认：

- 用户当前 `~/.token-hud/state.json` 中 Codex 数据为：
  - `"error":"No sessions yet"`
  - `"label":"Codex"`
  - `"quotas":[]`
- `ProviderDataStatus.status(for:)` 只把 `ProviderQueryError.noLocalSessions.rawValue`（即 `noLocalSessions`）映射为 `.noUsageData`。
- `"No sessions yet"` 不是已知枚举值，也不匹配 network/permission/expired 这些字符串规则，所以落入 `.error`。
- UI 对 `.error` 的标题是“查询异常”，详情是“查询结果无法解析或平台返回异常。”

所以根因不是 Codex auth 或 OpenAI Admin/API extras，而是 Codex fetcher 写入了不规范的 legacy error string，状态解析层又没有兼容它。

### 本轮目标

- Codex 没有本地 sessions 时显示“暂无数据”，而不是“查询异常”。
- 保持本地 Codex 认证状态仍为“已配置”。
- 对已有 `state.json` 中的 `"No sessions yet"` 做向后兼容，用户无需手动清空 state。
- 后续 CodexFetcher 写入规范化错误码 `noLocalSessions`，不再写自然语言字符串。

### 实施步骤

1. **补回归测试**
   - 在 `ProviderCapabilityTests` 增加测试：
     - `Service(error: "No sessions yet")` 应映射为 `.noUsageData`。
     - `Service(error: ProviderQueryError.noLocalSessions.rawValue)` 应映射为 `.noUsageData`。

2. **修状态解析兼容**
   - 在 `ProviderDataStatus.status(for:)` 中兼容 legacy 字符串：
     - `"No sessions yet"`
     - 可选兼容 `"no sessions"`
   - 映射为 `.noUsageData`。

3. **修 CodexFetcher 写入值**
   - `CodexFetcher.fetch()` 在 `.noSessionsDirectory` / `.noSessionFiles` 时写入：
     - `ProviderQueryError.noLocalSessions.rawValue`
   - 不再写 `"No sessions yet"`。

4. **验证**
   - `swift test --filter ProviderCapability`
   - `swift test --filter Codex`
   - `swift test`
   - `xcodebuild -project token_hud.xcodeproj -scheme token_hud -destination 'platform=macOS' build`
   - 手动验证：
     - 当前已有 `"No sessions yet"` state 时，Codex UI 显示“暂无数据”。
     - 点击刷新后，state 里 Codex error 变成 `noLocalSessions`。

### 风险

- 如果确实存在 JSONL 但解析失败，仍应保持 `parseError` => “查询异常”，不能把真实解析错误吞成“暂无数据”。
- 这次只修 Codex 无 sessions 的状态分类，不处理 MiniMax 的 `no active token plan subscription` 等其他平台状态。

### 本轮实现结果（2026-06-07）

- `ProviderDataStatus.status(for:)` 已兼容 legacy error string：`"No sessions yet"` / `"no sessions"` 会映射为 `.noUsageData`。
- `CodexFetcher.fetch()` 在没有 `~/.codex/sessions` 或没有 session 文件时，改为写入规范错误码 `noLocalSessions`。
- 新增回归测试，覆盖旧 state 文件里的 `"No sessions yet"` 和新规范错误码 `noLocalSessions`。

### 验证结果

- `swift test --filter ProviderCapabilityTests/serviceDataStatusClassifiesLegacyFetcherErrorStrings`：通过。
- `swift test --filter ProviderCapability`：通过，10 个 ProviderCapability 测试通过。
- `swift test --filter Codex`：通过，12 个 Codex 相关测试通过。
- `swift test`：通过，135 个测试通过。
- `xcodebuild -project token_hud.xcodeproj -scheme token_hud -destination 'platform=macOS' build`：通过。

### 待手动验证

- 打开 Settings → 平台 → Codex，当前已有 `"No sessions yet"` 的 state 应显示“暂无数据”，不再显示“查询异常”。
- 点击刷新后，`~/.token-hud/state.json` 中 Codex 的 `error` 应更新为 `noLocalSessions`。

---

## 当前重点：完善 Codex API 认证与数据源分层（已实现，待手动体验验证）

### 问题

用户反馈：Codex 的 API 认证相关功能现在感觉不可用。

结合 `docs/model-usage-query-practices.md` 和当前代码，问题核心是 Codex 现在只按“本地 Codex CLI 登录态”建模：

- `ProviderCapability.codex` 的 credentialKind 是 `.codexLocalAuth`。
- Settings 里只提供：
  - `重新登录 Codex` => 执行 `codex login`。
  - `打开 ~/.codex`。
  - `移除 ~/.codex/auth.json`。
- `CodexFetcher` 只读取：
  - `~/.codex/auth.json` 中的账号/plan。
  - `~/.codex/sessions` 中的 JSONL token/rate-limit 数据。
- 没有单独的 `OpenAI Admin Key` / `OpenAI API Key for Codex extras` 配置入口。
- 文档里已经沉淀：Codex 主路径应本地优先；OpenAI cookies/Admin key 只能作为可选 dashboard extras，不能和 Codex CLI auth 混在一起。

因此当前 UI 让用户容易误解：以为 Codex 的“API 认证”已经可配置，但实际没有任何可用入口或查询逻辑。

### 本轮目标

- 把 Codex 认证拆成两层展示和操作：
  - **Codex 本地认证**：继续读取 `~/.codex/auth.json`，用于身份、plan、本地 sessions。
  - **Codex API / OpenAI Admin 认证（可选）**：新增单独入口，用于后续 OpenAI Usage / Costs / dashboard extras。
- Settings → Codex 详情页新增明确的 API/Admin key 配置区域：
  - 保存 `OpenAI Admin Key` 或 `OpenAI API Key` 到独立 Keychain account。
  - 显示“已配置 / 未配置 / 仅可验证 / 需要组织权限”。
  - 提供重置按钮，不影响 `~/.codex/auth.json`。
- 不把 Admin key 当成 Codex CLI 登录态，也不删除/覆盖 Codex CLI 自己的认证。
- 如果没有 Admin key，只显示本地 Codex 数据，不报错为“API 不可用”。
- 如果有 Admin key，本轮先做低风险验证：
  - 尝试调用 OpenAI Usage/Costs API 或一个轻量认证探测接口。
  - 403/权限不足时明确显示“Admin 权限不足”。
  - 不伪造额度，不把普通 API key 说成能查 Codex 账单。

### 推荐方案

采用“本地 Codex + 可选 OpenAI Admin extras”的分层方案。

原因：

- 符合已沉淀文档：Codex 主数据来自本地 JSONL，API/Admin key 只做额外数据源。
- 避免把 `codex login`、OpenAI API key、OpenAI Admin key 混成一个凭据。
- 用户过期重登 Codex CLI 和重置 OpenAI Admin key 是两件事，应该分开操作。
- 如果 Admin API 权限不足，UI 可以准确解释，而不是让用户误以为 Codex 整体不可用。

不采用的方案：

- **把 Codex 改成普通 API key 平台**：会丢掉本地 session/rate-limit 这个最稳定来源。
- **用 Codex CLI auth token 去调 OpenAI billing API**：权限和稳定性不明确，容易产生 401/403，而且会把私有/非稳定路径变成主路径。

### 实施步骤

1. **补核心模型**
   - 增加 Codex API extras credential 的能力模型，建议新增：
     - `ProviderCredentialKind.codexLocalAuthAndAdminKey`，或保留 `codexLocalAuth` 但在 UI 里加 Codex 专属 extras section。
     - `ProviderResetAction.adminAPIKey` 或复用更明确的 `apiKey`，但不能和 Codex local auth 混淆。
   - 增加测试覆盖：
     - Codex 本地认证仍是主路径。
     - Codex 可选 Admin key 存在时，credential snapshot 可以展示 extras 已配置。
     - 删除 Admin key 不影响 `~/.codex/auth.json`。

2. **扩展 KeychainHelper**
   - 新增独立 account，例如 `codexOpenAIAdminKey`。
   - 提供：
     - `saveCodexAdminKey`
     - `hasCodexAdminKey`
     - `loadCodexAdminKey`
     - `deleteCodexAdminKey`
   - Settings 渲染路径只用 `has...`，避免反复读取 secret。

3. **Settings Codex 详情页改造**
   - Codex 认证面板拆成两个 section：
     - `Codex 本地登录`：当前 email/plan、重新登录、打开 `~/.codex`、移除本地认证。
     - `OpenAI Admin / API extras`：保存 key、状态说明、重置 key。
   - 文案明确：
     - 本地 Codex 数据不需要 Admin key。
     - 普通 OpenAI key 可能只能验证调用能力。
     - Usage/Costs 需要组织/项目权限。

4. **Fetcher 查询逻辑**
   - `CodexFetcher` 保持本地 JSONL 主路径。
   - 新增可选 extras fetch：
     - 有 Admin key 时尝试轻量 OpenAI Usage/Costs 查询。
     - 权限不足返回 `permissionDenied`，不覆盖本地 Codex quotas。
     - 网络错误返回 `networkError`，也不覆盖本地数据。
   - 合并策略：
     - 本地 tokens/rate-limit 永远保留。
     - API extras 成功时追加 cost 或 usage quota。
     - API extras 失败时只在 error/detail 中展示 extras 错误，不让 Codex 整体变成不可用。

5. **状态和重置**
   - Codex reset 区域拆成：
     - `移除本地认证`：删除 `~/.codex/auth.json`。
     - `重置 Admin Key`：删除 Keychain 中的 Codex Admin key。
     - `清空数据`：只清 `state.json` 的 codex service。

6. **文档沉淀**
   - 更新 `docs/model-usage-query-practices.md` 的 Codex 段落：
     - 记录本地 auth、sessions、Admin extras 的边界。
   - 如果实现中发现 OpenAI Usage/Costs API 对 key 权限有具体错误码，写入 work-log。

### 验证

- `swift test --filter ProviderCapability`
- `swift test --filter Codex`
- `swift test`
- `xcodebuild -project token_hud.xcodeproj -scheme token_hud -destination 'platform=macOS' build`
- 手动验证：
  - 没有 Admin key 时，Codex 本地数据仍能展示，不提示“API 不可用”。
  - 保存 Admin key 后，Settings 显示 extras 已配置。
  - 普通 key / 权限不足时明确显示“权限不足或仅可验证”，不会覆盖本地 Codex 数据。
  - 重置 Admin key 不删除 `~/.codex/auth.json`。
  - 移除本地认证不删除 Admin key。

### 风险

- OpenAI Usage/Costs API 需要组织/项目级权限，普通 API key 很可能 403；UI 必须把这解释成权限问题，而不是认证功能坏了。
- Codex CLI auth token 不应被 token-hud 接管或复用到 Admin API，避免不稳定和安全边界混乱。
- 当前工作区已有较多未提交改动，本轮实现必须只触碰 Codex/Settings/Keychain/测试/文档相关文件，不回滚其他视觉或 Notch 改动。

### 本轮实现结果（2026-06-07）

- Codex 认证展示已拆成两层：
  - `Codex 本地登录`：继续读取 `~/.codex/auth.json` 和本地 sessions。
  - `OpenAI Admin / API extras`：新增独立 key 配置入口。
- `KeychainHelper` 新增独立 account `codexOpenAIAdminKey`：
  - `saveCodexAdminKey`
  - `hasCodexAdminKey`
  - `loadCodexAdminKey`
  - `deleteCodexAdminKey`
- `ProviderCredentialSnapshot` 新增 `codexAdminKey`、`maskedCodexAdminKey` 和 `hasCodexAdminKey`。
- `ProviderResetAction` 新增 `adminAPIKey`；Codex reset actions 改为 `localAuth + adminAPIKey + serviceData`。
- Settings → Codex 详情页新增 Admin/API extras key 保存框和状态说明。
- Codex 重置区域新增 `重置 Admin Key`，只删除 Keychain extras key，不影响 `~/.codex/auth.json`。
- `CodexFetcher` 保持本地 JSONL 主路径，并在 extras key 存在时尝试查询 OpenAI organization Costs：
  - 成功时追加 `costSpent` quota。
  - 401/403、网络错误或解析不到金额时只记录日志，不覆盖本地 Codex 数据。
- 已更新 `docs/model-usage-query-practices.md` 的 Codex 段落。
- 已新增 `docs/work-log/2026-06-07-codex-api-auth-split.md` 记录认证边界。

### 验证结果

- `swift test --filter ProviderCapability`：通过，10 个 ProviderCapability 测试通过。
- `swift test --filter Codex`：通过，12 个 CodexJWT 测试通过。
- `swift test`：通过，135 个测试通过。
- `xcodebuild -project token_hud.xcodeproj -scheme token_hud -destination 'platform=macOS' build`：通过。

### 待手动验证

- Settings → 平台 → Codex 能看到 `Codex 本地登录` 与 `OpenAI Admin / API extras` 两块。
- 保存 extras key 后，Codex 页面显示 Admin/API key 已配置。
- 点击 `重置 Admin Key` 后 extras key 消失，但 `~/.codex/auth.json` 不受影响。
- 点击 `移除本地认证` 后只影响 Codex CLI 本地登录，不删除 extras key。
- 普通 API key 权限不足时，本地 Codex sessions 仍能显示。

---

## 当前重点：优化 MiMO 获取方法与套餐查询入口（已实现，待手动体验验证）

### 问题

用户反馈：MiMO 目前更像是要求用户手动粘贴 cookie，配置体验不成熟。调研后确认 MiMO 官方区分两类 key：

- `tp-xxxxx`：Token Plan key，只用于套餐服务和套餐额度。
- `sk-xxxxx`：pay-as-you-go API key，只用于按量 API 调用。

当前实现存在几个问题：

- 新 Settings 重构后的 MiMO 详情页没有明显暴露旧版 `MiMoConsoleConnectorSheet` 的 WebView 自动登录/自动抽 cookie 能力。
- UI 把 MiMO API key 和 Console Cookie 放在同一套语义里，容易让用户以为普通 `sk-` key 能查询 Token Plan。
- 手动 cookie 应只作为高级 fallback，不应作为主要路径。
- `docs/model-usage-query-practices.md` 已沉淀调研结论，后续实现应按该文档执行。

### 本轮目标

- MiMO 配置体验改成三层入口：
  - `Token Plan Key (tp-)`：首选，用于套餐服务/套餐查询。
  - `API Key (sk-)`：只用于 pay-as-you-go 调用验证。
  - `连接 MiMO 控制台`：备用路径，通过 WebView 登录后自动获取 cookie。
- 新 Settings 的 MiMO 详情页恢复明确的 `连接 MiMO 控制台` 按钮，不再让用户只能手动粘贴 cookie。
- 保存 cookie 或 key 后刷新 credential snapshot，并立即触发 MiMO 查询。
- UI 状态明确区分：
  - Token Plan Key 已配置
  - API Key 已配置，仅验证调用
  - Console Cookie 已配置
  - 控制台登录已过期
  - 未配置套餐查询凭据

### 实施步骤

1. **整理 MiMO 连接组件**
   - 将 `MiMoConsoleConnectorSheet`、`MiMoConsoleConnectorView` 从 `PlatformRowView.swift` 移到独立文件，例如 `Settings/MiMoConsoleConnectorView.swift`。
   - 保留 `WKWebsiteDataStore.default()`、`httpCookieStore.getAllCookies` 和原生 `URLSession` 验证逻辑。

2. **接入新 Settings MiMO 详情页**
   - 在 `PlatformListView` 的 MiMO credential panel 中增加 `连接 MiMO 控制台` 按钮。
   - 登录成功后保存 cookie 到 Keychain，刷新 snapshot，并调用 `apiPlatformFetcher.fetchSingle(platform: "mimo")`。

3. **拆分 MiMO key 语义**
   - UI 文案明确普通 `sk-` key 只能验证 `/v1/models`。
   - 增加 `tp-` Token Plan key 的保存/提示逻辑；如果本轮不改 Keychain schema，则先通过现有 API key 存储兼容保存，但 UI 必须根据前缀提示能力差异。

4. **错误与状态改进**
   - MiMO Token Plan 查询 401/业务未登录时显示“控制台登录已过期”。
   - `sk-` key 查询成功但无套餐数据时显示“普通 API Key 已验证，暂无 Token Plan 数据”。
   - 没有 `tp-` key 或 cookie 时显示“未配置套餐查询凭据”。

5. **文档引用**
   - 保持 `docs/model-usage-query-practices.md` 作为长期参考。
   - 如果实现中发现 MiMO API 行为和文档不同，再更新该文档。

### 验证

- `swift test --filter ProviderCapability`
- `swift test`
- `xcodebuild -project token_hud.xcodeproj -scheme token_hud -destination 'platform=macOS' build`
- 手动验证：
  - Settings → 平台 → MiMO 能看到 Token Plan/API Key/Console Login 三类入口。
  - 点击 `连接 MiMO 控制台` 后可以登录并自动保存 cookie。
  - cookie 保存后 MiMO 查询自动刷新。
  - `sk-` key 不被展示成“已查到套餐”。
  - cookie 过期时 UI 明确提示重新连接。

### 风险

- MiMO 控制台内部 JSON API 不是公开稳定 API，字段和业务码可能变化。
- `tp-` key 是否能直接查询套餐 remains 需要真实账号验证；如果官方只允许它调用模型而不开放 query API，需要继续保留 WebView cookie 路径。
- WebView 登录可能受地区、验证码、第三方登录或 2FA 影响；必须保留手动 cookie fallback。

### 本轮实现结果（2026-06-07）

- 新增 MiMO key 类型识别：
  - `tp-` => Token Plan Key。
  - `sk-` => pay-as-you-go API Key。
  - cookie 或 `tp-` key 才视为套餐查询凭据。
- 新 Settings 的 MiMO 详情页新增 `连接 MiMO 控制台` 入口：
  - 通过 `WKWebView` 打开 MiMO 控制台。
  - 登录成功后自动读取 WebView cookie。
  - 用原生 `URLSession` 验证 `/api/v1/tokenPlan/usage` 返回成功后保存 Cookie。
  - 保存后刷新 credential snapshot，并触发 MiMO 查询。
- 手动粘贴 Cookie 改为高级备用入口，不再作为主要路径。
- MiMO API key 文案改为 `tp-… 或 sk-…`，并明确：
  - `tp-` 是套餐服务 key。
  - `sk-` 只做调用验证。
- MiMO fetcher 改用官方文档中的 `api-key` header 验证 `/v1/models`。
- `sk-` key 验证成功后返回 `usageUnsupported`，避免 UI 显示成“已查到套餐但暂无数据”。
- 新增 `Settings/MiMoConsoleConnectionSheet.swift`，并加入 Xcode target。

### 验证结果

- `swift test --filter ProviderCapability`：通过，9 个 ProviderCapability 测试通过。
- `swift test`：通过，134 个测试通过。
- `xcodebuild -project token_hud.xcodeproj -scheme token_hud -destination 'platform=macOS' build`：通过。
- `xcodegen generate` 在本地报 `token_hud.xcodeproj` 已存在的拷贝错误；为避免删除现有工程，本轮手动把新增 Swift 文件加入 `token_hud.xcodeproj/project.pbxproj`，随后 app build 已验证通过。

### 待手动验证

- Settings → 平台 → MiMO 能看到 `连接 MiMO 控制台`。
- 点击后能打开 MiMO 控制台并完成登录。
- 登录后自动保存 Cookie，关闭 sheet，并刷新 MiMO 数据。
- 输入 `sk-` key 时 UI 显示“仅验证调用 / 用量不支持”，不误导为套餐用量。
- 输入 `tp-` key 时 UI 显示 Token Plan Key 已配置。

---

## 当前重点：补齐 Codex / OpenAI 本地认证重新配置入口（已实现，待手动体验验证）

### 问题

用户反馈：Codex 当前显示的是本地 OpenAI/Codex 认证状态，但 Settings 里没有可操作的重新配置入口。认证过期或账号需要切换时，只能看到“运行 `codex login`”提示，无法从 Settings 中直接处理。

当前实现的问题：

- `ProviderCapability` 里 Codex 的 `resetActions` 只有 `.serviceData`，没有认证相关操作。
- `PlatformCredentialPanel.codexContent` 只展示 auth 状态和提示文案，没有按钮。
- `PlatformResetPanel` 对 `.codexLocalAuth` 明确不删除 `~/.codex/auth.json`，这是为了安全，但结果是用户没有任何“重新认证”路径。
- 对用户来说，“Codex 正常的 OpenAI 认证”就是 Codex CLI 使用的 `~/.codex/auth.json`，Settings 应该提供明确入口，而不是只显示静态说明。

### 本轮目标

- Codex 平台详情页提供明确的重新认证入口：
  - `重新登录 Codex`：打开 Terminal 并执行 `codex login`。
  - `打开认证文件夹`：打开 `~/.codex`，方便用户检查 auth/session 文件。
- Codex reset 区域增加受控操作：
  - `清空 Codex 数据`：继续只删除 `state.json` 中 codex service。
  - `移除本地 Codex 认证`：可选 destructive 操作，删除 `~/.codex/auth.json`，并提示会影响 Codex CLI 登录状态。
- 不把 Codex 认证塞进 Keychain 逻辑，避免再次引入 Keychain 弹窗。
- 操作后刷新 Codex 状态和当前 state。

### 实施步骤

1. **补核心能力模型测试**
   - 更新 `ProviderCapabilityTests`：
     - Codex 的 reset actions 应包含 `.localAuth` 或等价 action。
     - Codex 仍保持 `.codexLocalAuth` 和 `.localSessionLogs`。

2. **扩展 reset action 模型**
   - 在 `ProviderResetAction` 增加 `localAuth`。
   - 将 Codex 的 reset actions 改为 `[.localAuth, .serviceData]`。

3. **增加 Codex 登录入口**
   - 在 `PlatformCredentialPanel.codexContent` 增加按钮：
     - `重新登录 Codex`
     - 使用 `NSWorkspace` 打开 Terminal 执行 `codex login`。
   - 如果自动执行 Terminal 命令不稳定，退化为复制命令并打开 Terminal。

4. **增加打开 auth 文件夹入口**
   - 增加 `打开 ~/.codex` 按钮。
   - 如果目录不存在，先创建或提示未找到。

5. **增加受控删除本地 auth**
   - `PlatformResetPanel` 针对 `.localAuth` 显示 `移除本地认证`。
   - 删除目标只限 `~/.codex/auth.json`，不删除 sessions。
   - 删除后调用 `onCredentialChanged()` 让 UI 刷新。
   - UI 文案明确：这会让 Codex CLI 退出登录，需要重新 `codex login`。

6. **验证**
   - `swift test --filter ProviderCapability`
   - `swift test`
   - `xcodebuild -project token_hud.xcodeproj -scheme token_hud -destination 'platform=macOS' build`
   - 手动验证：
     - Codex 详情页能看到重新登录按钮。
     - 点击后 Terminal 能进入/执行 `codex login`。
     - `打开 ~/.codex` 可用。
     - `移除本地认证` 后 Codex 状态变成未配置或过期。

### 风险

- 自动控制 Terminal 可能受系统权限、默认终端或 shell 配置影响；需要提供可退化方案。
- 删除 `~/.codex/auth.json` 会影响 Codex CLI 本身登录状态，所以必须做成明确 destructive 操作，不能静默执行。
- Codex 登录流程本身可能需要浏览器或 OpenAI 账号交互，Settings 只能提供入口，不能替用户完成全部认证。

### 本轮实现结果（2026-06-06）

- Codex 的 provider capability 已增加 `.localAuth` reset action。
- Codex 认证区域新增：
  - `重新登录 Codex`：通过 Terminal 执行 `codex login`。
  - `打开 ~/.codex`：打开或创建本地 Codex 配置目录。
- Codex 重置区域新增：
  - `移除本地认证`：带 destructive 确认，只删除 `~/.codex/auth.json`，不删除 sessions。
  - `清空数据` 仍只删除 `state.json` 中 codex service。
- 自动执行 Terminal 失败时，会复制 `codex login` 到剪贴板并打开 Terminal，用户可手动粘贴执行。

### 验证结果

- `swift test`：133 个测试通过。
- `xcodebuild -project token_hud.xcodeproj -scheme token_hud -destination 'platform=macOS' build`：通过。

### 待手动验证

- 在 Codex 平台详情页点击 `重新登录 Codex`，确认 Terminal 能启动登录流程。
- 点击 `打开 ~/.codex`，确认目录能打开。
- 点击 `移除本地认证`，确认有二次确认，删除后 Codex 状态更新。

---

## 当前重点：修复 Settings 操作时 Keychain 反复弹密码框（已实现，待手动体验验证）

### 问题

用户反馈：在 Settings 做各种操作时，macOS 会反复弹出 Keychain 授权框，需要输入七八次密码，导致 Settings 基本不可用。

本轮排查结论：

- 弹窗来自 macOS Keychain 访问 `com.tokenHud.sessionKey`。
- 上一轮 Settings 平台页重构后，把 Keychain 读取放进了 SwiftUI 渲染路径：
  - `PlatformListView.platformSidebar` 中每个平台 row 都会调用 `CredentialStatusReader.status(...)`。
  - `CredentialStatusReader.status(...)` 内部直接调用 `KeychainHelper.load()`、`loadAPIKey(...)`、`loadMiMoConsoleCookie()`。
  - `PlatformCredentialPanel` 的 `body` 中也直接调用 `KeychainHelper.load...` 来显示 masked secret。
- SwiftUI 的 `body` 会因为选中、hover、状态变化、刷新、布局变化而频繁重算；这会把一次打开 Settings 变成多次 Keychain 读取。
- 如果旧 Keychain item 的 ACL 绑定了旧签名或旧 bundle，macOS 会对每次读取都要求授权；代码层面的反复读取会把这个体验放大成连续弹窗。

### 本轮目标

- Settings 打开或切换平台时，不再在 SwiftUI `body` 中直接读取 Keychain。
- 将 Keychain 读取集中到一个缓存/快照模型中：
  - 打开平台页时最多读取一次。
  - 保存、重置、刷新后显式 reload。
  - UI 只读取内存中的 masked/status，不触发 Keychain。
- 对“是否已配置”的展示只依赖内存快照。
- 保留保存/删除凭据功能。
- 提供一次性清理旧 Keychain item 的说明，用于解决旧 ACL 导致的首次授权弹窗。

### 实施步骤

1. **补充可测试的快照模型**
   - 增加 `ProviderCredentialSnapshot` / `ProviderCredentialSnapshotStore` 一类纯数据模型。
   - 覆盖：
     - Claude session key 存在 => configured。
     - API key 存在 => configured。
     - MiMo API key 或 cookie 任一存在 => configured。
     - masked 值不暴露完整 secret。

2. **改 Settings 平台页数据流**
   - `PlatformListView` 增加 `@State private var credentialSnapshot`。
   - `.task` 或 `.onAppear` 中集中读取所有平台 Keychain 一次。
   - `CredentialStatusReader.status(...)` 改为吃 snapshot，不再自己读 Keychain。
   - `PlatformCredentialPanel` 改为接收 snapshot 中的 masked value，不在 `body` 中读 Keychain。

3. **保存/删除后显式刷新快照**
   - 保存 API key、保存 Cookie、保存 Claude session key 后 reload snapshot。
   - 重置 API key、重置 Cookie、重置 Claude session key 后 reload snapshot。
   - 不因为普通 UI hover/selection 触发 reload。

4. **降低后台自动 fetch 的 Keychain 读取频率**
   - `APIPlatformFetcher.fetchAll()` 仍可能按 interval 读取多个 key。
   - 本轮先不重构 fetcher 架构，但避免 Settings UI 重绘触发 Keychain 读取。
   - 如果用户仍遇到后台弹窗，再把 fetcher 改成更长间隔或集中读取快照。

5. **用户侧一次性修复建议**
   - 如果旧 Keychain item ACL 已损坏，提示用户可选择：
     - 在弹窗中点“始终允许”一次。
     - 或用 Settings 的 `重置认证` 删除旧 item 后重新保存。
   - 必要时提供 `security delete-generic-password -s com.tokenHud.sessionKey ...` 命令，但不自动执行。

### 验证

- `swift test --filter ProviderCredentialSnapshot`
- `swift test`
- `xcodebuild -project token_hud.xcodeproj -scheme token_hud -destination 'platform=macOS' build`
- 手动验证：
  - 打开 Settings 平台页，不应连续弹多次 Keychain 授权框。
  - 切换平台、hover、点击左侧列表，不应再次读取 Keychain。
  - 保存/删除凭据后状态更新。
  - 如果旧 item 仍弹一次，点“始终允许”后不再重复弹。

### 风险

- 如果后台 `APIPlatformFetcher` 正在自动刷新，它仍可能访问 Keychain；需要通过日志/手动观察区分 Settings UI 重绘和后台 timer。
- 如果用户选择“允许”而不是“始终允许”，macOS 仍可能下次再问；代码只能减少读取次数，不能替用户修改 Keychain ACL。
- 缓存快照可能短时间和 Keychain 不一致，所以所有保存/删除路径必须显式 reload。

### 本轮实现结果（2026-06-06）

- 新增 `ProviderCredentialSnapshot` 纯模型，用于把凭据存在性和 UI 展示从真实 secret data 中拆开。
- `PlatformListView` 不再在 SwiftUI `body` / row 渲染 / detail 渲染中调用 `KeychainHelper.load...`。
- `KeychainHelper` 增加 `hasClaudeSessionKey`、`hasAPIKey`、`hasMiMoConsoleCookie` 等 existence 查询，用 `kSecReturnAttributes` 只查 item 元数据，不取 secret data。
- Settings 平台页打开时集中生成一次 credential snapshot：
  - 已配置状态来自 snapshot。
  - UI 只显示 `••••••••`，不为显示末尾几位读取 secret。
  - 保存/删除凭据后显式 reload snapshot。
- 保留保存/删除凭据和刷新逻辑；真正需要请求平台 API 时，fetcher 仍会读取对应 secret。

### 验证结果

- `swift test`：133 个测试通过。
- `xcodebuild -project token_hud.xcodeproj -scheme token_hud -destination 'platform=macOS' build`：通过。

### 待手动验证

- 打开 Settings 平台页，确认不再连续弹 Keychain 授权框。
- 切换平台、hover、点击列表、滚动详情，确认不会重复弹窗。
- 保存或重置凭据后，平台状态能更新。
- 如果旧 item 仍弹一次，点“始终允许”或用 `重置认证` 删除后重新保存。

---

## 当前重点：Settings 平台配置、重置与查询状态优化（已实现，待手动体验验证）

### 问题

用户反馈：

- 已配置过的凭据、认证或 API key 过期后，Settings 里没有清晰的重置入口，导致无法重新配置。
- Codex 这类本地认证平台在“认证存在但没有查询结果 / token 过期 / 暂无 session 数据”时，缺少明确标识。
- Settings 页面当前信息架构较散：
  - `SettingsWindow` 还是简单 `TabView`，窗口尺寸偏小，不适合平台详情和状态面板。
  - `PlatformListView`、`PlatformRowView`、`APIKeyGroupView` 存在重复逻辑，平台状态、凭据编辑、查询结果混在一起。
  - 小组件自定义选择仍是普通 Picker，缺少搜索和筛选。
- 现有查询能力没有明确区分“能直接查用量 / 只能校验 key / 需要管理员或账单权限 / 需要控制台 cookie / 本地日志”，容易让 UI 显示成“已配置但没数据”。

用户已确认两个关键范围：

- 设置页布局采用预览方案 A：左侧导航 + 右侧平台 dashboard/detail。
- 重置拆成两个动作：
  - `重置认证`：删除 Keychain 里的 session key、API key、cookie 或本地认证引用。
  - `清空数据`：从 `state.json` 移除对应 service 数据，不删除凭据。
- 查询功能本轮选择方案 3：先把 UI、状态入口和能力说明做好；真实 provider 查询只做低风险补齐，不强行在普通 API key 上实现不可用的账单接口。

外部调研约束：

- OpenAI 官方 Usage/Costs API 是组织级用量/费用接口，通常要求组织权限；普通调用 API key 不等同于一定可查账单。
- Anthropic 的成本/用量报告需要 Console 角色权限，Admin/Usage/Cost API 不应假设普通 `sk-ant-` key 可用。
- Gemini/Google 的可靠费用侧更偏 Google Cloud Billing / BigQuery export；AI Studio API key 更适合验证调用能力，不适合作为完整费用查询凭据。
- DeepSeek 有官方 `/user/balance`，适合继续作为余额查询路径。
- MiniMax Token Plan 有官方 `token_plan/remains` 路径，适合继续做 token plan 用量查询。
- LiteLLM 等成熟开源实践通常是“请求日志 + provider usage/cost API + 本地价格表 + dashboard”，而不是只靠一个 API key 通吃所有平台账单。

参考：

- OpenAI Usage / Costs API：`https://platform.openai.com/docs/api-reference/usage`
- OpenAI Usage Dashboard 权限说明：`https://help.openai.com/en/articles/10478918`
- Anthropic Console cost and usage reports：`https://support.anthropic.com/en/articles/9534590-cost-and-usage-reporting-in-console`
- DeepSeek 查询余额：`https://api-docs.deepseek.com/zh-cn/api/get-user-balance/`
- MiniMax Token Plan remains：`https://platform.minimax.io/docs/coding-plan/faq`
- LiteLLM cost tracking：`https://docs.litellm.ai/docs/proxy/cost_tracking`

### 本轮目标

- 把 Settings 页面重组成更直观的“侧边栏导航 + 右侧详情”结构，先覆盖：
  - 小组件
  - 平台
  - 通用
- 平台页采用 dashboard/detail 结构：
  - 左侧平台列表显示配置状态、认证状态、数据状态。
  - 右侧显示当前平台的凭据、查询能力、最近结果、错误原因和重置操作。
- 增加统一重置能力：
  - `重置认证`：删除对应 Keychain 项；Codex 显示“请运行 codex login”，不直接删除用户 `~/.codex/auth.json`。
  - `清空数据`：从当前 `state.json` 删除对应 service。
  - MiMo 需要把 API key 和 Console Cookie 分开显示、分开清理。
- 优化认证/数据标识：
  - `未配置`
  - `已配置，未查询`
  - `已配置，暂无用量数据`
  - `认证过期`
  - `权限不足`
  - `平台不支持普通 API key 查询用量`
  - `网络错误`
- 小组件自定义选择增加搜索和筛选：
  - 支持按平台名、指标名搜索。
  - 支持按平台筛选。
  - 只展示该平台实际可提供或当前 UI 明确声明可用的指标。
- 为查询功能建立 `ProviderCapability` / `ProviderQueryStatus` 这类轻量模型，先服务 UI 和状态展示，后续迁到 `token_state` 时可以复用概念。
- 沉淀模型用量查询实践文档，记录哪些平台能查、需要什么权限、当前 token-hud 应如何展示。

### 实施步骤

1. **补充核心状态模型与测试**
   - 在 `Sources/token_hudCore` 增加平台能力/状态的纯模型，至少包含：
     - `credentialKind`
     - `usageCapability`
     - `credentialStatus`
     - `dataStatus`
     - `resetActions`
   - 在 `Tests/token_hudCoreTests` 覆盖：
     - OpenAI/Anthropic/Gemini 普通 API key => “可验证，不保证可查账单/用量”。
     - DeepSeek => “可查余额”。
     - MiniMax => “可查 Token Plan remains”。
     - Codex => “本地认证 + 本地 session 日志”。
     - MiMo => “API key 可验证，Console Cookie 可查 Token Plan”。

2. **实现 state.json 单平台清理**
   - 在 app 层增加一个小型 helper，读取当前 `stateFilePath`，删除指定 `services[platformID]`，写回文件。
   - 只清空对应 service，不改其他平台数据。
   - 失败时在 UI 显示明确错误，不吞掉。

3. **完善 Keychain 重置入口**
   - `KeychainHelper` 增加：
     - 删除 Claude session key 的公开方法。
     - 删除 legacy OpenAI key 的迁移/清理方法（如仍存在）。
     - 按平台删除 API key 的结果反馈。
   - Settings UI 中把“更换 Key / 删除配置”改成统一的 `重置认证`，必要时二次确认。
   - MiMo 分开提供：
     - `重置 API Key`
     - `重置 Console Cookie`
     - `清空 MiMo 数据`

4. **重构 Settings 外层布局**
   - 将 `SettingsWindow` 从 `TabView` 改为 `NavigationSplitView` 或等效侧边栏布局。
   - 窗口调整到更适合 dashboard 的尺寸，例如 `900 x 620`。
   - 侧边栏项目：
     - 小组件
     - 平台
     - 通用
   - 右侧保持现有小组件页和通用页行为，不在本轮重写全部视觉。

5. **重构平台页为 dashboard/detail**
   - 用一个 `selectedPlatformID` 控制详情页。
   - 平台列表统一展示所有平台，不再分 Claude / API Key / Codex 三套 UI。
   - 右侧详情拆成几个局部视图：
     - `PlatformStatusHeader`
     - `PlatformCredentialPanel`
     - `PlatformUsageCapabilityPanel`
     - `PlatformMetricsPanel`
     - `PlatformResetPanel`
   - 删除或逐步替换 `APIKeyGroupView` 与 `PlatformRowView` 里的重复凭据 UI。

6. **优化 Codex 状态**
   - 继续只读取 `~/.codex/auth.json` 和 `~/.codex/sessions`。
   - 区分：
     - 无 auth 文件：未配置。
     - access token 过期：认证过期，提示 `codex login`。
     - auth 有效但无 session 文件：已认证，暂无本地用量。
     - auth 有效且有 state 数据：显示 plan/email/窗口用量。
   - 不删除 `~/.codex/auth.json`，避免越权破坏 Codex 自身登录态。

7. **小组件选择搜索与筛选**
   - 扩展 `widgetCapabilities`，把 OpenAI、Gemini、Anthropic 这类“已配置但普通 key 不保证可查用量”的平台纳入能力说明，但默认只暴露确有数据来源的指标。
   - `CustomWidgetSheet` 改成搜索式选择：
     - 顶部搜索框。
     - 平台 filter。
     - 下方列表显示“平台 + 指标 + 支持状态”。
   - 选择指标后再选样式；样式只展示该指标可用的样式。

8. **查询功能低风险补齐**
   - 保留现有 DeepSeek、MiniMax、MiMo 拉取路径。
   - OpenAI/Anthropic/Gemini 本轮不伪造用量：
     - 如果没有足够权限或接口不适用于普通 key，写入明确 service error/status。
     - UI 显示“已配置，普通 API key 暂不支持用量查询；可后续添加组织/账单凭据”。
   - 对每个平台的 `fetchSingle` 行为补统一错误语义，避免 nil 导致 UI 只能显示“暂无数据”。

9. **沉淀文档**
   - 新增 `docs/model-usage-query-practices.md`。
   - 记录：
     - 各平台官方/成熟查询路径。
     - 需要的凭据类型。
     - 当前 token-hud 的实现状态。
     - 不建议做的路径，例如抓取普通网页 dashboard、把普通 API key 当账单 key。
   - 如本轮产生非平凡实现决策，完成后再按触发条件写 `docs/work-log/YYYY-MM-DD-settings-platform-query.md`。

### 验证

- `swift test --filter ProviderCapability`
- `swift test`
- `xcodebuild -project token_hud.xcodeproj -scheme token_hud -destination 'platform=macOS' build`
- 手动验证：
  - Settings 打开后默认进入新侧边栏布局。
  - 平台列表能切换 Claude、Codex、OpenAI、Gemini、DeepSeek、Anthropic、MiniMax、MiMo。
  - 每个平台能看到配置状态、查询能力和数据状态。
  - `重置认证` 删除凭据后状态立刻变成未配置。
  - `清空数据` 只删除当前平台 service，不影响其他平台。
  - Codex token 过期、未登录、无 session、有 session 四类状态文案不同。
  - 小组件自定义 sheet 可按平台和指标搜索/筛选。

### 风险

- 当前 `token_hud` 仍保留 app-side fetchers，但长期文档要求迁到 `token_state`；本轮不要继续扩大网络抓取复杂度，只建立清晰状态和 UI 边界。
- OpenAI、Anthropic、Gemini 的真实组织/账单用量查询可能需要额外凭据和权限，本轮如果强做会制造误导或权限错误。
- Settings 页面重构会影响多个 SwiftUI 文件，需要注意不要破坏已存在的小组件预览、App filter、floating panel 设置。
- Keychain 删除操作不可逆，UI 必须明确区分删除凭据和清空数据。

### 本轮实现结果（2026-06-06）

- Settings 外层已从 `TabView` 改成侧边栏导航，覆盖“小组件 / 平台 / 通用”。
- 平台页已改成统一 dashboard/detail：
  - 左侧平台列表展示认证状态和数据状态。
  - 右侧详情展示认证、查询能力、当前数据、重置操作。
- 新增 provider 能力/状态模型：
  - 普通 OpenAI/Anthropic/Gemini API key 标记为“可验证，不保证可查用量”。
  - DeepSeek 标记为官方余额接口。
  - MiniMax 标记为 Token Plan 接口。
  - MiMo 标记为 API key + Console Cookie。
  - Codex 标记为本地认证 + 本地 session 日志。
- 新增 `StateFile.removingService`，用于只清空某个平台的 `state.json` service。
- 新增 Keychain 重置入口：
  - Claude session key。
  - 平台 API key。
  - legacy OpenAI key。
  - MiMo Console Cookie。
- Codex 状态区分：
  - 未配置。
  - token 过期。
  - 已认证并展示 email/plan。
  - 不删除 `~/.codex/auth.json`，只提示 `codex login`。
- 小组件自定义 sheet 已支持：
  - 按平台筛选。
  - 按平台名/指标名搜索。
  - 根据指标展示可用样式。
- 查询语义已改为：
  - OpenAI/Anthropic/Gemini 普通 API key 持久化明确 `usageUnsupported` 状态，不再返回 nil。
  - 兼容旧 fetcher 错误字符串，如 `Network error`、`Invalid API key`、`Console login expired`。
- 新增长期文档：
  - `docs/model-usage-query-practices.md`
  - `docs/work-log/2026-06-06-settings-platform-query.md`

### 验证结果

- `swift test`：131 个测试通过。
- `xcodebuild -project token_hud.xcodeproj -scheme token_hud -destination 'platform=macOS' build`：通过。

### 待手动验证

- 打开 Settings，确认侧边栏导航、小组件、平台、通用三页切换正常。
- 在平台页切换 Claude、Codex、OpenAI、Gemini、DeepSeek、Anthropic、MiniMax、MiMo。
- 手动验证 `重置认证` 与 `清空数据` 的交互符合预期。
- 手动验证小组件自定义 sheet 搜索和平台筛选。

---

## 当前重点：修复鼠标到屏幕最顶端时展开后立刻收回（已实现，待真机验证）

### 问题

用户反馈：当前整体效果基本可用，但当鼠标拉到最顶端时，刘海面板会弹开又立刻缩回。

本轮排查后判断根因在 hover 停留区：

- `handleMouseMove` 在 hosted expanded 状态下调用 `isMouseInNotchRegion()`。
- `isMouseInNotchRegion()` 当前逻辑：
  - 先检查 collapsed compact 的 `notchHoverRegions`。
  - 如果鼠标不在 compact hover region，expanded 状态下只额外检查 `layout.body`。
- 这会漏掉一个关键区域：expanded 状态的 `layout.topCap`。
- 当鼠标在屏幕最顶端、停在 expanded topCap 或菜单栏顶边附近时：
  - 它可能已经不在 collapsed compact hover region。
  - 又不在下方 body。
  - 于是被判定为 outside，立刻 `scheduleCollapse()`，表现为弹开后马上缩回。

参考 `docs/notch-dynamic-island-implementation-reference.md` 里 hover / hit mask 约定，expanded 的可停留区域应该是 `topCap ∪ body`，不能只看 body。

### 本轮目标

- expanded 状态下，鼠标停在 topCap、刘海顶边、body 内部都应保持展开。
- 鼠标真正离开 `topCap ∪ body` 后，再按现有 delay 收回。
- 不扩大 collapsed 触发区到整条菜单栏，避免误触。
- 保持 hit mask 和 hover stay region 一致：expanded 都使用 `topCap.union(body)`。

### 实施步骤

1. **补充可测试策略**
   - 在 `NotchSurfacePolicy` 增加纯函数，用于根据 mode 和区域包含关系决定 hover action。
   - 增加测试覆盖：
     - expanded + mouse inside topCap => cancel collapse / keep open。
     - expanded + mouse inside body => cancel collapse / keep open。
     - expanded + mouse outside surface => schedule collapse。
   - 这样避免后续又把 expanded topCap 从停留区漏掉。

2. **修正 `isMouseInNotchRegion()`**
   - collapsed 继续使用 `NotchGeometryCalculator.notchHoverRegions(...)`。
   - expanded 时计算 hosted surface layout，并把 `layout.topCap.union(layout.body)` 转换到屏幕坐标。
   - 对该 union 做适度 inset padding，作为 expanded stay region。
   - 鼠标在 expanded stay region 内则返回 `true`。

3. **保持触发区不泛化**
   - 不修改 collapsed hover region 的宽度。
   - 不把整条菜单栏设为 hover target。
   - 不单纯增加 collapse delay 作为症状修补。

4. **验证**
   - `swift test --filter NotchSurfacePolicyTests`
   - `swift test`
   - `xcodebuild -project ../token_hud.xcodeproj -scheme token_hud -destination 'platform=macOS' build`
   - 真机验证：
     - 鼠标移到屏幕最顶端时，展开后不会立刻收回。
     - 鼠标停在 expanded topCap 内能保持展开。
     - 鼠标离开整个 topCap/body 后能正常收回。

### 本轮实现结果（2026-06-04）

- 新增 `NotchHoverRegionPolicy` 纯策略：
  - collapsed：只认 collapsed compact hover region，避免扩大初始触发区。
  - expanded：认 `collapsedHoverRegion || expandedSurface`，避免 expanded topCap 被误判为离开。
  - detached：不参与刘海 hover。
- `NotchHostPanelManager.isMouseInNotchRegion()` 已改为：
  - 先计算 collapsed compact hover region。
  - expanded 状态下额外计算 `layout.topCap.union(layout.body)`，转换为屏幕坐标，并复用现有 hover padding。
  - 通过 `NotchHoverRegionPolicy` 统一决定鼠标是否仍在刘海区域。
- 修复后的语义：
  - 鼠标在 expanded topCap、刘海顶边附近或 body 内部时保持展开。
  - 鼠标真正离开 `topCap ∪ body` 后才安排收回。
  - collapsed 初始触发范围不变，不会扩大到整条菜单栏。

### 验证结果

- `swift test --filter NotchSurfacePolicyTests`：16 个测试通过。
- `swift test`：124 个测试通过。
- `xcodebuild -project ../token_hud.xcodeproj -scheme token_hud -destination 'platform=macOS' build`：通过。

### 风险

- expanded topCap stay region 如果 padding 过大，可能让鼠标在菜单栏附近停留时不容易收回；第一版只复用现有 `collapsedHoverPadding`。
- 如果 SkyLight / public fallback 下窗口实际 frame 和视觉 frame 不一致，仍可能需要额外诊断日志打印 expanded stay region。

---

## 当前重点：修复 Xcode 运行 attach by pid 失败（已实现，待手动 Run 验证）

### 问题

用户在 Xcode 运行 app 时遇到：

```text
error: attach by pid '40216' failed -- attach failed (attached to process, but could not pause execution; attach failed)
```

本轮排查结果：

- `xcodebuild -project ../token_hud.xcodeproj -scheme token_hud -destination 'platform=macOS' build` 能通过，说明不是编译错误。
- 当前 `project.yml` / `project.pbxproj` 配置为：
  - `CODE_SIGNING_ALLOWED = NO`
  - `CODE_SIGNING_REQUIRED = NO`
  - `CODE_SIGN_STYLE = Manual`
- 默认构建出的 Debug app bundle 不是有效签名产物：
  - `codesign --verify --verbose=4 .../token_hud.app` 报错：
    - `code has no resources but signature indicates they must be present`
  - 该状态下 Xcode/LLDB attach 到 app pid 可能失败。
- 用命令行临时覆盖签名参数验证：
  - `CODE_SIGNING_ALLOWED=YES CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=-`
  - 构建成功，并执行了 `CodeSign ... Sign to Run Locally`。
  - 新产物 `codesign --verify --verbose=4` 通过。
  - entitlements 包含 `com.apple.security.get-task-allow = true`。

因此当前根因判断是：为了跳过签名而禁用 code signing，导致 Debug app bundle 签名无效，Xcode 可以构建但 LLDB 无法稳定 attach。

### 本轮目标

- 让本地 Debug 构建默认使用 ad-hoc signing（`Sign to Run Locally`）。
- 保持不依赖 Apple Developer Team，不引入正式证书要求。
- 确保 Xcode 直接 Run 时产物带 `get-task-allow = true`，LLDB 可以 attach。
- 保持命令行 `xcodebuild` 验证仍可通过。

### 实施步骤

1. **修改 XcodeGen 配置**
   - 在 `project.yml` 中把 target signing 配置改为：
     - `CODE_SIGNING_ALLOWED: "YES"`
     - `CODE_SIGNING_REQUIRED: "YES"`
     - `CODE_SIGN_STYLE: Manual`
     - `CODE_SIGN_IDENTITY: "-"`
     - `DEVELOPMENT_TEAM: ""`
   - 保留现有 `CODE_SIGN_ENTITLEMENTS: token_hud/token_hud.entitlements`。

2. **同步 Xcode 工程**
   - 优先运行 `xcodegen generate` 重新生成 `token_hud.xcodeproj`。
   - 如果本地 `xcodegen generate` 因既有工程复制冲突失败，则对 `project.pbxproj` 做等价最小修改，保持和 `project.yml` 一致。

3. **验证签名和构建**
   - 运行：
     - `xcodebuild -project ../token_hud.xcodeproj -scheme token_hud -destination 'platform=macOS' build`
     - `codesign --verify --verbose=4 <Debug token_hud.app>`
     - `codesign -d --entitlements :- <Debug token_hud.app>`
   - 确认：
     - app bundle valid on disk。
     - entitlements 包含 `com.apple.security.get-task-allow = true`。

4. **给出运行建议**
   - 如果 Xcode 仍旧 attach 失败，建议清理旧 DerivedData 或重新打开 project，因为旧无效签名产物可能仍被 Xcode 缓存。

### 本轮实现结果（2026-06-04）

- `project.yml` 已把 target signing 改成本地 ad-hoc signing：
  - `CODE_SIGNING_ALLOWED: "YES"`
  - `CODE_SIGNING_REQUIRED: "YES"`
  - `CODE_SIGN_IDENTITY: "-"`
  - `CODE_SIGN_STYLE: Manual`
  - `DEVELOPMENT_TEAM: ""`
- `token_hud.xcodeproj/project.pbxproj` 已做等价最小同步：
  - Debug / Release target build settings 均改为 `CODE_SIGNING_ALLOWED = YES`、`CODE_SIGNING_REQUIRED = YES`、`CODE_SIGN_IDENTITY = "-"`。
- 已尝试运行 `xcodegen generate`，但仍遇到既有工程复制冲突：
  - `XcodeGen couldn’t be copied to token_hud because an item with the same name already exists`
  - 因此本轮没有依赖 xcodegen 输出，而是手动保持 `project.yml` 与 `project.pbxproj` 一致。
- 默认 `xcodebuild` 不再需要命令行 signing override，构建过程会执行：
  - `Signing Identity: "Sign to Run Locally"`
  - `CodeSign ... token_hud.app`
- 产物 entitlements 已包含：
  - `com.apple.security.get-task-allow = true`
  - `com.apple.security.app-sandbox = false`

### 验证

- `xcodebuild -project ../token_hud.xcodeproj -scheme token_hud -destination 'platform=macOS' build`：通过，并执行 `Sign to Run Locally`。
- `codesign --verify --verbose=4 /Users/lauzanhing/Library/Developer/Xcode/DerivedData/token_hud-hilycrftzevwvucmmyckksjjimrz/Build/Products/Debug/token_hud.app`：通过，`valid on disk`。
- `codesign -d --entitlements :- /Users/lauzanhing/Library/Developer/Xcode/DerivedData/token_hud-hilycrftzevwvucmmyckksjjimrz/Build/Products/Debug/token_hud.app`：通过，包含 `get-task-allow = true`。
- `swift test`：121 个测试通过。
- 手动验证：
  - Xcode 直接 Run 不再出现 `attach by pid ... failed`。

### 风险

- ad-hoc signing 只适合本地开发运行，不是发布签名。
- 如果 Xcode 仍从旧 DerivedData 启动旧 app，需要清理 DerivedData 后再验证。
- 如果用户机器的 Xcode scheme 覆盖了 signing 设置，仍可能需要检查 scheme 的 Run 配置。

---

## 当前重点：修复 hosted compact 悬停不展开（已实现，待真机验证）

### 问题

当前样式已回到“单一 hosted surface + compact top cap/status slot”的方向，但用户反馈鼠标悬停后无法展开。结合 `docs/notch-dynamic-island-implementation-reference.md` 与 `docs/notch-open-source-research.md` 复查，触发机制存在明显冲突：

- 代码已有 `NotchTrackingContainerView.hitTest` 和 `hostedHitMask(in:)`，目标是只让 `topCap` / `body` 这些可见区域接收事件，透明区域穿透到菜单栏或桌面。
- 但 hosted 收起态多处把 `overlayWindow?.ignoresMouseEvents` 设为 `true`：
  - `animateToCollapsed`
  - `snapToCollapsed`
  - `screenParametersChanged`
  - `restoreState`
- 一旦 window 整体忽略鼠标，`hitTest`、tracking area、SwiftUI hover、本地 mouse monitor 都不会生效，只能依赖 `NSEvent.addGlobalMonitorForEvents(.mouseMoved)`。
- global monitor 对系统菜单栏、当前 app 自身 window、Space/私有层级里的事件并不稳定；成熟实现通常会把“透明区域穿透”和“可见触发区接收事件”拆开，而不是让整个 window ignore mouse。

因此本轮判断根因是：收起态事件策略错了，不是 hover region 的视觉尺寸或位置单独没调好。

### 本轮目标

- hosted compact 收起态仍保持菜单栏/透明区域不被大面积遮挡。
- compact 可见 top cap/status slot 区域能够稳定触发 hover expand。
- expanded 状态鼠标离开 top cap/body 后仍能按当前策略延迟收回。
- 触发路径对菜单栏区域、SkyLight hosted surface、public fallback 都尽量一致。
- 用纯逻辑测试锁住“hosted window 不应整体忽略鼠标”的策略，避免后续又改回旧路线。

### 实施步骤

1. **补失败测试**
   - 在 `NotchSurfacePolicyTests` 增加 mouse event policy 测试：
     - `.collapsed` hosted window 不应设置 `ignoresMouseEvents = true`。
     - `.expanded` hosted window 不应设置 `ignoresMouseEvents = true`。
     - `.detached` window 不应设置 `ignoresMouseEvents = true`。
   - 这个测试锁定核心原则：由 `hitTest` / hit mask 控制穿透，不由整窗 ignore mouse 控制穿透。

2. **新增 Notch mouse event policy**
   - 在 `NotchSurfacePolicy.swift` 增加 `NotchMouseEventPolicy`。
   - `NotchHostPanelManager` 所有 hosted/detached 状态切换统一调用该 policy，不再分散写 `hostState.isCollapsed` 或硬编码 `true/false`。

3. **改 hover monitor 策略**
   - 保留 global mouse monitor，用于鼠标在其他 app / 桌面区域移动时判断进入或离开刘海区域。
   - 增加 local mouse moved monitor，用于鼠标进入本 app hosted window 可见 top cap/body 后稳定触发。
   - `makeWindow` 对 hosted surface 设置 `acceptsMouseMovedEvents = true`。
   - local/global 两条路径最终进入同一个 `handleMouseMove`，避免状态机分叉。

4. **让 hit mask 真正接管穿透**
   - 收起态 overlay window 保持 `ignoresMouseEvents = false`。
   - `NotchTrackingContainerView.hitTest` 继续只允许 `hostedHitMask` 内部命中：
     - collapsed：`topCap`
     - expanded：`topCap.union(body)`
   - 这样 compact 可见区域能接收 hover，透明区域仍可穿透。

5. **补触发诊断**
   - hover expand/collapse 决策点打印轻量日志：
     - event source：global / local
     - 当前 mode
     - mouse 是否在 notch region
   - 日志只在状态动作发生时输出，避免鼠标移动刷屏。

### 本轮实现结果（2026-06-04）

- 新增 `NotchMouseEventPolicy`：
  - `.collapsed` / `.expanded` / `.detached` 都不再要求整窗 `ignoresMouseEvents = true`。
  - 核心原则改为：window 保持接收鼠标，透明区域穿透交给 `hostedHitMask(in:)` 和 `NotchTrackingContainerView.hitTest`。
- `NotchHostPanelManager` 已移除 hosted 收起态整窗忽略鼠标的写法：
  - `animateToCollapsed`
  - `snapToCollapsed`
  - `screenParametersChanged`
  - `restoreState`
- hosted / detached 状态切换统一通过 `NotchMouseEventPolicy.shouldIgnoreWindowMouseEvents(mode:)` 设置 window 事件策略。
- hosted surface window 设置 `acceptsMouseMovedEvents = true`。
- hover 触发从单一路径改为双路监听：
  - global mouse monitor：继续覆盖鼠标在其他 app / 桌面区域移动的情况。
  - local mouse monitor：覆盖鼠标进入本 app hosted top cap/body 后的事件，避免只依赖 global monitor。
- local/global mouse move 统一进入同一个 `handleMouseMove`：
  - collapsed + inside：展开。
  - expanded + outside：只在没有 pending timer 时安排收起，避免反复重建 timer。
  - expanded + inside：只在存在 pending timer 时取消，避免鼠标移动刷日志。
- hover 状态动作发生时输出轻量诊断：
  - `source`
  - `action`
  - `mode`
  - `mouseInsideNotchRegion`

### 验证

- `swift test --filter NotchSurfacePolicyTests`：13 个测试通过。
- `swift test`：121 个测试通过。
- `xcodebuild -project ../token_hud.xcodeproj -scheme token_hud -destination 'platform=macOS' build`：通过。
- 真机验证：
  - app 启动后 hosted compact 收起态只显示刘海两侧状态。
  - 鼠标移动到 compact top cap/status slot 上能稳定展开。
  - 鼠标离开展开 body 后能稳定收回。
  - 透明区域不吞掉菜单栏点击。
  - detached 后再次吸附回刘海，hover 仍可展开。

### 风险

- hosted window 由 `ignoresMouseEvents = true` 改为 `false` 后，如果 hit mask 计算错误，可能短暂吞掉比预期更大的菜单栏区域；需要用真机点击菜单栏验证。
- local/global monitor 同时存在，可能重复触发同一状态动作；需要通过 `NotchTransitionPolicy` 和当前 mode guard 保持幂等。
- SkyLight 私有 Space 下事件分发可能和 public fallback 不完全一致；如果 local monitor 仍不触发，需要进一步在 `NotchTrackingContainerView` 增加 tracking area / `mouseEntered` 兜底。

---

## 当前重点：按 Notch 参考文档纠偏 hosted 实现（已实现，待真机验证）

### 问题

根据 `docs/notch-dynamic-island-implementation-reference.md` 和 `docs/notch-open-source-research.md` 对当前实现复查后，主方向已经从“多个黑块/shoulder cap 拼接”回到“单一 hosted surface + compact 左右 slot”，但仍有几处实现路径不够稳：

- `SkyLightNotchSpace` 对私有 API 调用结果判定不严：
  - `SLSSpaceSetAbsoluteLevel` / `SLSShowSpaces` 的返回值被忽略。
  - `SLSSpaceAddWindowsAndRemoveFromSpaces` 无论返回码是什么都返回成功。
  - 这会导致日志显示 `skyLightSpace` 已启用，但实际 window 可能没有成功进入目标 Space，是“仍然无法进入菜单栏区域”的高风险点。
- `publicPanel` fallback 使用 `.screenSaver` window level，和参考文档里的公开路线不一致：
  - 成熟开源项目更常用 `.statusBar` 或 `.mainMenu + n`。
  - `.screenSaver` 可能过度遮挡系统 UI，也可能影响拖拽、菜单栏事件和系统交互。
- hosted 展开/收起状态机仍然过粗：
  - 当前主要只有 `collapsed` / `expanded` / `detached`。
  - `isAnimating` 基本没有真正约束 SwiftUI 动画。
  - 快速 hover in/out 或拖拽中断时，仍可能出现动画抢占、状态抖动或 hit mask 与视觉不同步。
- 旧 `NotchFusionLayout` / `NotchFusionView` 路线仍保留：
  - 当前 root view 已使用 `NotchHostedSurfaceView`，旧 Fusion 路线看起来不再是主路径。
  - 但旧 layout、旧 view、旧测试还在，会误导后续继续沿错误模型开发。

### 本轮目标

- 让 SkyLight / CGS 路线的成功或失败可被可靠判断，避免“日志显示成功但实际未进入菜单栏”的假阳性。
- 把公开 fallback 调整成更接近成熟项目的 window level 策略，并明确它只提供近似效果。
- 补上 hosted transition generation / phase 管理，让 hover、收起、展开、拖拽脱离之间不会互相抢状态。
- 清理或明确标记旧 Fusion 路线，避免后续开发再次回到旧模型。

### 实施步骤

1. **修正 SkyLight 成功判定**
   - `SkyLightNotchSpace` 记录并暴露：
     - `spaceSetAbsoluteLevel` 返回码。
     - `showSpaces` 返回码。
     - `delegateWindow` 返回码。
   - 只有关键调用返回成功时，`delegateWindow(_:)` 才返回 `true`。
   - 如果任一步失败，诊断日志明确输出失败阶段和返回码。
   - `NotchHostPanelManager.prepareOverlayForDisplay` 根据真实 delegate 结果决定是否继续标记 `overlayDelegatedToSkyLight`。

2. **调整 public fallback window level**
   - 将 `NotchSurfaceStrategy.publicPanel.windowLevel` 从 `.screenSaver` 调整到更保守的 `.statusBar` 或 `.mainMenu + 3`。
   - 保留 `skyLightSpace` 使用 `.mainMenu + 3` + private Space 的策略。
   - 在诊断日志中明确标注：
     - 当前是 `skyLightSpace` 还是 `publicPanel`。
     - public fallback 不承诺 100% 覆盖菜单栏左右两侧。

3. **补 hosted transition phase / generation**
   - 在 `NotchHostState` 或 `NotchHostPanelManager` 中增加 transition generation。
   - 每次 hover expand、collapse timer、drag detach、snap back 都递增 generation。
   - 延迟任务和动画 completion 只允许当前 generation 生效。
   - 必要时引入轻量 phase：`collapsed`、`expanding`、`expanded`、`collapsing`、`detached`，或保持 public mode 不变、内部增加 transition phase。

4. **清理旧 Fusion 路线**
   - 搜索并确认 `NotchFusionView` 是否仍被 app target 使用。
   - 如果未使用：
     - 删除 `NotchFusionView`。
     - 删除 `NotchFusionLayout` 和 `notchFusionLayout`。
     - 删除旧 Fusion layout 测试。
   - 如果仍需要保留兼容代码，则显式标记为 legacy，并确保不会被 hosted 新路线引用。

5. **补充测试**
   - SkyLight wrapper 的返回码逻辑拆成可测试的小结构或状态判断函数。
   - 增加 `NotchSurfaceStrategy` level 测试或静态断言，避免 fallback 再回到 `.screenSaver`。
   - 增加 transition generation 测试：
     - 旧 collapse timer 不应覆盖新的 expanded 状态。
     - 快速 hover out/in 后，最后一次事件决定最终状态。
   - 删除旧 Fusion 测试后，确保 hosted surface 测试覆盖 compact slot、top cap、body、hover region。

### 本轮实现结果（2026-06-04）

- 新增 `NotchSurfacePolicy` 纯逻辑：
  - `SkyLightReturnCodePolicy` 统一判断 SkyLight / CGS 返回码，当前仅把 `0` 视为成功。
  - `NotchSurfaceLevelPolicy` 明确 `skyLightSpace` 使用 `.mainMenu + 3`，`publicPanel` 使用 `.statusBar`，不再使用 `.screenSaver` 作为 hosted fallback。
  - `NotchTransitionPolicy` 和 `NotchTransitionGate` 为 hover/collapse 的 generation 防抖提供可测试基础。
- `SkyLightNotchSpace` 已记录并输出：
  - `setAbsoluteLevelReturnCode`
  - `showSpacesReturnCode`
  - `lastDelegateReturnCode`
  - 如果 Space setup 或 delegate 返回码失败，不再误报成功。
- `NotchHostPanelManager` 已接入真实 delegate 结果：
  - SkyLight delegate 失败时，立即降级为 `publicPanel`。
  - hover 在 expanded 状态重新进入 top cap/body 时，会取消 pending collapse，避免旧 timer 把当前展开态收回。
  - collapse timer 使用 generation token，过期任务不会再生效。
- 已删除旧 hosted 路线文件和工程引用：
  - `NotchFusionView.swift`
  - `NotchCollapsedView.swift`
  - `NotchExpandedView.swift`
  - `NotchEarView.swift`
  - 对应旧 `NotchFusionLayout` / `notchFusionLayout` 和旧 Fusion tests 已删除。
- `xcodegen generate` 本轮因现有 `token_hud.xcodeproj` 复制冲突失败；已手动对 `project.pbxproj` 做等价最小更新：
  - 新增 `NotchSurfacePolicy.swift`。
  - 移除已删除 legacy Swift 文件引用。

### 验证

- `swift test --filter NotchSurfacePolicyTests`：11 个测试通过。
- `swift test --filter NotchGeometryCalculator`：45 个测试通过。
- `swift test`：119 个测试通过。
- `xcodebuild -project ../token_hud.xcodeproj -scheme token_hud -destination 'platform=macOS' build`：通过。
- 真机验证：
  - 日志能明确显示 SkyLight 每一步是否成功。
  - 如果 SkyLight 失败，界面降级到 public fallback，并且日志不再误报成功。
  - 快速 hover in/out 不出现展开/收起状态错乱。
  - 拖拽脱离和再次吸附后，hosted top cap 仍回到 canonical geometry。
  - app 内不再存在可被误用的旧 Fusion 主路径。

### 风险

- SkyLight / CGS 是私有 API，不同 macOS 版本返回码语义可能有差异；需要先记录真实返回值，再决定是否兼容多种“成功码”。
- 降低 public fallback level 后，如果 SkyLight 不可用，菜单栏融合能力可能变弱；但这比 `.screenSaver` 误伤系统 UI 更可控。
- transition phase 改动会影响 hover、drag、snap 多条路径，需要保持范围集中并用测试锁住。
- 删除旧 Fusion 路线前要确认没有 storyboard/project target 或预览仍引用它。

---

## 当前重点：重做刘海融合 compact 形态（开源路线纠偏，已实现，待真机验证）

### 问题

用户在 2026-06-04 的截图中指出，当前 “左右小格 + shoulder cap” 适配完全不对：

- 刘海两边出现两个孤立的黑色竖块，视觉上不像从刘海自然延展。
- 左侧进度和右侧百分比被拆成两个独立面板，中间缺少连续轮廓。
- 当前方案是在错误形态上继续补边，不能再沿用。

本轮系统性排查后判断，根因不是参数没调好，而是形态建模错了：我们把刘海融合拆成了多个局部黑块，再用 `leftShoulder` / `rightShoulder` 去补缝。这会天然产生断裂、竖边和定位不稳定，和用户要的“刘海弹开”相反。

### 开源调研结论

已重新查看 Boring Notch、Atoll、SuperIsland 的公开仓库和源码，关键做法如下：

- Boring Notch / Atoll：
  - 使用单个居中的 notch surface，而不是多个左右窗口或多个孤立黑块。
  - 通过 `auxiliaryTopLeftArea` / `auxiliaryTopRightArea` 计算真实刘海宽度。
  - 用一个 `NotchShape` 统一裁剪外壳，顶部和底部圆角是同一个 shape 的参数。
  - 强融合/锁屏等场景使用 SkyLight / CGS Space 提升窗口层级。
- SuperIsland：
  - 使用透明 `NSPanel`，`statusBar` level，窗口根据 notch rect 居中贴顶。
  - hosting view 保持最大尺寸，window 作为 clipping viewport，展开前先放大 viewport，收起动画结束后再缩回 compact，避免 SwiftUI relayout 跑偏。
  - compact 状态在 notched Mac 上支持 `minimalLeading` / `minimalTrailing` 两侧内容，但它们在同一个 compact surface 内渲染，中间让硬件刘海自然隐藏，而不是画两个独立竖块。

因此，本项目应废弃当前 “左右独立小格 + shoulder cap” 路线，改成“单一连续 top cap + 下拉 body”的路线。

### 本轮目标

- 删除/停用当前错误形态：
  - 移除 `NotchHostedSurfaceLayout.leftShoulder` / `rightShoulder`。
  - 移除 `NotchShoulderCapShape`。
  - 不再绘制两个脱离主轮廓的黑色竖块。
- 重建 compact 刘海形态：
  - collapsed 时只保留一个连续的 top cap，宽度 = 真实刘海宽度 + 左右状态槽扩展。
  - top cap 顶边贴住 `screen.frame.maxY`，以菜单栏真实区域为定位基准。
  - 左侧进度条和右侧百分比作为 top cap 内部的 leading/trailing status slot，不作为独立面板。
  - 中间刘海区域保持纯黑/空内容，由硬件刘海自然吞掉，避免在中间画条。
  - 外侧底角使用同一个连续 shape 的圆角，不再用额外黑块补缝。
- 重建展开动画：
  - hover top cap 时，body 从刘海下方向下延展。
  - compact top cap 始终是展开动画的锚点；body 高度和宽度向下/向外插值。
  - 内容在 body 高度足够后淡入，避免一开始文字压在菜单栏区域。
- 重建 hitbox：
  - collapsed 命中区覆盖整个 top cap，不覆盖整条菜单栏。
  - expanded 命中区覆盖 top cap + body。
  - 不再只依赖很小的左右小格作为触发区。
- 保持定位稳定：
  - hosted 仍以目标 screen 的 notch rect / frame 顶部定位。
  - 拖拽/吸附期间不根据鼠标所在屏幕反复切换目标 screen。
  - 展开时 window 可临时使用最大尺寸作为 clipping viewport；收起动画结束后再缩回 compact，避免定位漂移。

### 实施步骤

1. **补充失败测试**
   - 在 `NotchGeometryCalculatorTests` 中新增 compact top cap 测试：
     - collapsed 布局只有一个连续 `topCap`，不再有 `leftShoulder/rightShoulder`。
     - `leftStatusSlot` 和 `rightStatusSlot` 必须完全包含在 `topCap` 内。
     - `topCap.width` 至少覆盖真实 notch gap，并根据安全边距限制左右扩展。
     - collapsed 可见高度不应产生向下悬挂的大竖块。
   - 新增 hover 测试：
     - collapsed hover region 覆盖整个 `topCap`。
     - hover region 不覆盖整条 screen 顶部。

2. **重写 geometry 模型**
   - 将 hosted surface layout 从 “left ear/right ear/body/shoulder” 改成：
     - `topCap`
     - `leftStatusSlot`
     - `rightStatusSlot`
     - `body`
     - `contentOpacity`
   - compact 宽度计算参考 SuperIsland：
     - 基础宽度取真实 notch width。
     - 左右扩展先用 44-56pt。
     - 如果左右菜单栏安全空间不足，则自动缩小或关闭 side status。
   - expanded 继续使用现有目标宽度，但从 `topCap` 中心连续插值。

3. **重写 `NotchHostedSurfaceView`**
   - 用同一个连续 top cap 和下拉 body 绘制黑色外壳。
   - collapsed 时只显示 top cap 和内部 status slot。
   - expanded 时同一个 shape 向下长出 body。
   - 移除 `NotchShoulderCapShape` 和独立 shoulder 绘制。
   - 左右状态只作为 overlay 内容渲染在 `leftStatusSlot/rightStatusSlot` 内。

4. **调整 `NotchHostPanelManager`**
   - hit mask 改为 `topCap.union(body)`。
   - hover 判定改为 compact top cap / expanded surface。
   - 保留“展开前窗口放大、收起后延迟缩回”的 clipping viewport 思路，避免再次出现拖拽后位置随机偏移。

5. **文档沉淀**
   - 实现完成后新增 `docs/work-log/2026-06-04-notch-fusion-rebuild.md`。
   - 文档里记录：废弃 shoulder cap 的原因、参考开源项目的架构原则、最终 geometry 约定。

### 本轮实现结果（2026-06-04）

- `NotchHostedSurfaceLayout` 已从 “left/right ear + left/right shoulder + body” 改为：
  - `topCap`
  - `notchGap`
  - `leftStatusSlot`
  - `rightStatusSlot`
  - `body`
  - `contentOpacity`
- collapsed 状态只保留一个连续 `topCap`：
  - `topCap` 覆盖真实 notch gap 和左右状态槽。
  - 左侧进度条、右侧百分比都在 `topCap` 内部渲染，不再作为独立黑块。
  - `body.height == 0`，避免收起时向屏幕下方悬挂一大块。
- expanded 动画从同一个 `topCap` 往下长出 `body`：
  - 黑色 body 在高度增长时先出现。
  - body 内容通过 `contentOpacity` 延迟淡入，避免文字挤在菜单栏区域。
- hover / hitbox 已改为新模型：
  - collapsed hover region 是一个围绕 `topCap` 的连续区域。
  - collapsed 点击命中只接收 `topCap`。
  - expanded 点击命中接收 `topCap.union(body)`。
- 已删除 hosted surface 里的 shoulder cap 绘制路径，不再用左右补丁块遮缝。

### 验证

- `swift test --filter NotchGeometryCalculator`：已通过，48 个 geometry 相关测试通过。
- `swift test`：已通过，111 个测试通过。
- `xcodebuild -project ../token_hud.xcodeproj -scheme token_hud -destination 'platform=macOS' build`：已通过。
- 真机验证：
  - collapsed 时不能再出现两个孤立竖块。
  - 刘海两侧只在同一个 top cap 内显示进度/百分比。
  - 鼠标移到 top cap 任意位置都能展开。
  - 展开动画从刘海区域向下长出，收回时缩回 top cap。
  - 拖拽后再次吸附，位置稳定，不随机偏移。

### 风险

- 公开 `NSPanel` 路线仍可能受菜单栏层级限制；如果需要 100% 覆盖菜单栏，仍要回到 SkyLight / CGS 策略。
- 不同机型 notch 宽度和菜单栏图标密度不同，side status 需要根据安全空间动态缩小。
- 不能复制 GPL 项目源码；只吸收架构原则，重新实现本项目自己的 geometry 和 shape。

---

## 历史记录：修复刘海圆角缝隙并明确触发标识（已实现，但已判定不可接受）

### 问题

用户在 2026-06-04 的截图中指出两个问题：

1. 当前 collapsed 左右小格靠近刘海的一侧是直角，没有考虑真实刘海下方左右两个角的弧度，导致小格和刘海之间出现蓝色镂空缝隙，视觉很不自然。
2. 触摸下拉的范围不明确，用户不知道应该摸哪里才能展开。

用户提出两个方向：

- 完全覆盖，让所有地方都可触发。
- 给出明确视觉标识。

### 当前判断

不建议回到“整条菜单栏都可触发”，因为这会重新引入误触：鼠标扫过任意菜单栏位置都会展开。更合适的路线是：

- 可见层：保留左右小格，但补上刘海底部圆角过渡，让小格与刘海视觉融合。
- 交互层：给左右小格一个明确的触发标识，同时把隐形 hitbox 扩大到比可见标识更容易摸到。

### 本轮目标

- 解决刘海下方左右圆角导致的镂空缝隙：
  - 左右小格靠近 notch gap 的一侧增加黑色圆角过渡/shoulder cap。
  - 过渡层应向刘海下方轻微覆盖 8-12pt，遮住真实刘海圆角外侧的背景缝。
  - collapsed 和 expanded 过程中都不应露出明显蓝色缝。
- 触发范围明确：
  - 左右小格内增加轻量视觉标识，例如底部短横/亮点。
  - 标识不应喧宾夺主，保持弱对比。
  - 实际 hover hitbox 大于可见小格，例如可见 44pt，命中宽度约 64-72pt。
- 保持上一轮策略：
  - hosted window 仍固定 expanded frame。
  - 展开/收回仍由 `expansionProgress` 驱动。
  - 不回退到 window resize 动画。

### 本轮实现结果（2026-06-04）

- `NotchHostedSurfaceLayout` 新增：
  - `leftShoulder`
  - `rightShoulder`
- `NotchGeometryCalculator` 新增常量：
  - `notchShoulderWidth = 12`
  - `notchShoulderDrop = 10`
  - `collapsedTriggerHitPadding = 14`
  - `collapsedHoverPadding` 改为复用 `collapsedTriggerHitPadding`
- `hostedSurfaceLayout` 计算左右 shoulder rect：
  - 左 shoulder 贴住 `notchGap.minX`，向下覆盖 `10pt`。
  - 右 shoulder 贴住 `notchGap.maxX`，向下覆盖 `10pt`。
  - 用于遮住刘海底部圆角外侧的蓝色缝隙。
- `notchHoverRegions` 的可触发 hitbox 从 44pt 可见小格扩大到 72pt 宽，但仍只围绕左右小格，不覆盖整条菜单栏。
- `NotchHostedSurfaceView` 新增：
  - `NotchShoulderCapShape`，绘制左右黑色圆角过渡块。
  - 小格底部低透明短 handle，给用户明确触发位置。
- `NotchHostPanelManager.hostedHitMask` 把 shoulder rect 也纳入 hosted 可交互区域，避免可见黑色过渡块穿透异常。
- `NotchGeometryCalculatorTests` 新增 shoulder cap 与 widened hitbox 测试。

验证结果：

- `swift test --filter NotchGeometryCalculator` 通过，49 个测试通过。
- `swift test` 通过，112 个测试通过。
- `xcodebuild -project ../token_hud.xcodeproj -scheme token_hud -destination 'platform=macOS' build` 通过。

### 实施步骤

1. **补充 geometry/layout 测试**
   - 在 `NotchHostedSurfaceLayout` 增加左右 shoulder/corner fill rect。
   - 测试 collapsed 下：
     - left/right shoulder 与 notch gap 左右边相邻或轻微覆盖。
     - shoulder 高度覆盖菜单栏底部到 body 顶部附近的过渡区。
   - 测试 hover region：
     - hover region 宽度大于可见 pill 宽度。
     - hover region 仍不覆盖整条菜单栏。

2. **调整 `NotchGeometryCalculator`**
   - 新增常量：
     - `notchShoulderWidth`，建议 12pt。
     - `notchShoulderDrop`，建议 10pt。
     - `collapsedTriggerHitPadding`，建议 14pt。
   - `hostedSurfaceLayout` 返回左右 shoulder rect。
   - `notchHoverRegions` 使用更大的 hit padding，但仍只围绕左右小格。

3. **调整 `NotchHostedSurfaceView`**
   - 在 ears/body 之前或之后绘制 shoulder cap：
     - 黑色填充。
     - 用圆角/Path 形成内侧圆角过渡，避免直角贴刘海。
   - 左右小格增加触发标识：
     - 左侧可在进度条下方或底部中央加很短的浅色 handle。
     - 右侧百分比旁或底部加对应 handle。
   - body 顶部保持与 shoulder cap 同色，避免 expanded 时断层。

4. **验证**
   - 运行 `swift test --filter NotchGeometryCalculator`。
   - 运行 `swift test`。
   - 运行 `xcodebuild -project ../token_hud.xcodeproj -scheme token_hud -destination 'platform=macOS' build`。
   - 真机验证：
     - collapsed 时刘海下方左右圆角不再出现蓝色缝。
     - 左右小格触发位置有明确视觉提示。
     - 小格附近容易 hover 展开，但扫过远离刘海的菜单栏位置不会误触。
     - 展开/收回过程圆角过渡不闪烁、不露缝。

### 风险

- 真实刘海圆角尺寸不同设备可能不同；第一版用 12pt/10pt 经验值，后续可根据 safe area 或截图微调。
- shoulder cap 如果画得太多，会像重新变成长条；需要控制宽度和 opacity。
- 视觉标识如果太亮，会影响“融入刘海”的感觉；第一版用低透明白色短 handle。

---

## 历史记录：重做 collapsed 刘海左右小格与下拉展开（已实现，待真机验证）

### 问题

当前 hosted collapsed 状态仍然显得太长、不连贯。用户在 2026-06-04 的截图中指出：刘海两侧的黑色状态区横向过长，视觉上像一整条黑条，而不是刘海左右各一个小状态块。

期望效果：

- 收起时只在刘海左右两边各保留一小格。
- 左右小格仍能表达极简用量状态，例如左侧短进度、右侧百分比。
- 鼠标摸到任意一个小格时，完整小窗从刘海区域向下延展。
- 动画看起来像从刘海两侧状态块自然拉开，而不是长条突然变大。

### 当前判断

当前 `NotchHostedSurfaceView` 已经把 collapsed/expanded 合并为一个 surface，并通过 `expansionProgress` 做连续动画，这是正确基础。

问题主要在 geometry 与 hover 命中区：

1. `hostedSurfaceLayout` 的 ears 在 collapsed 时使用 expanded surface 剩余空间计算，导致左右耳朵过长。
2. `notchRegion` 对刘海屏返回整屏顶部宽度，鼠标扫过顶部菜单栏任何位置都可能触发展开，不符合“摸左右小格才展开”。
3. collapsed body 起始宽度仍偏大，展开时缺少“从两个小格往下长出”的视觉集中感。

### 本轮目标

- collapsed 状态只显示左右两个短状态格：
  - 建议每侧宽度先用 44pt。
  - 中间 notch gap 保持透明。
  - 不画横跨刘海两侧的大面积黑条。
- hover 命中区从“整屏顶部”收缩到左右状态格附近：
  - 命中区覆盖左右小格。
  - 保留少量 padding，避免太难触发。
- expanded 状态保持当前完整小窗能力。
- collapsed -> expanded 动画改为：
  - 左右小格横向扩展。
  - 下方 body 从刘海下方长出。
  - 内容在 body 高度足够后淡入。
- expanded -> collapsed 动画反向收回，只留下左右小格。

### 本轮实现结果（2026-06-04）

- `NotchGeometryCalculator` 新增 `collapsedStatusPillWidth = 44` 和 `collapsedHoverPadding = 10`。
- `hostedSurfaceLayout` 改为：
  - collapsed 时 left/right ear 各 44pt，并贴在 notch gap 左右两侧。
  - expanded 时 ears 和 body 从 notch center 向外插值扩展到完整面板宽度。
  - body collapsed 起始宽度改为 `notchGapWidth + 2 * collapsedStatusPillWidth`，不再一开始就铺成宽条。
- 新增 `notchHoverRegions(screenFrame:geometry:)`：
  - 刘海屏返回左右两个 compact hover region。
  - 不再让整条顶部菜单栏都触发展开。
- `NotchHostPanelManager.isMouseInNotchRegion()` 改为：
  - collapsed 时只看左右小格 hover region。
  - expanded 时额外把 body 作为停留区域，避免鼠标在面板内时立刻收回。
- `NotchHostedSurfaceView` 微调 44pt 小格内部视觉：
  - 左侧进度条缩短并减少 padding。
  - 右侧百分比改小字号和更强缩放，适配 44pt 宽度。
  - 小格底部外侧圆角收紧到 7pt。
- `NotchGeometryCalculatorTests` 新增 compact pill 和 hover region 覆盖。

验证结果：

- `swift test --filter NotchGeometryCalculator` 通过，47 个测试通过。
- `swift test` 通过，110 个测试通过。
- `xcodebuild -project ../token_hud.xcodeproj -scheme token_hud -destination 'platform=macOS' build` 通过。
- 本轮未新增 Swift 文件，不需要重新运行 `xcodegen generate`。

### 实施步骤

1. **补充 geometry 测试**
   - 在 `NotchGeometryCalculatorTests` 中新增 hosted surface collapsed 小格测试：
     - `expansionProgress == 0` 时 left/right ear 宽度等于短小格宽度。
     - collapsed 两个小格的总宽度明显小于 expanded body 宽度。
     - `expansionProgress == 1` 时 body 宽度仍能达到 expanded body 宽度。
   - 新增 hover region 测试：
     - hover region 不再覆盖整屏宽度。
     - hover region 覆盖 collapsed 左右小格所在 x 范围。

2. **调整 `NotchGeometryCalculator` 常量与 layout**
   - 新增 `collapsedStatusPillWidth`，初始值 44pt。
   - 保留 `collapsedStatusEarWidth` 作为旧 fallback 或删除未用路径，避免概念混乱。
   - `hostedSurfaceLayout`：
     - collapsed ear width 从 44pt 起步。
     - expanded ear/body width 继续插值到完整面板宽度。
     - body collapsed width 从 `notchGapWidth + 2 * pillWidth` 起步，避免刚展开就太宽。

3. **收缩 hover 命中区**
   - 新增或调整纯函数，让 hover region 基于 collapsed 小格布局计算。
   - `isMouseInNotchRegion()` 使用新的 compact hover region。
   - 命中区增加 8-12pt padding，确保可用但不误触整条菜单栏。

4. **调整 `NotchHostedSurfaceView` 视觉**
   - collapsed 小格圆角更像独立小 pill：
     - 左格靠刘海一侧可保持直角或微圆。
     - 外侧用 6-8pt 圆角。
   - 左侧进度条缩短到适合 44pt 的长度。
   - 右侧百分比使用可缩放小字号，避免 100% 溢出。

5. **验证**
   - 运行 `swift test --filter NotchGeometryCalculator`。
   - 运行 `swift test`。
   - 如果新增/删除 Swift 文件，运行 `xcodegen generate`。
   - 运行 `xcodebuild -project ../token_hud.xcodeproj -scheme token_hud -destination 'platform=macOS' build`。
   - 真机验证：
     - collapsed 只露左右小格，不再是一长条。
     - 鼠标摸左右小格能顺滑下拉展开。
     - 鼠标扫过其它菜单栏位置不会误展开。
     - 收回后只剩左右小格，视觉连贯。

### 风险

- 44pt 小格可能对右侧百分比文本偏窄，尤其 `100%`；第一版使用 `minimumScaleFactor`，必要时把右侧设为 52pt。
- hover 区域缩小后可能变得难触发；需要真机调 padding。
- 如果系统菜单栏图标靠近刘海，右侧小格仍可能视觉冲突；后续可根据 `auxiliaryTopLeftArea/rightArea` 做更精细避让。
- 当前 hosted window 仍保持 expanded frame 以获得平滑动画和透明穿透；本轮只改变绘制和命中区，不回到 window resize 动画。

### 最近沉淀

- `docs/work-log/2026-06-01-notch-fusion-smooth.md`（hosted 面板重影、漂浮拖拽、动画流畅性修复）
- `docs/work-log/2026-05-31-notch-drag-settle.md`
- `docs/work-log/2026-05-31-notch-collapsed-status.md`
