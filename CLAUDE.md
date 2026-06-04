# Agent 协作约定

这个仓库把项目文件作为计划和 agent 交接信息的事实来源。不要只依赖对话历史来恢复实现上下文。

## 工作流程与计划持久化

- 我们全程中文对话，每次回复我，都先说一句“我读了你的要求”
- 开始任何功能修改、功能新增、功能删除或 Bug 修复前，先阅读 `PLAN.md` 和 `docs/` 下相关文件。
- 开始实现前，先在 `PLAN.md` 写清楚本次工作的目标、范围、执行步骤、验证方式和风险点。推荐章节结构：`### 问题` → `### 本轮目标` → `### 实施步骤` → `### 验证` → `### 风险`，与现有 PLAN.md 中已有工作项保持一致。
- `PLAN.md` 需要先交给用户确认；用户确认没有问题后，才按计划修改代码或项目文件。
- 执行过程中如果计划发生实质变化，先更新 `PLAN.md` 并说明变化；必要时再次等待用户确认。
- **PLAN 流程豁免**：以下琐碎改动可以跳过 PLAN，直接改并在回复里一句话说明改动范围——
  - typo、注释、文案、字符串微调
  - 纯测试补充或测试重命名
  - 单文件改动 ≤ 30 行，且无新增 public API、无行为变化
  - 依赖/工具链版本号升级，且无 API 兼容性变化
- 长期路线图、架构方向和产品决策放在 `docs/` 下。
- 短期工作完成后，从 `PLAN.md` 移除已完成任务，或把可长期保留的决策沉淀到 `docs/`。
- **work-log 触发条件**：只有以下情况才在 `docs/work-log/` 下沉淀文档——
  - 涉及架构决策、私有 API 取舍、跨模块约定
  - 调试出非平凡根因（值得未来会话避坑）
  - 跨多个文件的非平凡重构
  - 后续会话恢复时必须知道、且无法从 `git log` 还原的上下文
  - 纯执行类的常规改动（一次性 bug 修复、参数调整、视觉微调）让 `git log` 承担，不再单独写 work-log。
- 工作沉淀文件名使用 `YYYY-MM-DD-工作内容.md` 格式，例如 `2026-05-03-widget-scale-fix.md`；工作内容用简短英文或拼音描述，避免空格和特殊符号。
- 对话里的计划保持简洁；未来会话需要恢复的信息必须写进仓库文件。

## 项目快照

- `token-hud` 是一个 macOS 14+ SwiftUI app，用轻量 HUD 展示 AI 用量和额度信息。
- 产品形态以刘海融合 HUD（hosted）为主，支持拖拽脱离成可移动浮动面板（detached），并能再次吸附回刘海。
- 数据通过 `~/.token-hud/state.json` 流转；能用本地文件和本地凭据时，优先避免直接抓取产品页面。
- 核心数据模型和格式化逻辑位于 `Sources/token_hudCore`。
- app UI、设置、overlay、状态监听、数据拉取和 widgets 位于 `token_hud`。
- 测试位于 `Tests/token_hudCoreTests`。

## 关键文档索引

新会话开始前按需读取，不要盲目通读整个 `docs/`：

- `PLAN.md`：当前进行中的实现计划，开工前必读。
- `docs/roadmap.md`：长期路线图与未来方向。
- `docs/project-summary.md`：项目整体概况，适合新会话上下文恢复。
- `docs/token-state-split.md`：`state.json` 数据模型与拆分约定，改解析器/状态模型前必读。
- `docs/notch-open-source-research.md`：刘海窗口实现参考与开源调研。
- `docs/work-log/`：按日期命名的工作沉淀，找历史决策时按主题搜索文件名（例如 `notch-`、`menubar-`、`widget-`）。

## 开发命令

- `swift test`：跑核心测试套件（Swift Testing）；定位单条用例时加 `--filter <TestName>`。
- `xcodegen generate`：修改 `project.yml` 或调整源码目录后，必须重新生成 `token_hud.xcodeproj`，否则 Xcode 端不会感知新文件。
- `xcodebuild -project token_hud.xcodeproj -scheme token_hud -destination 'platform=macOS' build`：在仓库根目录验证 app 能整体编译。
- `open token_hud.xcodeproj`：需要手动运行、调试或抓真机行为时打开 Xcode。

## 实现注意事项

- 保留已有用户改动。编辑前先 `git status --short` 检查未提交内容；不要用 stash/reset/checkout 覆盖用户未提交的工作。
- 优先做范围集中的改动，并贴合当前 SwiftUI 和 Observation 写法。
- 可脱离 app target 测试的共享模型和格式化行为，应放在 `Sources/token_hudCore`。
- 修改解析器、状态模型或 widget 数值格式化逻辑时，添加或更新 Swift Testing 覆盖。
- 密钥只应存放在 Keychain helper 或用户提供的本地配置路径中；不要提交真实 token、cookie 或 session key。
