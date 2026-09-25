# 产品结构与竞品分析看板

## 交付物

- 独立站点源码：`product-dashboard/`
- 私有站点：<https://token-hud-product-dashboard.lauzanhing.chatgpt.site>
- 调研日期：2026-09-09

## 核心判断

1. token-hud 当前分层总体合理：`Sources/token_hudCore` 承载可测试纯逻辑，App target 承载 SwiftUI、AppKit、状态监听、凭据和 provider 拉取；本地 `state.json` 是清晰的数据契约。
2. 结构热点集中在 `PlatformListView.swift`、`CodexFetcher.swift` 和 `NotchHostPanelManager.swift`。继续新增 provider 或刘海交互前，应分别建立 `ProviderAdapter` 边界，并拆分窗口定位、交互状态机与系统事件监听。
3. 竞争市场的基础能力已经从“菜单栏看额度”推进到多 provider、历史洞察、通知、多账户和 agent 状态联动。token-hud 不适合追逐 provider 数量，应强化“刘海原生 + 可脱离 HUD + 本地优先”的工作流入口。
4. 推荐演进顺序：先补齐可信状态、分发更新和提醒；再做节奏预测、多账户、provider 路由与项目成本；最后再扩展为 Notch agent control plane。
5. UI 优先级：先统一“已用/剩余”语义和数据状态，再收敛卡片信息层级、统一平台连接流程，最后精修 hosted/detached 空间动效。

## 竞品来源

- CodexBar：<https://github.com/steipete/CodexBar>
- Usage for Claude：<https://apps.apple.com/us/app/usage-for-claude/id6755173244?platform=mac>
- AgentBar：<https://github.com/scari/AgentBar>
- Claude Statistics：<https://github.com/sj719045032/claude-statistics>
- UsageBar：<https://github.com/methol-dev/usage-bar>
- AI Usage Counter：<https://github.com/lazymodthai/ai-usage-counter>

竞品能力会持续变化；看板中的热度和评分仅用于产品定位与优先级判断，不作为质量排名。

## 2026-09-23：工作流 HUD 专题

### 产品判断

- 多产品并行时的核心问题不是缺少任务列表，而是切换之后丢失工作上下文。工作流 HUD 应保存“产品 → 今日成果 → 当前动作 → 下一步 → 状态 → 完成证据”。
- 收起态只显示一个全局当前线程；展开态最多显示三个活跃产品；脱离态提供 Now / Next / Done，用于重排和复盘。
- 活跃产品采用 WIP 3/3 上限。第一版使用检查点、状态和完成证据，不使用没有可信分母的百分比进度。
- MVP 仅包含产品线程、每日成果、唯一当前动作、三种 HUD 状态和当日完成时间线；复杂看板、团队协作、重型日历、云端账号与自动安排整天均暂缓。

### 参考模式

- 刘海 Today：[Notchwell](https://notchwell.app/) 与 [Notchable](https://notchable.com/) 说明刘海适合承载当前重点与快速捕获，完整规划应留在展开或桌面层。
- 单任务浮窗：[FocalDot](https://www.focaldot.app/) 与 [Focana](https://focana.app/) 说明常驻界面应只强调一个下一动作。
- 每日规划：[Structured](https://structured.app/)、[Sunsama](https://www.sunsama.com/features/daily-planning-and-shutdown) 与 [Akiflow](https://product.akiflow.com/articles/0741055-today-page) 说明容量和当天承诺比无限优先级更有效。
- Agent 状态：[Notchi](https://notch.website/) 与 [Isle](https://isle.withmii.com/) 说明运行、等待批准、完成等机器状态可以与人的工作线程共用状态语言。

### 交付与验证

- 在 `product-dashboard/` 新增「工作流 HUD」导航和完整专题，并提供收起、展开、脱离三个可切换原型。
- `npx oxlint app/page.tsx app/layout.tsx` 与 `npm run build` 通过；真实浏览器验证三个 Tabs 均可切换。
- 已覆盖发布到原私有站点：<https://token-hud-product-dashboard.lauzanhing.chatgpt.site/#workstreams>。
- 本次只修改独立看板仓库与项目文档，没有修改 Swift/Xcode 源码。
