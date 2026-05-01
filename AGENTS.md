# Agent 协作约定

这个仓库把项目文件作为计划和 agent 交接信息的事实来源。不要只依赖对话历史来恢复实现上下文。

## 计划持久化

- 短期执行计划放在 `PLAN.md`。
- 长期路线图、架构方向和产品决策放在 `docs/` 下。
- 开始实现前，先阅读 `PLAN.md` 和 `docs/` 下相关文件。
- 如果计划发生实质变化，在同一次改动里更新对应文件。
- 短期工作完成后，从 `PLAN.md` 移除已完成任务，或把可长期保留的决策沉淀到 `docs/`。
- 对话里的计划保持简洁；未来会话需要恢复的信息必须写进仓库文件。

## 项目快照

- `token-hud` 是一个 macOS 14+ SwiftUI app，用轻量 HUD 展示 AI 用量和额度信息。
- 产品面向带刘海的 MacBook，但当前实现也包含可移动浮动面板。
- 数据通过 `~/.token-hud/state.json` 流转；能用本地文件和本地凭据时，优先避免直接抓取产品页面。
- 核心数据模型和格式化逻辑位于 `Sources/token_hudCore`。
- app UI、设置、overlay、状态监听、数据拉取和 widgets 位于 `token_hud`。
- 测试位于 `Tests/token_hudCoreTests`。

## 开发命令

- 使用 `swift test` 运行核心测试。
- 需要手动运行 macOS app 时，使用 `open token_hud.xcodeproj` 打开项目。
- Xcode 项目通过 `project.yml` 配置；如果源码布局变化，需要同步更新该文件。

## 实现注意事项

- 保留已有用户改动。编辑前先检查 `git status --short`。
- 优先做范围集中的改动，并贴合当前 SwiftUI 和 Observation 写法。
- 可脱离 app target 测试的共享模型和格式化行为，应放在 `Sources/token_hudCore`。
- 修改解析器、状态模型或 widget 数值格式化逻辑时，添加或更新 Swift Testing 覆盖。
- 密钥只应存放在 Keychain helper 或用户提供的本地配置路径中；不要提交真实 token、cookie 或 session key。
