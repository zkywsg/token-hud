# 项目总结

## 产品

`token-hud` 是一个 macOS SwiftUI app，用于在尽量不占屏幕空间的前提下持续显示 AI 额度和用量信息。README 将它定位为 Claude、OpenAI 及相关 AI 工具的 MacBook 刘海 HUD。

## 当前架构

项目分为一个小型可测试核心包和一个 macOS app target：

- `Sources/token_hudCore` 包含共享状态模型、额度解析器和 widget 数值格式化逻辑。
- `token_hud` 包含 SwiftUI app、设置 UI、overlay/浮动面板、状态监听、平台数据拉取和 widget 渲染。
- `Tests/token_hudCoreTests` 覆盖状态解析、JWT 处理和 widget 数值格式化。

主要数据契约是一个本地 JSON 文件：

```text
token-state or local fetchers -> ~/.token-hud/state.json -> token-hud UI
```

`StateWatcher` 会读取并监听配置的 state file 路径。如果真实数据不可用，app 会回退到 `StateFile.preview`，确保 widgets 仍然可以渲染。

## 已实现能力

- macOS 14+ SwiftUI app target，并在 `project.yml` 中配置 Swift 6 和严格并发检查。
- 浮动面板 overlay 支持位置持久化、透明度、缩放、紧凑/分组显示模式和可选快捷键。
- 可配置 widget 列表，支持默认 widgets、预设、拖拽排序，以及从旧版左右分栏 widget 存储迁移。
- Widget 样式包括 ring、bar、text、aggregate、multi、countdown、status 和 model breakdown。
- 支持的 widget 指标包括剩余时间、重置倒计时、剩余 token、余额、会话 token、使用率、输入/输出 token、请求数、花费、限流状态、credits、订阅状态和套餐名称。
- 平台设置覆盖 Claude、OpenAI、Codex、Gemini、DeepSeek、Anthropic API、MiniMax 和 MiMo。
- 通过 `SessionKeyExtractor` 和 Keychain 存储支持 Claude session key 提取和手动录入。
- Codex 用量从本地 `~/.codex/sessions` JSONL 日志和 `~/.codex/auth.json` 读取；不需要 Codex 网络请求。
- API 平台拉取包含 DeepSeek、MiniMax 和 MiMo 路径，其中 MiMo 支持通过控制台 cookie 获取 Token Plan 用量。
- App 过滤可以把 HUD 可见性限制在选定的前台应用中。

## 当前数据模型

`StateFile` 包含以平台 id 为 key 的 service 条目。每个 `Service` 可以暴露：

- `label`
- `quotas`
- `currentSession`
- `error`

`Quota` 支持 time、token、money、request、input/output token、daily/monthly token、daily/monthly request 和 cost-spent 等类型。`SessionSnapshot` 支持会话聚合用量和可选的按模型拆分。

## 验证

核心包可以用以下命令测试：

```bash
swift test
```

现有测试覆盖剩余额度格式化、credits、Codex 限流标签、订阅标签、会话指标、模型拆分格式化，以及已支持 service payload 的解析行为。
