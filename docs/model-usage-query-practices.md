# Model Usage Query Practices

本文记录 token-hud 查询模型用量、余额、套餐额度和本地 coding agent 状态时的成熟路径。后续开发前优先读这个文档，避免把“普通 API key 可调用模型”和“可读取账单/套餐用量”混为一谈。

## 总原则

- **本地优先**：Codex、Claude Code 这类本机 coding agent 优先读取本地认证和 session JSONL，不抓网页。
- **官方接口优先**：DeepSeek 余额、MiniMax Token Plan remains 这类有官方接口的平台可以直接查询。
- **普通 API key 只做调用验证**：OpenAI、Anthropic、MiMO、MiniMax 的普通调用 key 不等同于账单或套餐查询凭据。
- **套餐 key 和按量 key 分开建模**：MiMO 明确区分 `tp-` Token Plan key 和 `sk-` pay-as-you-go key；MiniMax 也区分 Token Plan key 和普通开放平台 key。
- **控制台 cookie 只作为补充路径**：当官方没有开放用量 API、但控制台有清晰 JSON 接口时，可以用 WebView 登录后读取 cookie；不建议让用户长期手动粘贴 cookie。
- **账单权限单独建模**：组织级、管理员级、Cloud Billing / BigQuery export 这类能力必须作为单独凭据和单独状态处理。
- **避免默认抓取网页 dashboard**：网页结构和风控变化快，且容易触发登录态、验证码、权限和隐私问题。优先使用 JSON API、本地日志或 provider 官方导出。

## 平台数据源矩阵

| 平台 | 能获取的数据状态 | 成熟获取路径 | 凭据/权限 | token-hud 建议 |
| --- | --- | --- | --- | --- |
| OpenAI API | API usage、cost buckets、请求级 token usage | 官方 Usage / Costs Admin API；或通过代理/SDK记录请求 usage | 组织/项目权限；普通调用 key 不一定足够 | 普通 OpenAI key 只标记“可验证调用”；真实用量新增 Admin key/组织级配置 |
| Codex | 本地 session token、rate limit 事件、账号/plan、可选 dashboard extras | `~/.codex/auth.json`、`~/.codex/sessions` JSONL；CodexBar 也扫描本地 session 和 archived session；OpenAI Admin Usage/Costs 只能做 extras | Codex CLI 本地登录态；可选 OpenAI Admin/API key | 保持本地优先，不接管 auth；Admin/API key 单独存储、单独重置，不影响 `codex login` |
| Claude / Claude Code | session token、costUSD、模型、5h/weekly block、统计缓存；API usage/cost report | `~/.claude/projects` JSONL、`~/.claude/stats-cache.json`；API Console reports/Admin API | Claude Code 本地文件；Console Developer/Billing/Admin 角色 | Claude Code 用本地 JSONL 优先；Claude Web session key 只作为 web quota 补充，避免频繁读 Keychain |
| DeepSeek | 账户余额、币种、赠金、充值余额、是否可用 | 官方 `GET /user/balance` | DeepSeek API key Bearer token | 当前路径正确，可继续作为余额查询主路径 |
| MiniMax | Token Plan remains、套餐/窗口/每日 quota；普通 key 可验证模型调用 | 官方 `GET https://www.minimax.io/v1/token_plan/remains`；失败时 `/v1/models` 验证 | Token Plan API key；普通 key只能验证 | 当前路径正确，UI 必须区分 “Token Plan key” 与 “普通 key” |
| MiMO | Token Plan credits、plan、到期/进度；普通 key 可验证模型调用 | 优先 Token Plan `tp-` key；其次 WebView 登录控制台后读取 cookie 调控制台 JSON；普通 `sk-` key 调 `/v1/models` 验证 | `tp-` Token Plan key、控制台 cookie 或 `sk-` API key | 不再要求用户手贴 cookie；恢复/迁移已有 WKWebView 自动连接入口，并把 `tp-` key 作为首选 |

## MiMO 获取方法优化

### 调研结论

MiMO 官方文档明确区分两类 key：

- `tp-xxxxx`：Token Plan subscription services，只用于套餐服务。
- `sk-xxxxx`：pay-as-you-go API calls，只用于按量 API 计费。

因此，当前“让用户粘贴 cookie 才能看 Token Plan 用量”的体验不应该作为唯一入口。更合理的顺序是：

1. **Token Plan key 优先**
   - Settings 中 MiMO 凭据类型应从单一 API key 拆成：
     - `Token Plan Key (tp-)`：用于套餐查询和调用套餐服务。
     - `API Key (sk-)`：用于按量 API 调用验证。
     - `Console Login`：备用自动登录连接。
   - 保存时根据前缀提示用途：`tp-` 才能展示套餐状态，`sk-` 只能验证调用能力。

