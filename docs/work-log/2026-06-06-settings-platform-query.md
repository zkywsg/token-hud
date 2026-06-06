# Settings Platform Query

## 背景

用户需要重新整理 Settings 页面，并解决凭据/API 配置过期后无法重置、认证状态不清晰、平台查询能力容易误导的问题。本轮同时要求沉淀模型用量查询的成熟路径，避免后续把普通 API key 误当成所有平台的账单/用量凭据。

## 关键改动

- Settings 外层从 `TabView` 改为侧边栏导航，右侧按“小组件 / 平台 / 通用”展示详情。
- 平台页改为统一 dashboard/detail：
  - 左侧列表显示平台、认证状态和数据状态。
  - 右侧展示认证、查询能力、当前数据和重置操作。
- Core 增加 provider 能力/状态模型，放在 `Sources/token_hudCore/StateModel.swift` 中，避免 Xcode 工程漏掉新增 core 文件。
- `StateFile.removingService` 负责纯数据层删除单个平台 service。
- `StateWatcher.swift` 里增加 `StateServiceResetter`，负责按当前 `stateFilePath` 清空单个平台数据。
- `KeychainHelper` 增加删除 Claude session key、legacy OpenAI key、平台 API key、MiMo Console Cookie 的入口。
- 小组件自定义 sheet 改为搜索 + 平台筛选 + 指标列表。
- `APIPlatformFetcher` 对 OpenAI、Anthropic、Gemini 返回明确 `usageUnsupported` service，不再返回 nil。
- 新增 `docs/model-usage-query-practices.md`，记录不同平台的用量查询路径与权限边界。

## 决策

- 本轮不强行实现 OpenAI、Anthropic、Gemini 的真实账单/组织用量查询。
- 普通 API key 只代表模型调用或 key 验证能力，不代表有账单/组织用量权限。
- Codex 认证由 Codex 自身管理，Settings 不删除 `~/.codex/auth.json`，只显示状态和提示 `codex login`。
- MiMo 的 API key 与 Console Cookie 分开建模和重置，因为二者能力不同。
- 新的小型 helper 合入已有 Xcode 已感知文件，避免当前 `xcodegen generate` 不稳定时新增文件不进 app target。

## 验证

- `swift test`：131 个测试通过。
- `xcodebuild -project token_hud.xcodeproj -scheme token_hud -destination 'platform=macOS' build`：通过。

## 后续注意

- 后续如果要做真实 OpenAI Usage/Costs、Anthropic Cost Reports、Gemini Billing Export，应新增单独的管理员/账单凭据配置，不复用普通 API key 文案。
- 长期上 provider fetcher 仍应迁往 `token_state`，TokenHUD 保持触发和展示层职责。
- 如果恢复使用 `xcodegen generate`，需要确认新增文件能稳定进入 `token_hud.xcodeproj`。