2. **WebView 自动连接作为备用**
   - 使用 `WKWebView` 打开 `https://platform.xiaomimimo.com/console/plan-manage`。
   - 使用 `WKWebsiteDataStore.default()` 保留用户登录态。
   - 登录后从 `httpCookieStore.getAllCookies` 读取 `platform.xiaomimimo.com` 可用 cookie。
   - 用原生 `URLSession` 带 `Cookie` 访问：
     - `https://platform.xiaomimimo.com/api/v1/tokenPlan/usage`
     - `https://platform.xiaomimimo.com/api/v1/tokenPlan/detail`
   - 只有返回业务成功码后才把 cookie header 存进 Keychain。
   - cookie 失效时显示“控制台登录已过期”，让用户点按钮重新连接，不要要求手动粘贴。

3. **普通 API key 只做验证**
   - `https://api.xiaomimimo.com/v1/models` 可以验证 key/base URL 是否可用。
   - 这个结果不能被 UI 表达成“已查到套餐用量”。

### 当前代码里的可复用资产

当前旧 UI 已经有一套比较接近正确路线的实现：

- `Settings/PlatformRowView.swift` 中的 `MiMoConsoleConnectorSheet`
- `MiMoConsoleConnectorView`
- `MiMoCookieHeaderBuilder`
- `State/CodexFetcher.swift` 中 MiMO 的 `/tokenPlan/usage` 和 `/tokenPlan/detail` 拉取逻辑

后续实现不应该重新发明一套。更好的改法是：

1. 把 `MiMoConsoleConnectorSheet` / `MiMoConsoleConnectorView` 从 `PlatformRowView.swift` 移到独立文件，例如 `Settings/MiMoConsoleConnectorView.swift`。
2. 在新的 `PlatformListView` MiMO 详情页露出 `连接 MiMO 控制台` 按钮。
3. 保存 cookie 后刷新 credential snapshot，并立即触发 `fetchSingle(platform: "mimo")`。
4. 增加 `tp-` Token Plan key 的单独保存项，避免和 `sk-` API key 混用。
5. UI 状态改成：
   - `Token Plan Key 已配置`
   - `按量 API Key 已配置，仅验证调用`
   - `Console Cookie 已配置`
   - `控制台登录已过期`
   - `未配置套餐查询凭据`

## 平台细节

### OpenAI

成熟做法分三层：

- **请求级 usage**：SDK 响应中的 `usage` 字段，适合 token-hud 后续做“从本地代理/日志累计成本”。
- **组织级 Usage / Costs API**：官方 Usage API 可按 bucket 查询 API 活动，Costs API 可查成本 bucket；但这属于组织/项目级能力，不等同于普通模型调用 key。
- **开源代理统计**：LiteLLM、Helicone、LLMeter 等常见做法是在请求链路中记录模型、token、cost，再按价格表聚合。

token-hud 中不要把普通 OpenAI API key 显示成“可查余额”。后续如果要做真实账单，需要新增 `OpenAI Admin Key` 或 `Organization Usage` 配置。

### Codex

成熟路径是“Codex 登录态优先，本地日志兜底”：

- 读取 `~/.codex/auth.json` 判断账号、plan、token 是否过期。
- 当前可用的套餐/限额主路径是 `GET https://chatgpt.com/backend-api/wham/usage`：
  - Header: `Authorization: Bearer <tokens.access_token>`
  - Header: `ChatGPT-Account-Id: <tokens.account_id>`（存在时）
  - Header: `User-Agent: codex-cli`
  - 返回 `plan_type`、`rate_limit.primary_window`、`rate_limit.secondary_window`、`credits`。
- `GET https://chatgpt.com/backend-api/codex/usage` 在部分账号/环境会返回 403，不能作为唯一主路径。
- 扫描 `~/.codex/sessions` 和 `archived_sessions` JSONL，汇总 session token/cost/rate-limit 事件，作为后端 usage 不可用时的兜底。
- 参考 CodexBar / codex-cli-usage / Codex Usage Monitor 的做法：复用 Codex CLI 本地 OAuth 登录态查询 usage；OpenAI Admin key 只做 dashboard/cost extras。

token-hud 当前方向是正确的：不把 Codex auth 存进 Keychain，只提供 `codex login` 入口、打开 `~/.codex` 和受控删除 `auth.json`。

Codex 的 API 认证必须和 Codex CLI 本地登录分开：

- **本地登录**：`~/.codex/auth.json` 只由 Codex CLI 管理。token-hud 读取 email、plan、access token 和过期状态，但不把它复制进 Keychain。
- **套餐/限额**：`wham/usage` 是当前更完整路径，可展示 plan、5h、7d 和 credits。没有 Admin/API key 时也应该能展示这些数据。
- **本地用量**：`~/.codex/sessions` 是兜底数据源，可提供本地 token/session 汇总。
- **OpenAI Admin/API extras**：单独保存到 Keychain，例如 `codexOpenAIAdminKey`。它可以尝试查询 OpenAI organization Usage/Costs，但普通 key 可能 401/403；失败不能覆盖本地 Codex 数据。
- **重置边界**：`移除本地认证` 只删除 `~/.codex/auth.json`；`重置 Admin Key` 只删除 Keychain extras key；`清空数据` 只清 `state.json` 中的 codex service。

### Claude / Claude Code

成熟路径有两类：

- **Claude Code 本地日志**：官方文档说明 Claude Code session 会写入 `~/.claude/projects` JSONL；`.claude` 目录还包含 `stats-cache.json`，记录 `/usage` 使用的聚合 token/cost。
- **Console 报表/Admin API**：Anthropic Console usage/cost reports 需要 Developer、Billing 或 Admin 角色，普通 `sk-ant-` key 不应默认视为可查账单。

开源项目如 `ccusage`、`claude-usage` 的共同路径是扫描本地 JSONL，使用已有 `costUSD` 或基于模型价格表计算成本。token-hud 后续应优先接本地 JSONL 和 `stats-cache.json`，Claude Web session key 仅作为 web quota 的补充凭据。

### DeepSeek

DeepSeek 有稳定官方余额接口：

- `GET https://api.deepseek.com/user/balance`
- Header: `Authorization: Bearer <TOKEN>`
- 可返回 `is_available`、`balance_infos`、币种、总余额、赠金余额、充值余额。

token-hud 当前把 DeepSeek 作为“可查余额”是正确的。错误状态应区分 401 invalid key、余额不可用、网络错误和解析失败。

### MiniMax

MiniMax 官方 Token Plan FAQ 给出 remains 接口：

- `GET https://www.minimax.io/v1/token_plan/remains`
- Header: `Authorization: Bearer <API Key>`
- Token Plan 的 M2.7 是 5 小时 rolling window，其他多模态能力是 daily quota。

MiniMax 官方 CLI 也提供 `mmx quota`，说明“CLI 登录/Token Plan key + quota 查询”是官方支持的产品路径。token-hud 可以继续直接查 remains，失败时用 `/v1/models` 验证普通 key，但 UI 要明确“普通 key 无套餐数据”。

如果 MiniMax 返回 `no active token plan subscription`，这表示当前 key 没有关联 active Token Plan 套餐，应归类为 `usageUnsupported`，不要显示成“查询异常”。普通 key 通过 `/v1/models` 验证成功但没有 remains 数据时，也应归类为 `usageUnsupported`。

### MiMO

MiMO 官方 FAQ 给出的重要约束：

- Token Plan 有 Lite、Standard、Pro、Max 等套餐。
- 套餐 credits 被不同模型按不同倍率消耗。
- 可在 Subscription Management 查看当前 plan 的 quota 和 usage。
- Token Plan key `tp-` 和 pay-as-you-go key `sk-` 彼此独立，不能混用。

后续实现优先级：

1. 先支持 `tp-` Token Plan key。
2. 再恢复 Settings 里的 WebView 自动连接控制台。
3. 保留手动 cookie 输入作为高级/调试 fallback，而不是默认入口。

## UI 状态约定

Settings 平台页应至少区分以下状态：

- `未配置`：没有可用凭据。
- `已配置，未查询`：凭据存在，但 `state.json` 里没有该平台数据。
- `已配置，暂无用量数据`：查询/验证成功，但平台没有返回可展示 quota/session。
- `普通 API key 暂不支持用量查询`：普通 key 不能读取账单或组织用量。
- `Token Plan key 可查询套餐`：套餐 key 存在，可以尝试读取 remains/usage。
- `控制台登录已过期`：cookie 存在但控制台 JSON 返回 401/业务未登录。
- `权限不足`：凭据有效但没有读取账单/用量的权限。
- `网络错误`：请求失败，通常可重试。
- `有数据`：`state.json` 里有 quota 或 session 可展示。

## 参考来源

- MiMO FAQ: https://platform.xiaomimimo.com/docs/en-US/faq
- MiniMax Token Plan FAQ: https://platform.minimax.io/docs/token-plan/faq
- MiniMax CLI / quota: https://platform.minimax.io/docs/token-plan/minimax-cli
- DeepSeek balance API: https://api-docs.deepseek.com/zh-cn/api/get-user-balance/
- OpenAI Usage / Costs API: https://platform.openai.com/docs/api-reference/usage
- OpenAI Usage Dashboard: https://help.openai.com/en/articles/10478918
- Anthropic Console cost and usage reporting: https://support.anthropic.com/en/articles/9534590-cost-and-usage-reporting-in-console
- Claude Code local session docs: https://code.claude.com/docs/en/how-claude-code-works
- Claude `.claude` directory docs: https://code.claude.com/docs/en/claude-directory
- CodexBar: https://github.com/steipete/CodexBar
- CodexBar providers: https://github.com/steipete/CodexBar/blob/main/docs/providers.md
- ccusage cost modes: https://ccusage.com/guide/cost-modes
- claude-usage: https://github.com/phuryn/claude-usage
- LiteLLM: https://github.com/BerriAI/litellm
