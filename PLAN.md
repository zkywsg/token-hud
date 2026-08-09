# 短期计划

这个文件跟踪当前项目正在进行的实现工作。保持内容小而可执行；可长期保留的决策沉淀到 `docs/`。

## 当前重点：每日用量统计（E 版本，已确认范围，实施中）

### 背景

只有「重置倒计时 + 用量」两个数据的平台，单看用量没有参照。经 mockup 确认走 **E 版本**：每日柱状图 + 周期预测。
**上游不提供按天数据**（`state.json` 只有本周期累计值；唯一按天的接口是 OpenAI Admin 费用接口，与套餐用量无关），因此必须本地采样差分。

### 平台适用性（按真实 state.json 核对）

| 平台 | 数据 | 结论 |
|---|---|---|
| Codex | tokens 累计 + 7 天窗口 + `resets_at` | ✅ 第一批（柱状 + 预测 + 倒计时全成立） |
| MiMo | monthly_tokens 有 **total 上限** + `resets_at` | ✅ 第一批（有上限，预测最有价值） |
| Claude | tokens 累计，**无 total、无 resets** | ✅ 第二批（只做柱状，隐藏预测/倒计时） |
| DeepSeek | `used` 实为**余额**（`total_balance`），随消费**下降** | ⏸ 暂不做（需反向逻辑，且充值会造成上升） |
| MiniMax | `error=usageUnsupported` | ❌ 不做 |

### 本轮目标

1. **core 纯逻辑 + 测试**：累计采样 → 每日差分，处理周期重置（累计值下降 ⇒ 新周期，该区间消耗按新值计），输出最近 N 天（缺失日补 0）。
2. **本地存储**：`~/.token-hud/usage-history.json`，按 `服务:配额类型` 分组存 `(时间, 累计值)`；写入节流（≥5 分钟一条）、保留 30 天。
3. **采样挂载**：`StateWatcher` 每次解析出新 state 时记录一次。
4. **卡片渲染**：历史 ≥3 天显示柱状图（今日高亮、周期内未到的日子灰显）；不足 3 天回退到"预测版"并提示"正在积累"。Claude 无周期 ⇒ 隐藏预测与倒计时。

### 风险

- **无法回填**：只能从开启记录起算，头几天必然稀疏 → UI 必须诚实说明。
- **App 未运行**：累计差额会全部落到下次开机当天，该日偏高；文档记录，不做伪造平摊。
- **周期重置**：必须靠"累计值下降"识别，否则出现负数。DeepSeek 因语义相反被排除在外，避免误判。

### 本轮实现结果（2026-08-03）

- **core** `Sources/token_hudCore/UsageHistory.swift`：`UsageSample` / `DailyUsage` / `UsageHistoryCalculator`
  - `dailyUsage(from:days:now:calendar:)`：相邻采样差分归入较晚一天；**差值为负 ⇒ 周期重置**，该区间消耗按新累计值计（不产生负数）；范围内无消耗的日子补 0。
  - `recordedDayCount`：判断是否够画图（阈值 `minimumDaysForChart = 3`）。
  - `pruned`：保留 30 天，且同一 5 分钟窗口内只留最新一条。
  - `projectedCycleTotal(used:cycleElapsedFraction:)`：周期进度 >2% 才给预测。
  - `UsageHistoryTests` 6 个用例（差分 / 重置 / 补零 / 天数统计 / 裁剪 / 预测边界）。
- **存储** `token_hud/State/UsageHistoryStore.swift`（`@Observable`）：写 `~/.token-hud/usage-history.json`，按 `服务:配额类型` 分组；`trackedServices = [codex, mimo, claude]`；优先选有 `total` 的配额（便于叠加余量），否则取 token 类计数器；写盘按 5 分钟节流。
- **采样挂载**：`StateWatcher.readNow()` 每次成功解析后调用 `usageHistory?.record(from:)`；`AppDelegate` 创建并注入到浮窗与设置页环境。
- **卡片渲染**：`DailyUsageChart`（今日高亮 + 发光、周期内未到的日子灰显、按峰值归一）；历史 ≥3 天显示柱状图，否则回退 gauge/计数条。副标题显示「按此节奏 · 周期约 X」；数据不足时显示「正在积累每日数据 · 已记录 N 天」。Claude 无 time 配额 ⇒ 自动无预测（`projectedCycleTotal` 返回 nil）。
- **DeepSeek 排除**：其 `used` 实为 `total_balance`（余额，随消费下降、充值上升），差分会把每天误判为周期重置；代码注释已记录原因。

### 验证结果（2026-08-03）

- `swift test`：通过，175 个测试（+6）。
- `xcodegen generate` 后 `xcodebuild ... build`：通过。
- **端到端实测**：删除历史文件后重启，`~/.token-hud/usage-history.json` 正确生成三条序列——
  `codex:tokens`、`mimo:monthly_tokens`、`claude:tokens`，均含最新累计值；DeepSeek/MiniMax 未被记录（符合预期）。

### 追加修正：功能不可见（2026-08-03）

用户反馈"看不到任何变化，也找不到入口"。复查发现**是我写错了逻辑，导致全部不显示**：

1. **`paceText` 提前 return 挡掉了预测**：只有 1 条采样时 `dailyUsage == nil` → `recorded == 0` → `guard recorded > 0 else { return nil }`。
   而预测（C 版）本来就只依赖周期进度、**开箱即用**，却被历史数据的判断挡在门外。
   → 改为：预测独立判断，`projectedCycleTotal` 有值就显示。
2. **图表阈值过高**：`minimumDaysForChart = 3` 意味着安装后 3 天内完全看不到东西，也没有任何"正在工作"的迹象。
   → 降为 **1**：有 1 天真实消耗即出图，其余日子显示 0 柱，读起来正确且立刻有反馈。
3. **缺少可发现入口**：新增 `UsageHistoryStatusRows`，位于小组件页右栏「显示」面板——列出正在记录的平台、各自已记录天数与图表是否启用，并说明"上游只给累计值、历史无法回填"。
   新增 `UsageHistoryStore.daysSinceFirstSample(for:)`（按自然日跨度算，区别于只统计"有消耗的天数"的 `recordedDayCount`，否则空闲日会显示 0 天）。

**验证**：以注入的 3 天采样推演，`有消耗天数=2 ≥ 阈值1 → 图表显示 ✅`；随后**删除注入的测试数据**，重启确认恢复为三条真实序列各 1 条。`swift test` 175 通过；`xcodebuild` 通过。

### 待手动验证

- 出现真实消耗后柱状图是否当天即出现（阈值已降为 1 天）。
- 周期重置（Codex 8/8、MiMo 月初）当天是否正确记为新周期而非负值。
- App 关闭一段时间后重开，差额集中落在当天导致该日偏高——属已知取舍，观察是否可接受。

## 预览高度 + 刘海 header 跟随翻页（2026-08-02，已实现）

**1. 设置页实时预览显示不全**
`previewHeight` 仍按已退役的堆叠列表公式算（hero 62 + 每行 40，cap 300），但预览现在渲染的是聚焦卡；3 个组件时只有 166pt，卡片被裁。
改为与卡片自身高度对齐：`NotchGeometryCalculator.focusCardHeight (172) + 圆点行 + padding`，**与组件数量无关**（轮播一次只显示一张）。

**2. 刘海 header 不随翻页变化**
`expandedHeader` 取 `store.widgets.first`，写死第一条；左右滑动切卡时菜单栏那行不动。
- `NotchHostState` 新增 `focusedWidgetID: UUID?`。
- `OverlayFocusView` 在 `onAppear` / `onChange(of: currentID)` 时写入（`@Environment(NotchHostState.self) private var hostState: NotchHostState?` **可选读取**——设置页预览里没有该环境对象）。
- `headlineMetric` 改为按 `focusedWidgetID` 查找，回退 `first`。

**验证**：`swift test` 169 通过；`xcodebuild` 通过；重启后进程存活（确认设置页缺少 `NotchHostState` 时可选环境读取不崩）。

**待手动验证**：浮窗展开后左右滑动，刘海两侧的平台名与数值应随卡片同步变化。

## 接口现状核对（2026-08-02，已实现）

以真实 `~/.token-hud/state.json` 为准逐个平台核对代码期望。

### 已修

**1. Codex 取消 5 小时窗口**
真实数据只剩一个 time 配额：`total=604800`（7 天）。但 UI 三处写死 `quotaIndex == 1 ? "7 天" : "5 小时"`，而 `quotaFor` 对越界 index 回退 `first` → **两个 widget 显示同一份 7 天数据，其中一个被标成「5 小时」**。
- 新增 `WidgetValueComputer.rateLimitWindowDisplayName(_:)`，从配额真实时长推导窗口名（≥7d / ≥1d / ≥5h），**禁止再用 quotaIndex 猜**。
- `WidgetMetricComputer.metricTitle` 对 codex remainingTime 改用推导值（原先返回空串）。
- 移除所有 `quotaIndex: 1` 的 codex 来源：默认 widgets、设置页预设、core 推荐引擎。
- 新增迁移 `collapseCodexRateLimitWindows`：把已保存的多条 codex `remaining_time` 合并为一条并把 quotaIndex 归零。
- **实测**：迁移后存储由 `codex×2` 变为 `codex×1`。

**2. DeepSeek 货币显示错误**
配额 `unit=CNY, used=11.48`，但 `formattedRemaining` / `formattedUsed` 写死 `$` → 把 ¥11.48 显示成 **$11.48**。
新增 `formatMoney(_:unit:)` 按 `quota.unit` 选符号（CNY/RMB→¥、EUR→€、USD/空→$、其他→`数值 单位`）。

### 待用户决定（未改）

- **MiMo 重置时间过期**：`resets_at=2026-07-02T23:59:59Z`，而当前为 2026-08-02 —— 已过期一个月。可能是上游字段变更或解析取错字段，需要抓一次真实响应确认。
- **Claude 无 time 配额**：只有 tokens/input/output 且 `total` 全为 `nil`。用户列表里的 `claude/remaining_time` 因此恒为「—」（现在会显示「无数据」徽章）。建议从 claude 能力表移除 `remainingTime`。
- **Claude `tokensRemaining` 语义**：无 total 时 `formattedRemaining` 回退成显示**已用量**，但标签仍是「剩余量」，语义相反。
- **MiniMax `error=usageUnsupported`**：无配额无会话，4 个预设全是死项（现已收进「暂无数据」）。
- **`formattedCostSpent` 仍写死 `$`**：它接收 session 而非 quota，拿不到 unit；如需按币种显示要先让 session 带上货币字段。

## 当前重点：指标重新归类（配额型 vs 计数型）+ 裁剪（待确认）

### 问题

所有指标目前共用同一张"环 + 百分比 + 进度条"的媒体卡，但只有一部分指标真的有分母：

- **有真分母**（`quota.total` 来自 state.json）：`tokensRemaining` `balance` `usagePercent` `dailyTokens` `monthlyTokens` `dailyRequests` `monthlyRequests` `creditsRemaining` `creditsUsed` `rateLimitStatus` `remainingTime`。
- **无分母的纯计数**：`sessionTokens` `inputTokens` `outputTokens` `costSpent`。无配额时 `fraction` 返回 0 → 进度条画成空的，看着像"还没用"，实为"没数据"，**误导**。
- **合成分母（写死常量，百分比是编的）**：`sessionDuration` ÷ 28800（8h）、`tokensPerMinute` ÷ 200、信用额度 `resetCountdown` ÷ 2_592_000（30 天）。
- **状态/标签**：`subscriptionStatus`（二值）、`planName`（纯文本）、`inputOutputRatio`（比例非用量）。二值指标做成整张媒体卡（环停在 0/100%）不合理。

### 本轮目标

**1. 卡片形态在运行时决定，而非按指标写死**

同一个 `costSpent`，配了额度就该有进度条、没配就只能显示数字。新增 `MetricPresentation`：
- `.quota(fraction)` — 存在真实 `total` → 环 + 百分比 + 进度条/波形（现状）。
- `.counter` — 无 total → **去掉环与进度条**，大数字 + 单位 + 一行上下文，底部用静态强调色细线代替，不谎报比例。

**2. 裁剪（用户已确认"全部按建议来"）**

- 降级、不再单独成卡：`subscriptionStatus`（→ 卡片副标题徽章）、`planName`（→ 副标题，已重复）、`resetCountdown`（→ 卡片右上重置胶囊，已重复）。
- 删除：`sessionDuration`、`tokensPerMinute`、`inputOutputRatio`、`costPerRequest`。
- 可选指标 23 → 16。

**3. 兼容性（关键约束）**

`WidgetConfig` 解码 `WidgetMetric` 失败会让整个 widget 数组解码失败。因此**保留 enum case**（不物理删除），改为标记 `isSelectable == false` 并从所有 UI（可添加列表、预设、收起态来源）过滤；`WidgetStore` 载入时丢弃已退役指标的 widget。这样旧配置永不崩，用户侧等同于"删掉了"。

**4. 收起态条同步**

刘海收起条左槽是进度条；来源若是 `.counter` 指标，改为显示数值文本而不是空进度条。

### 实施步骤

1. `Sources/token_hudCore`：新增 `MetricPresentation` 枚举 + `WidgetMetric.isSelectable`（退役标记），补 Swift Testing（退役集合、`isSelectable` 覆盖）。
2. `WidgetMetricComputer` 新增 `presentation: MetricPresentation`：先判状态类，再判是否存在真实 total，否则 `.counter`；同时**删除三处写死分母**的 fraction 分支。
3. `OverlayFocusCard` 按 `presentation` 分支渲染：`.quota` 保持现状；`.counter` 隐藏 `ProgressRing` 与 `FocusGauge`，改大数字 + 上下文 + 静态细线。
4. `WidgetStore` 载入时过滤退役指标；设置页可添加列表 / 预设 / 收起态来源均按 `isSelectable` 过滤。
5. `NotchCollapsedStatusEngine`：来源为 counter 时输出文本而非 fraction。
6. 验证（见下）。

### 验证

- `swift test`：新增 `MetricPresentation` / 退役指标用例；更新受影响的既有用例。
- `xcodebuild ... build`。
- 手动：配了额度的平台显示进度条卡；未配额度的（如仅有消耗数据的 API）显示计数卡且无空进度条；旧配置含已退役指标时能正常加载并被静默丢弃。

### 风险

- 退役指标采用"保留 case + 过滤"而非物理删除，是为了解码兼容；需确保**所有** UI 入口都过滤，否则会出现"能选但没意义"的残留。
- `.counter` 卡去掉环和进度条后视觉重量下降，需确认与配额卡并排（翻页切换）时不显得残缺。
- 删除写死分母会改变既有指标的显示（如会话时长不再有百分比），属预期变化。

### 本轮实现结果（2026-08-02）

- **core 新增** `Sources/token_hudCore/MetricPresentation.swift`：`MetricPresentation`（`.quota(Double)` / `.counter` / `.status`，带 `fraction` 与 `showsGauge`）+ `RetiredMetrics`（7 个退役 rawValue + `isRetired`）。`MetricPresentationTests` 4 个用例。
- **运行时判定形态**：`WidgetMetricComputer.presentation` —— 状态类直接 `.status`；`remainingTime` / `sessionTokens` / `inputTokens` / `outputTokens` / `costSpent` / `sessionCredits` 按 `hasTotal(for:)` 决定 `.quota` 还是 `.counter`；其余默认 `.quota`。
- **清除全部写死分母**：
  - `sessionDuration` ÷28800、`tokensPerMinute` ÷200、`inputOutputRatio`、`costPerRequest` → 统一返回 0（已退役，按计数渲染）。
  - `resetCountdown` 的 ÷2_592_000 → 返回 0（时间点，非量级）。
  - `remainingTime` 的信用额度回退 ÷2_592_000 → 删除，仅真实 time quota 才有 fraction。
- **卡片按形态渲染**：`OverlayFocusCard` 在 `.showsGauge == false` 时隐藏 `ProgressRing` 与 `FocusGauge`，改用 `counterRule`（"累计用量 · 无额度上限" + 渐隐强调色细线），保持视觉重量但不谎报比例。
- **退役指标全链过滤**：`WidgetMetric.isSelectable` / `selectableCases`（委托 `RetiredMetrics`）；`WidgetStore` 载入时 `dropRetired` 静默丢弃；设置页预设、能力表、自定义 sheet 选项、core 推荐结果均按 `isSelectable` 过滤。enum case 保留，旧配置解码不会失败。
- **收起条**：`progressBar` 在 `fraction <= 0` 时改画中性细线，不再显示"看起来还剩很多"的空进度条。

### 验证结果（2026-08-02）

- `swift test`：通过，169 个测试（+4）。
- `xcodegen generate` 后 `xcodebuild ... build`：通过。

### 待手动验证

- 有额度的平台（Codex/MiniMax/MiMo）仍显示环 + 进度条；仅有消耗数据的（如 OpenAI costSpent 无额度）显示计数卡、无空进度条。
- 「可添加」列表与自定义面板中不再出现订阅状态/计划名/重置倒计时/会话时长/每分钟 token/输入输出比/单次成本。
- 若此前添加过上述指标，重启后应被静默移除且不报错。

### 追加修正：按"真实有无数据"过滤（2026-08-02）

**问题**：上一步只按"是否退役"过滤，「可添加」里仍堆着大量加了也只显示「—」的项。核对真实 `state.json` 后确认：`openai` / `gemini` / `anthropic` **根本不在文件里**（能力表却仍在提供它们的指标）；`minimax` 存在但 `error=usageUnsupported`、无配额无会话；`claude` 的 quota `total` 全为 `None`。

**修法**：可用性用**卡片真实取值**判断，而不是维护一张静态表——
`WidgetContentColumn.hasData(config:state:)` 直接调 `WidgetMetricComputer(...).formattedValue`，非「—」且非空才算可用。与卡片同一条代码路径，不会出现"表说有、卡片显示—"的偏差。

- 「可添加」拆成 `available`（默认展示）与 `unavailable`（折叠在「暂无数据 N」里，行半透明，附说明"在「平台」页配置后会自动出现在上面"）。
- 「已添加」行在取不到值时显示 `无数据` 警示胶囊，解释卡片为何是空的。
- `state` 经 `WidgetContentColumn` / `ActiveWidgetsPanel` / `WidgetRow` 传递。

**验证**：`swift test` 169 通过；`xcodebuild` 通过。

### 追加修正 2：在源头与唯一收口处过滤（2026-08-02）

**问题**：「已添加」里仍出现订阅状态。根因是前两轮**在各调用点分别打补丁，却漏了产生数据的源头**。全链路排查后找到 3 个漏口：

1. `WidgetStore.defaultWidgets` 本身含 `.subscriptionStatus` —— 列表为空或「恢复默认」时会重新写回。
2. `WidgetRecommendationEngine`（core）仍产出 `subscription_status` / `plan_name` / `reset_countdown` 三个描述符。
3. `dropRetired` 只在 `init` 调用；`resetToDefaults()` 与 `populateEmptyWidgetListIfNeeded()` 直接赋值绕过了它。

**修法（改为单一收口，不再逐点过滤）**：

- `WidgetStore.widgets` 的 `didSet` 内做净化：任何写入（默认值、恢复默认、迁移、编辑器、拖拽）都会被过滤，再赋值一次触发二次 `didSet` 后落盘。**这是唯一必须正确的地方**。
- 源头数据清理：`defaultWidgets` 去掉 `.subscriptionStatus`；core 推荐引擎去掉 3 个退役描述符；`widgetCapabilities` 的 `metrics`/`presets` 去掉退役项。
- `init` 的 v3 分支在确实丢弃了条目时补 `save()`（`didSet` 在 init 中不触发，否则清理不会落盘）。

**验证（对真实用户数据）**：重启后读取 `widgets_v3` 实际内容 →
`codex/remaining_time`、`claude/remaining_time`、`claude/session_tokens`、`codex/remaining_time`，**退役指标残留：无**。
`swift test` 169 通过；`xcodebuild` 通过。

## 当前重点：设置页方案 B — 双栏工作台 + 常驻预览（mockup 已选定，待代码确认）

### 问题

小组件页是四块面板竖向堆叠（推荐 / 预览 / 已添加+添加），要来回滚动才能"改一下看一眼"；「已添加」用原生 `List(.bordered)` + `minHeight 180`，既有表格观感又在内容少时留白；且外观类设置（进度条样式、内容大小、刘海收起态）在通用页，与它们影响的预览分处两页——用户连续两轮反馈"找不到"。

### 本轮目标（方案 B）

**小组件页重构为双栏**
- 左栏（约 1.15 份）：搜索框（按平台名/指标名过滤）→「已添加」（拖拽排序、可删）→「可添加」（推荐 + 预设，点击即加）。两个列表合并为一栏连续内容，取代现在的「已添加/添加」分段切换。
- 右栏（约 0.95 份）：**常驻实时预览**（媒体卡）+「显示」设置卡——进度条样式、内容大小、刘海收起态（左/右）。改设置立刻在上方预览看到效果。
- 移除顶部独立的「推荐组件」面板（并入左栏「可添加」）与「已添加/添加」分段控件。

**通用页收敛**
- 只保留：数据源、系统、应用过滤。原「HUD 外观」「刘海收起态」两组迁至小组件页右栏。

**统一观感**
- 「已添加」保留 `List` + `.onMove`（拖拽排序依赖它，重写风险高），但改 `.listStyle(.plain)` + `.scrollContentBackground(.hidden)` + 透明行背景，去掉表格边框与固定 `minHeight`，高度随内容。

不改：数据模型、fetcher、凭据、HUD 渲染与刘海几何。

### 实施步骤

1. `WidgetListEditor` 拆成 `WidgetContentColumn`（左）与 `WidgetInspectorColumn`（右）两个子视图，`body` 改为 `HStack`。
2. 左栏：新增 `@State searchText` + 过滤；合并「推荐 + 预设」为「可添加」列表；「已添加」List 去边框化。
3. 右栏：预览面板（复用现有 `WidgetPreviewPanel`）+ 新建「显示」设置卡，承载 `focusGaugeStyle` / `widgetSizeScale` / 收起态左右来源（从 `SettingsWindow` 的 `HUDAppearanceSection` 迁出）。
4. `SettingsWindow`：删除 `HUDAppearanceSection` 与「刘海收起态」分组，通用页只留数据源/系统/应用过滤。
5. 窗口最小宽度复核：双栏需要更宽，`minWidth` 由 760 视情况上调（若不足则左右栏用 `ViewThatFits` 回退单栏）。
6. 验证（见下）。

### 验证

- `swift test`（应为纯 UI 改动，无核心逻辑变化）。
- `xcodebuild ... build`。
- 运行截图：小组件页双栏布局、搜索过滤生效、拖拽排序仍可用、改右栏设置预览实时变化；通用页只剩三组。

### 风险

- 拖拽排序依赖 `List.onMove`，去边框化时若样式覆盖不当可能破坏重排手感 → 保留 List 本体，只改样式，不自造拖拽。
- 双栏在窄窗口会挤压 → 设置合理 `minWidth` 并在过窄时回退单栏。
- 设置项跨页迁移会改变用户已有的心智位置，但正是本轮要解决的问题；`@AppStorage` key 不变，配置不受影响。

### 本轮实现结果（2026-08-02）

- **小组件页双栏**：`WidgetListEditor.body` 改为 `ViewThatFits`（宽 → `HStack` 双栏；窄 → 单栏堆叠，预览在上）。
  - 左栏 `WidgetContentColumn`（新）：搜索框（按平台名/指标名过滤）→ `ActiveWidgetsPanel`（已添加，拖拽排序）→「可添加」（推荐 + 预设去重合并，`AddableWidgetRow` 点击即加，带「自定义」入口）。
  - 右栏：`WidgetPreviewPanel`（常驻预览）+ `WidgetDisplaySettingsPanel`（新）——进度条样式 / 内容大小 / 刘海收起态左右来源。
- **已添加列表去表格化**：保留 `List` + `.onMove`（拖拽排序不自造），改 `.listStyle(.plain)` + `.scrollContentBackground(.hidden)` + 透明行/无分隔线；固定 `minHeight: 180` 改为随内容的 `listHeight`（clamp 76...320）。
- **删除被取代的面板**：`ConfiguredWidgetRecommendationPanel`、`RecommendationChip`、`WidgetManagementPanel`（已添加/添加分段）、`AddWidgetsPanel`、`PresetCard`，及随之失效的 `prependWidget` / `prependMissingRecommendations` / `configuredProviderCount`。
- **通用页收敛**：删除 `HUDAppearanceSection`（含刘海收起态），现只剩 数据源 / 系统 / 应用过滤。
- **窗口尺寸**：`minWidth` 760 → 820、`idealWidth` 900 → 1000，保证双栏成立；不足时自动回退单栏。

### 验证结果（2026-08-02）

- `swift test`：通过，165 个测试。
- `xcodebuild ... build`：通过。
- 累计（本会话设置重构全部轮次）：**+1576 / -3000 行**。

### 待手动验证

- 双栏在默认窗口宽度下的排布；缩窄窗口时回退单栏是否自然。
- 搜索过滤、点击添加、拖拽排序、删除是否都正常。
- 右栏改「进度条样式 / 内容大小」时，上方预览是否实时变化。

## 当前重点：刘海展开 header + 设置页信息架构重构与清死代码（待确认）

### 问题

**1. 刘海展开时状态栏两侧看不到内容**

根因（读 `NotchGeometryCalculator.hostedSurfaceLayout` 确认）：状态槽是给**收起药丸**设计的——
`collapsedStatusWidth = min(compactStatusSlotWidth(56), maxSideExpansion, screenLeftRoom, screenRightRoom)`，
`leftStatusSlot.x = topCap.minX`、`rightStatusSlot = topCap.maxX - statusWidth`。
展开后 `topCapWidth = bodyWidth` 被拉到 `expandedBodyMaxWidth`，两个 56pt 的窄槽被推到**宽卡片的最外侧边缘**，既窄又远离刘海，视觉上等于没有。上一轮我只是把它们的 opacity 打开，位置没变，所以没效果。

**2. 设置页逻辑混乱（代码审计结果，问题比反馈更严重）**

- **整条 widget 渲染链已死**：`WidgetRenderer` **0 处外部引用**；8 个 widget 视图（Bar/Ring/Text/Aggregate/Multi/Status/Countdown/ModelBreakdown）**仅被 WidgetRenderer 引用** → 全链死代码。另 `PlatformRowView.swift`（**1183 行**）无任何引用。
- **UI 在显示无效设置**：`WidgetConfig.style` 渲染早已忽略，但小组件页仍显示样式图标/名称（`styleIcon`、`style.displayName`），自定义 sheet 仍有样式选择器 → **用户改了完全没反应**。
- **两套缩放互相冲突**：`floatingPanelScale`（通用→浮动面板→缩放 0.5–2x，只作用 detached，且和捏合手势同源）与 `widgetSizeScale`（通用→外观→小组件大小 小/中/大，作用全部 HUD）。
- **布局设置位置错误**：「布局」放在"浮动面板"分组下，但它同时控制刘海展开面板 → 命名误导，用户找不到（本次反馈第 2 点）。
- **相关设置被拆散**：「刘海收起态」在小组件页，布局/外观在通用页。
- **`hudOpacity` 语义冲突**：focus 布局在刘海内是纯黑，透明度滑块无效果。
- **布局选项冗余**：`paged`（一屏一个 + 翻页）与 `focus`（一屏一个 + 翻页）功能高度重合。

### 本轮目标

**A. 刘海展开 header（修问题 1）**
- 展开态不再复用收起态窄槽：按 `topCap` 实际宽度重新排布，左右各留内边距，中间避开刘海缺口。
- 内容：左＝平台图标 + 名称，右＝数值 +（有则）重置倒计时；收起态维持现状（进度条 + 文本）不变。

**B. 清死代码**
- 删除 `WidgetRenderer.swift` + 8 个 widget 视图 + `PlatformRowView.swift`（合计约 2000+ 行）。
- 保留 `WidgetConfig.style` **存储字段**（旧配置解码兼容），但移除所有 style 相关 UI。

**C. 设置页信息架构重构**
- 三页保持（小组件 / 平台 / 通用），但重排分组：
  - 「小组件」：只管**内容**——推荐、实时预览、已添加/添加、排序。移除样式相关 UI。
  - 「通用」→ 重组为：**HUD 外观**（布局、进度条样式、小组件大小、透明度、刘海收起态左右来源）、**数据**（state.json 路径、刷新间隔）、**系统**（登录启动、全局快捷键、应用过滤）。
  - 「刘海收起态」从小组件页移入通用页 HUD 外观分组，与布局并列。
- 「布局」分组名从"浮动面板"改为"HUD 外观"，消除"只影响浮窗"的误导。
- 合并缩放：**保留 `widgetSizeScale`**（统一 HUD 内容缩放），删除 `floatingPanelScale` 设置项与其 UI；detached 捏合手势改写 `widgetSizeScale`。
- 布局选项去掉 `paged`（与 focus 重合），保留 focus / summary / drawer。
- `hudOpacity` 仅在会用到玻璃的场景显示（非 focus 布局），并在说明里写清作用范围。

不改：数据模型 `state.json`、fetcher 抓取逻辑、凭据、刘海吸附/脱离几何策略。

### 实施步骤

1. **A**：`NotchHostedSurfaceView` 增加展开态 header 分支（按 topCap 排布，避开 notchGap），收起态走原路径；必要时几何层补一个 `expandedHeaderSlots` 计算并加测试。
2. **B**：删除死文件 → `xcodegen generate` → 构建验证。
3. **C1**：移除 style UI（`styleIcon`、显示名、自定义 sheet 的样式选择器），`WidgetConfig` 存储字段与解码保持不变。
4. **C2**：删 `floatingPanelScale`，捏合手势改写 `widgetSizeScale`。
5. **C3**：`OverlayLayout` 移除 `paged`（含 `OverlayPagedView`、`pagedExpandedHeight` 及其测试），`from()` 对旧值 `"paged"` 回落到 `focus`。
6. **C4**：重排 `SettingsWindow` 分组 + 把刘海收起态面板从 `WidgetListEditor` 移入通用页。
7. 验证（见下）。

### 验证

- `swift test`（更新受影响的几何/枚举用例）。
- `xcodegen generate` 后 `xcodebuild ... build`。
- 运行截图：通用页新分组清晰、布局选择器一眼可见；小组件页无失效的样式 UI；旧配置（含 `paged`、含 style 字段）能正常加载不崩。
- 手动：刘海展开时 header 左右有内容且不压刘海。

### 风险

- 删除 `paged` 会让已选该布局的用户配置失效 → `from()` 必须容错回落，且保留 `WidgetConfig.style` 解码，避免破坏已保存数据。
- 删除 `floatingPanelScale` 后旧值残留无害（不再读取），但捏合手势改写 `widgetSizeScale` 会影响刘海内容大小，需确认可接受。
- 一次删约 2000 行死代码，必须靠构建 + 全量测试兜底，分步提交便于回滚。
- 展开 header 涉及刘海几何（历史多次回归），只新增展开分支，不动收起态与吸附/脱离逻辑。

### 本轮实现结果（2026-08-02）

- **A 展开 header**：`NotchHostedSurfaceView` 增加 `expandedHeader(layout:)`，展开态（`body.height > 0.5`）走它、收起态仍走原 `statusSlot`。按 `topCap` 实宽排布：左侧 = 平台图标 chip + 名称，右侧 = 主数值（强调色）；两侧各留 14pt 边距并距 `notchGap` 再留 10pt，避免压到摄像头；宽度不足 40pt 时自动隐藏该侧。数据取 `store.widgets.first`（与聚焦卡 hero 同源）。
- **B 死代码清理（-1669 行）**：删除 `WidgetRenderer.swift` + 8 个 widget 视图（Bar/Ring/Text/Aggregate/Multi/Status/Countdown/ModelBreakdown）+ `PlatformRowView.swift`。
  - 注意：`PlatformRowView.swift` 内另含仍被使用的 `CodexAuthStatus`，已迁到其唯一使用者 `PlatformListView.swift` 的 `CodexAuthReader` 旁（`PlatformConfig`/`APIKeyGroupView` 确认零引用，随文件删除）。
- **C1 移除无效 style UI**：删 `styleIcon`、`availableStyles`、自定义 sheet 的样式选择器、已添加行/预设卡上的样式图标与名称（改显示平台名）。`WidgetConfig.style` 存储与解码保持不变，旧配置不受影响。
- **C2 合并缩放**：删除 `floatingPanelScale` 及其设置项；`FloatingPanelView` 的捏合手势改写 `widgetSizeScale`（clamp 0.6...2.0），去掉重复的 `scaleEffect`。
- **C3 移除 paged**：`OverlayLayout` 去掉 `.paged`，删 `OverlayPagedView`、`NotchGeometryCalculator.pagedExpandedHeight()` 及其测试、manager 分支；`from()` 对旧值 `"paged"` 回落 `.focus`。`PageDots` 迁到 `OverlayFocusCard.swift`（focus 仍在用）。
- **C4 设置页信息架构**：通用页重组为 **HUD 外观**（布局 / 进度条样式(focus 时) / 内容大小 / 透明度(非 focus 时)）→ **数据源** → **系统**（启用浮动面板、呼出快捷键 + 辅助功能授权、登录时启动）→ **应用过滤**。
  - 「布局」从"浮动面板"组移到最顶部，并注明"同时作用于刘海展开面板和脱离的浮动面板"（原命名误导，用户找不到）。
  - `hudOpacity` 仅在非 focus 布局显示（focus 在刘海内是纯黑，滑块无作用）。

### 与计划的偏差

- **「刘海收起态」未从小组件页移出**。原因：其选择器需要 `recommendedWidgets`（依赖凭据快照 + 推荐引擎），移到通用页要么丢掉"已配置推荐"分组、要么重复一份推荐逻辑。且该设置本质是选*哪个 widget* 供给收起条＝内容语义，留在小组件页更贴合。功能未削减。

### 验证结果（2026-08-02）

- `swift test`：通过，173 个测试（因删除 paged 高度用例，由 174 → 173）。
- `xcodegen generate` 后 `xcodebuild ... build`：通过。
- 通用页运行截图核对：三组结构清晰，布局选择器位于首屏首项。

### 待手动验证

- 刘海展开时 header 左右是否有内容且不压刘海（本轮无法自动触发展开态）。
- 浮动面板双指捏合改写内容大小的手感（现在会同时影响刘海内容）。
- 旧配置（曾选 `paged`、含 style 字段）加载后是否正常回落到聚焦布局。

## 追加：收敛为单一媒体卡 + 设置可发现性（2026-08-02，已实现）

### 问题

用户体验后提出：既然只保留媒体卡，「聚焦/摘要/列表」三选一已无意义；且**仍找不到布局切换与刘海收起态样式的入口**——因为布局选项本身已无实际选择价值，而刘海收起态上一轮被我留在了小组件页。

### 实施

- **删除多布局，收敛为单一媒体卡**：
  - 删除 `OverlayLayout` 枚举、`OverlayContentView` 分发、`OverlaySummaryView` / `OverlayListView` / `OverlayHeroRow` / `OverlayListRow` / `UsageBar` / `ValueColumnFrame`（整个 `OverlayListView.swift`）。
  - 三处调用点（`NotchHostedSurfaceView` / `FloatingPanelView` / 设置页实时预览）直接渲染 `OverlayFocusView`。
  - `ServiceIconChip` 迁入 `OverlayFocusCard.swift`（focus 与展开 header 仍在用）。
  - core 侧连带删除已死的 `SummaryEntranceAnimation`（+测试）与 `adaptiveExpandedHeight`（+3 个测试）；`computeFrames` 简化为恒用 `focusExpandedHeight()`。
- **删除随之失效的设置**：布局选择器、`hudOpacity`（媒体卡自绘背景，滑块无作用）及其读取点。
- **刘海收起态移入通用页**：`HUDAppearanceSection` 之后新增「刘海收起态」分组（左/右来源菜单），从 `WidgetListEditor` 删除原 `NotchCollapsedSettingsPanel`。
  - 取舍：新选择器只提供「自动 + 当前小组件」，不再有原来的「已配置推荐」子分组——该分组依赖凭据快照 + 推荐引擎，移到通用页需重复一份逻辑；收起条本就应从已添加的小组件里选，功能损失可接受。

### 结果

- 通用页最终结构：**HUD 外观**（进度条样式 / 内容大小）→ **刘海收起态**（左侧 / 右侧）→ **数据源** → **系统** → **应用过滤**。
- `swift test` 165 通过；`xcodebuild` 通过。
- 本轮（含前一段）累计 **-2720 行 / +1365 行**。

## 当前重点：聚焦卡进度条样式可选（待确认）

### 问题

聚焦卡当前的主视觉是硬边分段柱状波形，与卡片"流光/水光"质感冲突（用户反馈"一格一格的不搭"）。经 mockup 出了 8 个替代方案，用户希望**全部保留**并在设置里由用户选择。

### 本轮目标

- 新增 `FocusGaugeStyle` 枚举（9 项：现有 `classicBars` + 以下 8 项），作为聚焦卡主视觉的可选样式：
  - `glowBar` 连续流光条：胶囊轨道 + 渐变填充 + 高光扫过。
  - `wave` 流动波浪：连续正弦线 + 下方光晕填充，缓慢流动。
  - `aurora` 极光 band：无边缘光雾，漂移。
  - `softDots` 柔化光点：圆润发光柱 + 亮波流过。
  - `liquid` 液态水银条：胶囊内液面晃动。
  - `particles` 粒子流：发光粒子沿轨道流动。
  - `arc` 光弧地平线：弧形光带 + 光点滑行。
  - `fiber` 光纤束：多条细光线并行交错流动。
- 所有样式统一接口：输入 `fraction`(0...1) + `accent`，输出等高视图；用量以填充范围/密度/亮度体现。
- 设置页新增选择器（菜单式，9 项），仅在布局为「聚焦」时显示；小组件页「实时预览」自动反映。
- 默认样式 `wave`（流动波浪）。
- 尊重 `accessibilityReduceMotion`：所有样式退回静态帧，不做循环动画。

### 实施步骤

1. `Sources/token_hudCore/FocusGaugeStyle.swift`：枚举 + `displayName` + `from(_:)` 容错解析；补 Swift Testing（未知值回落默认、`allCases` 覆盖）。
2. `token_hud/Overlay/FocusGauges.swift`：9 个样式视图，统一 `FocusGauge(style:fraction:accent:)` 入口分发；动画一律 `TimelineView(.animation)` + `Canvas`，Reduce Motion 走静态分支。
3. `OverlayFocusCard` 用 `@AppStorage("focusGaugeStyle")` 取样式，替换现在写死的 `WaveformView`。
4. `SettingsWindow` 浮动面板区块：布局为 focus 时显示「进度条样式」菜单选择器。
5. 验证（见下）。

### 验证

- `swift test`（含新增枚举用例）。
- `xcodegen generate`（新增文件）后 `xcodebuild ... build`。
- 运行截图：设置页切换 9 种样式，实时预览逐一正确渲染、无布局跳动；Reduce Motion 下静态。

### 风险

- 9 个动画视图若同时存在会耗性能；实际同一时刻只渲染一个，且 `TimelineView` 仅在可见时驱动，风险可控。
- 各样式高度需一致（32–40pt），否则切换时卡片高度跳动——统一固定高度。
- 粒子/光纤等样式在低 fraction 时要能看出差异，避免"看起来都一样"。

### 本轮实现结果（2026-07-29）

- **用户决定**：去掉经典硬边波形，只保留 8 种新样式；默认 `wave`（流动波浪）。
- 新增 `Sources/token_hudCore/FocusGaugeStyle.swift`：8 个 case + `displayName`（中文）+ `from(_:)` 容错 + `default`；`FocusGaugeStyleTests` 3 个用例（round-trip / 未知回落 / 8 项且名称唯一）。
- 新增 `token_hud/Overlay/FocusGauges.swift`：`FocusGauge(style:fraction:accent:)` 单一入口，内部 `Canvas` 绘制 8 种样式，全部是 `(t, fraction, size)` 的纯函数；动画由单个 `TimelineView(.animation)` 驱动，Reduce Motion 时 `t = 0` 渲染静态帧。
  - glowBar（渐变填充 + `clip` 内高光扫过）、wave（正弦线 + 下方光晕，超出 fraction 的部分只留暗基线）、aurora（`.blur` + `plusLighter` 漂移光斑）、softDots（圆润柱 + 行进亮波）、liquid（胶囊 clip + 波动液面，末端有张力收拢）、particles（26 个确定性粒子，速度/相位由 index 推导，无状态）、arc（二次贝塞尔弧 + 沿弧滑行光点）、fiber（4 条正弦光带，两端向中线收拢）。
- `OverlayFocusCard` 改用 `@AppStorage("focusGaugeStyle")` + `FocusGauge`，删除写死的 `WaveformView`（已无引用的死代码）。
- `SettingsWindow` 浮动面板区块：布局为 `focus` 时显示「进度条样式」菜单选择器（8 项），并提示可在小组件页实时预览查看。

### 验证结果（2026-07-29）

- `swift test`：通过，174 个测试（+3）。
- `xcodegen generate` 后 `xcodebuild ... build`：通过。
- 逐一切换 8 种样式启动：**全部存活无崩溃**；截图确认 `wave`（连续发光线 + 光晕）与 `particles`（沿轨道流动的发光粒子）渲染正确。

### 待手动验证

- 在设置里逐个切换 8 种样式，确认观感与预期一致、卡片高度不跳动。
- 低用量（fraction 很小）时各样式是否仍能区分。
- Reduce Motion 开启时全部为静态帧。

## 当前重点：浮窗「聚焦卡」媒体卡风格（brainstorming + mockup 已确认，待代码确认）

### 背景与已确认方向

用户给了一张"灵动岛/Live Activity 媒体卡"参考图，要求把浮窗做成那种效果。经问答 + mockup 确认：

- **单指标聚焦卡**：一次放大展示一个 provider/指标，多平台靠左右翻页（圆点指示）。
- **波形 = 用量趋势**：中间波形柱表现当前 hero 指标的占用——已用部分用平台强调色点亮（左→右渐暗），剩余暗灰。不依赖历史数据。
- **辉光跟随平台色**：卡片外发光用各 provider 强调色（Claude 橙 / Codex 紫…）。
- **控件映射真实操作**：底部 收起 ▾ / 刷新 ↻ / 更多 ···，接真实动作。
- 深色玻璃卡（透出桌面）+ 强调色内晕 + 大圆角。

参考图元素 → 映射：圆环+大数字=强调色进度环+hero 用量%；右上标签+图标=指标名(强调色)+平台图标 chip；副标题=平台·计划·已用%；右侧胶囊=重置倒计时；波形=用量趋势；底部控件=收起/刷新/更多；绿色辉光=平台色外发光。

### 本轮目标

- 新增聚焦卡视图与波形，作为新的浮窗布局 `.focus`，可在 Settings「布局」里选择；默认仍由用户切换（不强制替换现有摘要/列表/分页）。
- 控件接真实操作（低耦合，用 NotificationCenter，避免改浮窗生命周期与 fetcher 构造）：
  - 刷新 ↻ → post `TokenHUD.refreshNow`；`CodexFetcher`/`APIPlatformFetcher` 加观察者调用 `fetchAll(allowUserInteraction: false)`。
  - 更多 ··· → post `TokenHUD.openSettings`；`AppDelegate` 观察后调 `openSettings()`。
  - 收起 ▾ → post `TokenHUD.collapseHUD`；`NotchHostPanelManager` 观察后折叠/隐藏（复用现有 toggle/collapse 路径）。
- 几何：hosted 展开态为 focus 布局提供合适高度（新增 `focusExpandedHeight`，比列表高、固定单卡高）；detached 浮窗按窗口自适应缩放。
- 不改数据模型、fetcher 抓取逻辑、凭据、刘海吸附/脱离几何策略。

### 实施步骤

1. 新增 `token_hud/Overlay/OverlayFocusCard.swift`：单卡（强调色进度环 + hero 大数值 + 指标名/图标 + 重置胶囊 + 副标题 + 波形 + 控件）。用 `WidgetMetricComputer` 取值，`serviceAccentSwiftUIColor` 取强调色。
2. 波形：`Canvas` 画 N 根柱，高度按确定性包络（sin+jitter），`index/N < fraction` 的柱用强调色渐亮，其余暗灰。
3. 卡片背景：玻璃 + 强调色外发光（`shadow(color: accent...)` 叠加）+ 强调色内晕；复用/扩展 `GlassPanelBackground` 或新建 `FocusCardBackground`。
4. 分页容器 `OverlayFocusView`：横向 `scrollTargetBehavior(.paging)` + `PageDots`（复用现有），每页一张聚焦卡。
5. `OverlayLayout` 增加 `.focus`；`OverlayContentView` 分发；Settings「布局」Picker 增加「聚焦」。
6. 几何：`NotchGeometryCalculator` 增加 focus 单卡高度分支；`NotchHostPanelManager` 布局为 focus 时用它；补/更新几何测试。
7. 控件接线：定义 `Notification.Name` 常量；fetcher/AppDelegate/manager 加观察者；卡片按钮 post。
8. 验证（见下）。

### 验证

- `swift test`（含 focus 几何用例）。
- `xcodegen generate`（新增文件）后 `xcodebuild ... build`。
- 运行截图：detached 浮窗 focus 卡观感（辉光跟随平台色、波形、控件），左右翻页 + 圆点；hosted 展开 focus 高度合适；刷新/更多/收起按钮真实生效。

### 风险

- Canvas 波形在频繁数据刷新时避免重算过重；柱高包络用纯函数、只在 fraction 变化时动画。
- 控件用 NotificationCenter 解耦，避免动浮窗生命周期（该模块历史多次回归）；observer 记得在合适时机移除。
- focus 单卡较高，hosted 刘海几何要给合理固定高度，别撑破；detached 靠窗口缩放。
- `.focus` 为可选布局，不强制替换现有布局，控制影响面。

### 本轮实现结果（2026-07-29）

- **新增聚焦卡** `token_hud/Overlay/OverlayFocusCard.swift`：`OverlayFocusCard`（进度环 + hero 大数值 + 指标名/图标 chip + 重置胶囊 + 斜体副标题 + 波形 + 控件）、`ProgressRing`、`WaveformView`（`Canvas` 画 44 根柱，确定性包络，已用部分强调色渐亮）、`FocusCardBackground`（玻璃 + 强调色外发光 + 内晕，Reduce Transparency 回落）、`OverlayFocusView`（翻页容器 + 圆点）。
- **环/波形与大数字同步**：`gaugeFraction` 优先解析 hero value 里的百分比（`percentage(in:)`），解析不到才回落 `metric.fraction`——解决"环 11% 但数字 89%"的矛盾。
- **新增布局 `.focus`**：`OverlayLayout` 增加 `focus` 且设为 `from()` 默认；`OverlayContentView` 分发；`PageDots` 改 internal 复用。**focus 设为出厂默认布局**（4 处 AppStorage 默认值 + manager fallback 全改 focus）；Settings「布局」Picker 增加「聚焦」。
- **几何**：`NotchGeometryCalculator.focusExpandedHeight()`（固定 ≥172）；manager `computeFrames` focus 分支用它；测试 `focusHeightIsFixedAndTallEnoughForCard`。
- **控件接真实操作（NotificationCenter 解耦）**：`Notification.Name` 常量（`hudRefreshNow`/`hudOpenSettings`/`hudCollapse`）于 `HUDActions.swift`；`CodexFetcher`/`APIPlatformFetcher` init 加 `hudRefreshNow` 观察者调 `fetch/fetchAll(allowUserInteraction:false)`（stop 里移除）；`AppDelegate` 观察 `hudOpenSettings` → `openSettings()`；`NotchHostPanelManager` 观察 `hudCollapse` → 折叠展开态/隐藏 detached。
- **detached 浮窗 focus 去双层玻璃**：`FloatingPanelView` focus 时不画自身 `GlassPanelBackground`、padding 归零，让聚焦卡本身即浮窗。
- **已知限制**：hosted 刘海展开态里聚焦卡带自身圆角+辉光，与刘海方形顶未完美融合（本轮以 detached 浮窗为主，notch 融合留后续）；`percentage(in:)` 在 app target，未走 core 单测。

### 验证结果（2026-07-29）

- `swift test`：通过，171 个测试（+1 focus 高度用例）。
- `xcodegen generate` 后 `xcodebuild ... build`：通过。
- 运行截图（Settings 实时预览，与 detached/hosted 同一渲染路径）：聚焦卡观感贴合参考图——进度环 + 大数值 + 波形（已用渐亮）+ 重置胶囊 + 控件；环/波形与 89% 数字一致。

### 待手动验证

- 脱离浮窗（快捷键呼出）实际观感：单卡玻璃 + 强调色外发光、左右翻页 + 圆点、无双层玻璃。
- 控件真实生效：刷新 ↻ 触发抓取、更多 ··· 打开设置、收起 ▾ 折叠/隐藏。
- 不同平台切换时辉光/环/波形颜色跟随强调色（Claude 橙、Codex 紫等）。
- hosted 刘海展开态 focus 卡观感（已知未完美融合，评估是否需要单独适配）。

## 当前重点：Settings UI 适配排查与修复（已完成，见下）

### 问题（已通过运行截图 + 代码核实）

用户反馈整个设置窗有大量"不适配"。当前系统为深色外观，问题集中在**布局贴合/材质一致性**，不是亮/暗色配色。已确认：

**小组件页（已看到实物）**
1. 「实时预览」面板固定 `240px` 高、内容顶对齐（`WidgetListEditor.swift:622`），单/少组件时下方一大片黑色空洞。
2. 「主指标 (hero)」标注放在 `.topTrailing`（`:611-618`），与 hero 右上角的大号数值**重叠**。
3. 预览面板底仍是实心深色 `SurfaceLevel.raised.gradient`（`:582`），但真实 HUD 本轮已改玻璃——预览与实物质感不再一致。
4. `NotchCollapsedSettingsPanel.progressColor`（`:554-558`）是**第 4 套**重复的严重度配色，阈值/色值与 `Theme.severityColor` 不统一。
5. 默认窗口高度下详情底部被裁（预览吃掉 240px 是主因，修 1 缓解）。

**通用页（代码核实）**
6. 原生 `Form(.grouped)`（`SettingsWindow.swift:142`）在磨砂玻璃底上违和（历史已知欠债）。

**平台页（待审计）**
7. 结构较统一（sidebar 260 + 玻璃卡片），但需按同一套 lens 过一遍：重复色值、卡片层级/间距、固定宽度截断。

### 本轮目标

- 小组件页：预览面板高度自适应内容（clamp 上下限、去黑洞）；hero 标注移到不遮挡位置；预览质感与真实 HUD 对齐；`progressColor` 收敛到 `Theme.severityColor`（消除第 4 套）。
- 通用页：让原生 Form 在玻璃底上协调（统一背景/分组样式，不整体重写）。
- 平台页：代码审计后修掉发现的固定宽截断、重复色值、间距不一致。
- 不改功能、数据模型、fetcher；纯 UI 布局/材质对齐。

### 实施步骤

1. 修 `WidgetPreviewPanel`：高度改为自适应（`fixedSize`/内容测量 + clamp），内容对齐调整，hero 标注移位，面板材质与 HUD 对齐。
2. `NotchCollapsedSettingsPanel.progressColor` → `Theme.severityColor(forFraction:)`。
3. 平台页/通用页按审计结果逐项修（小步、范围集中）。
4. 逐页运行截图核对。

### 验证

- `swift test`（应为纯 UI 改动，无逻辑回退）。
- `xcodebuild ... build`。
- 逐页运行截图：小组件预览无黑洞/无重叠、底部不裁切；通用页 Form 与玻璃协调；平台页无截断。

### 风险

- 预览自适应高度若用 `OverlayContentView` 实测高度，需注意其内部 ScrollView 不能塌成 0；给合理 min/max。
- 通用页 Form 协调不整体重写，控制范围避免蔓延。
- 平台页审计可能牵出较多小项；按优先级只修"看得见的不适配"，不做无关重构。

### 本轮实现结果（2026-07-29）

- **小组件页（重灾区，已修）**：
  - `WidgetPreviewPanel` 高度从固定 `240` 改为 `previewHeight`（hero 62 + 每多一条 40 + padding，clamp 300），单/少组件不再有黑洞；`.frame(height: previewHeight)`。
  - 移除与 hero 大数值重叠的「主指标 (hero)」浮标注（信息已由 `summaryText` 表达），ZStack 对齐从 `.topTrailing` 改回默认居中。
  - 预览面板底改用 `GlassPanelBackground(opacity: 0.6)`，与真实 HUD 玻璃质感一致（替换原 `SurfaceLevel.raised.gradient` 实心深色）。
  - `NotchCollapsedSettingsPanel.progressColor` 收敛到 `Theme.severityColor(forFraction:)`（消除第 4 套重复严重度配色）。
- **平台页 / 通用页审计结论**：逐页临时改默认 section 截图核对后，两页布局/材质基本协调，无明显黑洞/重叠/截断；本轮未改（`Form(.grouped)` 在玻璃上可接受）。
- **已知剩余小项（未做，待用户确认是否处理）**：`ActiveWidgetsPanel` 用原生 `List(.bordered)` + `minHeight: 180`，单组件时下方留空、表格质感与玻璃卡片略不搭；改造涉及拖拽重排，范围较大，暂留。

### 验证结果（2026-07-29）

- `swift test`：通过，170 个测试。
- `xcodebuild ... build`：通过。
- 逐页运行截图核对：小组件预览贴合内容/无重叠/质感一致；平台、通用页协调。

## 当前重点：HUD 玻璃透明化 + Lv1 减法 + token 统一（brainstorming 已确认，待实现）

### 背景与已确认方向

用户要求做较大的前端调整，两个轴：(1) 布局更简洁；(2) 质感更透明、更像工具类 App。经 brainstorming 可视化对比后确认：

- **以现状 A 布局为底做减法**（不是推翻重来）。
- **质感转向半透明毛玻璃**（透出桌面），替换现在的实心深色卡。
- **减法力度 = Lv1（保守）**：保留图标块与信息层级，只做轻量精简。
- **范围 = HUD + 设置窗一致化**（设置窗已是玻璃风，本轮主要对齐 token，不改结构）。

### 问题

1. HUD 现在是实心深色卡（`SolidPanelBackground` 刻意不透明），与"透明工具感"诉求相反。
2. 布局偏"厚重"：每行都有进度条 + 副标题 + 分隔线，信息密度高、表格感强。
3. 视觉语言仍有历史欠债，玻璃化后会更显眼：
   - 严重度绿/黄/红颜色 + 阈值在 `progressColor`（折叠条，阈值 0.85/0.65）、`UsageBar.barColor`（阈值 0.5/0.8）、`Theme.Palette.status*` 三处各定义一套，值和阈值都不一致。
   - 进度方向矛盾：折叠条 `progressBar` 画"已用 fraction"，`UsageBar` 画"剩余 1-fraction"。
   - 字号 30/26/18/12/9 等散落硬编码，无统一 ramp。
   - 设置窗 `SettingsWindow.swift` 侧栏画了两条重复分隔线（:20 与 :71）。

### 本轮目标

**A. 质感玻璃化（展开面板主体 + 脱离浮动面板）**
- 新增 `GlassPanelBackground`：`.ultraThinMaterial` 打底 + 极淡深色 tint + 0.5px 高光描边，透出桌面。`SolidPanelBackground` 保留但 HUD 不再默认使用。
- `NotchHostedSurfaceView.bodyPanel` 与 `FloatingPanelView` 背景改用玻璃。
- 刘海折叠态"黑帽子"（`topCap`）保持纯黑不变，保证与物理刘海无缝融合；玻璃只作用于展开后主体。
- 现有 `hudOpacity` 语义改为调节玻璃 tint 浓淡（低=更浓深色玻璃，高=更清透），而非整体 alpha。先定位 `hudOpacity` 当前作用点再改。

**B. Lv1 减法布局（`OverlaySummaryView` / `OverlayHeroRow` / `OverlayListRow`）**
- Hero（第一条）：保留 图标块 + 名称 + 副标题 + 放大数字 + 进度条（唯一保留进度条的行）。
- 次要行：收成单行——小图标块 + 名称 + 百分比，去掉进度条，副标题默认隐藏。
- 分隔线变淡（白 0.05）或改为纯间距分组，弱化表格感。
- 同时作用于刘海展开面板与脱离浮动面板（共用 summary）。

**C. token 统一（顺手修历史欠债）**
- `Theme.severity(for: fraction) -> Color`（含统一阈值）作为绿/黄/红唯一来源，替换 `progressColor` 与 `UsageBar.barColor` 的两套内联值。
- 统一进度方向：折叠条与 `UsageBar` 统一表示同一语义（与百分比数字一致），先读 `WidgetMetricComputer.fraction` 语义再定"已用/剩余"。
- 新增 `Theme.Typography`：hero/value/title/caption/mono 几档，替换 HUD 内散落字号。

**D. 设置窗一致化**
- 用统一后的 severity 色 / 字号档 / 间距对齐设置窗；去掉 `SettingsWindow.swift` 侧栏重复分隔线。不改结构。

不改：`state.json` schema、fetcher、凭据、刘海吸附/脱离几何与生命周期、`WidgetConfig` 存储。

### 实施步骤

1. **Theme 扩展**：`Theme.severity(for:)` + `Theme.Typography`；保留现有 Palette/Radius/Spacing。补 `Sources/token_hudCore` 可测的 severity 阈值纯逻辑（若阈值/取色可下沉），加 Swift Testing。
2. **玻璃背景**：新增 `GlassPanelBackground`（material + tint + 高光描边），`hudOpacity` 驱动 tint。先验证当前 NSPanel 上 `.ultraThinMaterial` 能否产生 behind-window 模糊；不行则回退 `NSVisualEffectView` representable。
3. **接入 HUD**：`NotchHostedSurfaceView.bodyPanel` 与 `FloatingPanelView` 换玻璃背景；`topCap` 保持纯黑；`progressColor` 改走 `Theme.severity`。
4. **Lv1 布局**：改 `OverlayHeroRow.summaryBody`（保留 bar）、`OverlayListRow`（次要行单行、去 bar、隐副标题）、`OverlaySummaryView` 分隔线变淡；`UsageBar` 颜色走 `Theme.severity`、方向与折叠条统一。
5. **设置窗对齐**：severity/typography/spacing token 化；删重复分隔线。
6. **验证**（见下）。

### 验证

- `swift test`（含新增 severity 阈值用例）。
- `xcodegen generate`（若新增文件）后 `xcodebuild -project token_hud.xcodeproj -scheme token_hud -destination 'platform=macOS' build`。
- 手动：亮/暗桌面 + 亮/暗系统外观 + Reduce Transparency 下玻璃可读性；折叠态仍纯黑融合刘海；`hudOpacity` 滑块调玻璃浓淡；Lv1 布局在 1 条/多条/超多条下的层级与滚动；severity 颜色折叠态与展开态一致。

### 风险

- **玻璃透出桌面依赖宿主窗口非不透明 + behind-window 混合**。若 SwiftUI material 不生效需回退 `NSVisualEffectView`，属本轮主要不确定点，先验证再铺开。
- 折叠态必须保持纯黑；玻璃只能在展开主体，避免破坏刘海融合（该模块历史多次回归）。
- `hudOpacity` 语义变更需先定位其现有作用点，避免与玻璃 tint 双重叠加导致过暗/过淡。
- token 统一（severity 方向/阈值）会改变现有配色观感，需手动确认警示语义仍正确（高占用=红）。
- Reduce Transparency 下玻璃退化的兜底（回落到接近实心深色）要一并处理，避免文字发灰不可读。

### 本轮实现结果（2026-07-29）

- **A 玻璃化**：
  - 新增 `token_hud/Overlay/GlassPanelBackground.swift`：`.ultraThinMaterial`（宿主窗口 `isOpaque=false`/`backgroundColor=.clear`，真透出桌面）+ `hudOpacity` 驱动的深色 tint 渐变 + 0.5px 高光描边 + 柔和阴影；`accessibilityReduceTransparency` 下回落到 `SurfaceLevel.raised.gradient` 近实心深色保证可读。
  - `NotchHostedSurfaceView.bodyPanel`、`FloatingPanelView` 背景改用 `GlassPanelBackground`；两者新增 `@AppStorage("hudOpacity")` 传入。
  - 折叠态 `topCap` 保持纯黑不变（刘海融合无回归）。
  - **删除死代码** `SolidPanelBackground.swift`（玻璃化后完全无引用）。
- **B Lv1 减法**：
  - `OverlayListRow`：summary 次要行收成单行——隐藏 metricTitle 副标题、`showsBar` 在 summary 下恒 false（去进度条）；hero 仍保留进度条。
  - `OverlaySummaryView` 分隔线统一淡化到白 0.05。
  - 字号走新 `Theme.Typography`（title/value/caption/mono/hero）。
- **C token 统一**：
  - 新增 `Sources/token_hudCore/UsageSeverity.swift`（`.ok/.warn/.critical`，阈值 0.65/0.85，clamp 越界）+ `UsageSeverityTests`（4 用例）。
  - `Theme.severityColor(for:)` / `severityColor(forFraction:)` 复用 `Palette.status*` 作为绿/黄/红唯一来源；`NotchHostedSurfaceView.progressColor` 与 `UsageBar.barColor` 均改走它，删除两处内联 RGB。
  - **进度方向统一为"已用填充"**：`UsageBar` 由原来填充 `1-fraction`（剩余）改为填充 `fraction`（已用），与折叠条和百分比数字一致；glow 触发改用 `UsageSeverity == .critical`。
  - 新增 `Theme.Typography` ramp。
- **D 设置窗对齐**：删除 `SettingsWindow.swift` 侧栏 trailing 处与父 HStack 重复的第二条分隔线。
- **实现约束发现**：Xcode app target（project.yml）把 `token_hud` + `Sources/token_hudCore` 编译进**同一 module**，app 侧引用 core 类型**不需要 `import token_hudCore`**（加了反而 Xcode 构建失败）；SwiftPM 测试侧 core 仍是独立 module。

### 验证结果（2026-07-29）

- `swift test`：通过，170 个测试（+4 UsageSeverity）。
- 删除 `SolidPanelBackground.swift` 后 `xcodegen generate` + `xcodebuild ... build`：通过，无 error。

### 待手动验证

- 玻璃透出桌面观感：亮/暗桌面背景、亮/暗系统外观下是否清透且文字清晰；`hudOpacity` 滑块从 20%→100% 是否呈"浓烟玻璃→清透玻璃"渐变（该设置此前是死设置，本轮才真正生效）。
- Reduce Transparency 开启时是否回落到近实心深色、文字不发灰。
- 折叠态仍纯黑无缝融合刘海；展开/折叠切换无质感割裂或双浮窗回归。
- Lv1 布局：hero 保留进度条、次要行单行无进度条无副标题；1 条/多条/超多条下层级与滚动正常。
- severity 颜色在折叠条与展开 bar 上方向/配色一致（已用越多越偏红）。

## 当前重点：HUD BC-L 摘要布局精修（待确认）

### 问题

摘要布局已具备 hero、普通指标行、数字滚动与高占用辉光，但 hero 的数值和辅助信息层级仍偏松散，普通行数值列在不同内容下不够稳定，展开过程也缺少克制的分层入场节奏。

### 本轮目标

- 只精修默认的 `summary` 摘要布局，采用已确认的 BC-L 方向：动态岛式轮廓与轻动效为主，吸收仪表式数字对齐和紧凑信息表达。
- Hero 改为图标、名称、右侧数值三段式结构；只展示 `WidgetMetricComputer` 已提供的真实辅助信息。
- 普通行统一等宽数字、固定最小宽度与右对齐。
- hosted 展开时 hero 先进入，普通行按索引轻微错位淡入上移；实时数据刷新不重播整组动画。
- 尊重 macOS“减少动态效果”，关闭位移与错位延迟。
- 不修改列表、分页、收起态、provider 数据结构、拉取器或浮窗生命周期。

### 实施步骤

1. 实施前先把当前已完成但未提交的上一轮 HUD 改动提交为基线，避免 BC-L 与既有工作混入同一提交。
2. 在 `token_hudCore` 新增可测试的摘要入场进度计算，按展开进度、行索引和 Reduce Motion 计算稳定的行可见进度，并限制总延迟；运行 `xcodegen generate` 同步工程。
3. 给 `OverlayContentView` / `OverlaySummaryView` 增加默认完成态的 `entranceProgress`；hosted 传入 `hostState.expansionProgress`，detached 和 Settings 预览保持直接显示。
4. 调整 `OverlayHeroRow` 为三段式层级，在右侧数值下显示可选 `formattedDetail`；调整普通行数值列稳定宽度。
5. 普通行按纯函数结果应用低幅上移和透明度；Reduce Motion 下取消位移与错位。
6. `UsageBar` 增加短促宽度动画并保留低强度静态高占用辉光，不增加循环动画。

### 验证

- `swift test --filter SummaryEntranceAnimationTests` 验证行顺序、完成态、延迟上限和 Reduce Motion。
- 全量 `swift test`。
- `xcodebuild -project token_hud.xcodeproj -scheme token_hud -destination 'platform=macOS' build`。
- 手动验证 hosted 展开节奏、实时刷新不重播、无辅助信息不留空白、不同缩放比例、Reduce Motion 和高占用辉光。

### 风险

- 行延迟随 widget 数量累积会拖慢展开；计算必须设置阈值上限，保证整组约 250ms 内结束。
- 数值列过宽会压缩名称，过窄会截断长金额；使用缩放后的最小宽度并保留单行缩放。
- 当前工作区已有未提交 HUD 改动；实现必须基于现状增量修改，不得重置或覆盖。
- 视觉动画难以用稳定快照测试；只测试纯进度策略，视觉节奏依赖手动验收。

## 当前重点：下一轮精修（动效 + C 分页 + Settings 招光 + 实时长高/清理）（已实现，待手动体验验证）

### 背景

上一轮布局/材质/token 地基已稳。用户确认下一轮四块全做，按风险从低到高分四部分推进，每部分独立可验证、独立可回滚。

### 本轮目标（分四部分）

**Part 1 · 实时长高 + 死代码清理（最低风险，先做）**
- `NotchHostPanelManager` 观察 `widgetStore.widgets` 与 `overlayLayout` 变化：hosted 展开态下内容变化时重算自适应高度并 `reassertHostedFrame`，实现面板实时长高（不必等下次展开）。
- 用 `withObservationTracking` 重注册模式观察 `@Observable` 的 widgetStore；防抖，避免与 `isRestoringState`/`isResettingHostedFrame` 守卫冲突或重复 setFrame。
- 删除已无引用的 `CompactOverlayContent.swift`、`GroupedOverlayView.swift`；`xcodegen generate` 同步工程。

**Part 2 · 浮窗动效精修（精美感主体）**
- 数字滚动：hero/row 主数值 Text 加 `.contentTransition(.numericText())` + 按 `formattedValue` 的 `.animation`，数据更新时数字滚动过渡。
- 展开错位渐入：展开时行按 index 轻微 stagger（基于 `expansionProgress` 的阈值或延迟）淡入上移，不与外层 spring 抢节奏。
- collapsed 轻辉光：被追踪指标高占用（>0.85）时，collapsed 状态槽/进度条加极轻的语义色 glow。
- 图标小圆底 chip：list row 图标也套 provider 强调色圆底（hero 已有），统一精致度。
- 数值列右对齐 + 固定宽，`monospacedDigit` 保证多行数字/进度条右缘对齐。

**Part 3 · 补齐 C 分页布局**
- 新增 `OverlayPagedView`：一屏一个服务/指标（hero 尺寸），横向分页（`scrollTargetBehavior(.paging)`，macOS 14+）+ 圆点指示。
- `OverlayContentView` 的 `.paged` 分支接入；Settings 布局选择器放出"分页"。
- `adaptiveExpandedHeight` 为 paged 增加单页高度分支（固定较矮）。

**Part 4 · Settings 深度招光**
- 状态徽章统一：`StatusPill` / `StatusDot` / "已配置 N" 绿胶囊收敛为一套基于 `Theme.Palette.status*` 的组件。
- 卡片抬升体系：平台详情各 section 统一 `.glassCard` 层级与间距节奏（8pt 栅格）。
- 通用页原生 `Form(.grouped)` 违和：在磨砂底上确认可读性，必要时给 section 统一容器/透明背景，使其与自定义页风格一致（不重写为完全自定义，控制范围）。

### 实施顺序与验证

- 按 Part 1 → 2 → 3 → 4 顺序实现，每部分单独 `swift test` + `xcodebuild` + 手动验证后再进下一部分。
- 新增文件（`OverlayPagedView` 等）后 `xcodegen generate`。
- 几何/策略相关改动补或更新 Swift Testing。

### 验证

- 全量 `swift test` 无回退（含分页高度新用例）。
- app 构建通过。
- 手动：数字滚动/错位渐入/辉光观感；三种布局切换（摘要/列表/分页）正确；实时长高生效；Settings 状态徽章统一、通用页协调。

### 风险

- 数字滚动/动画在实时数据频繁更新时可能抖动或过度动效——需限制动画范围（只主数值）、必要时节流。
- 实时长高观察若触发过频会与浮窗生命周期守卫竞争；必须防抖并复用既有 reassert 守卫路径。
- macOS 分页 API（`scrollTargetBehavior`）行为与 iOS 有差异，需真机验证翻页与圆点同步。
- Part 4 通用页只做协调，不重写 Form；避免范围蔓延。
- 每部分独立提交式推进，任一部分有问题可单独回滚，不影响其余。

### 本轮实现结果（2026-07-08）

- **Part 1 · 实时长高 + 清理**：
  - `NotchHostPanelManager` 用 `withObservationTracking` 观察 `widgetStore.widgets.count`，hosted 态内容变化时 `refreshGeometry` + `reassertHostedFrame` 实时重算面板高度（守卫 `isRestoringState`/`isDragging`，复用 `isResettingHostedFrame` 防误切）。
  - 删除无引用的 `CompactOverlayContent.swift`、`GroupedOverlayView.swift`，`xcodegen` 已同步。
- **Part 2 · 动效精修**：
  - hero/row 主数值加 `.contentTransition(.numericText())` + `.animation(value: formattedValue)`，数据更新数字滚动。
  - 新增 `ServiceIconChip`：list row 图标也套 provider 强调色圆底（与 hero 一致）。
  - collapsed 进度条高占用（≥0.85）加语义色轻辉光。
  - （错位渐入本轮未做：避免破坏已稳定的展开动画，留待后续。）
- **Part 3 · C 分页布局**：
  - 新增 `OverlayPagedView`（`scrollTargetBehavior(.paging)` + `scrollPosition` + `PageDots` 圆点），接入 `OverlayContentView.paged`。
  - 新增 `NotchGeometryCalculator.pagedExpandedHeight()`（固定单页高度）；manager 分页时用它。
  - Settings 布局选择器放出"分页"。
- **Part 4 · Settings 招光**：
  - `ProviderCredentialStatus.color` / `ProviderDataStatus.color` 及平台页内所有内联 `.green/.orange/.red/.yellow/.blue` 状态色统一走 `Theme.Palette.status*` / `brandAccent`。
  - 卡片沿用上一轮 `.glassCard` 统一层级；通用页原生 `Form(.grouped)` 本轮按计划保持（不重写），仅确认在磨砂底可读。

### 验证结果（2026-07-08）

- `swift test`：通过，161 个测试通过（+1 `pagedHeightIsFixedAndAtLeastDefault`）。
- 每部分均 `swift test` + `xcodebuild ... build` 通过；Part 1 删文件后 `xcodegen generate`。

### 待手动验证

- 数字更新时主数值滚动过渡是否自然、不抖。
- 图标小圆底 chip 观感；collapsed 高占用轻辉光是否恰当（不过曝）。
- 三种布局切换：摘要/列表/分页均正确；分页左右翻页与圆点同步（macOS `scrollTargetBehavior` 真机验证）。
- 展开态下在 Settings 增删 widget，浮窗**实时长高/缩短**。
- 平台页状态色统一（configured/expired/error/需授权）观感一致。

## 当前重点：浮窗布局重构（B 摘要布局）+ 自适应高度 + Settings 磨砂恢复 + 去样式内容模型（已实现，待手动体验验证）

### 问题

用户体验后提出两类问题，并要求重新规划浮窗排布与对应 Settings 逻辑：

1. 设计风格不统一：
   - (a) Settings：应做成**半透明磨砂**质感（科技感），参考 Token Monitor。上一轮"设计 token 统一"把 Settings 也改成了实心深色，与此诉求冲突，需要修正。
   - (b) 浮窗：尽量与刘海融为一体（深色、无缝）。
2. 浮窗内容多时**显示不全**（当前 `expandedHeight = 110` 固定，body 装不下就溢出）。

### 已确认的设计决策（brainstorming 结论）

- **两套表面身份**：Settings = 半透明磨砂玻璃；HUD 浮窗 = 深色刘海融合。`Theme` 拆出 `glass`(Settings) 与 `notch`(HUD) 两个 surface family；brandAccent / status / 间距 / 圆角 / 字体仍共用。
- **三种浮窗布局做成 Settings 可切换模式**：`summary`(B) / `drawer`(A) / `paged`(C)，共用同一份有序内容列表。**本轮只实现 B**，A/C 下一轮。
- **内容模型去样式**：`WidgetConfig.style` 保留在存储里但渲染忽略（向后兼容，不清数据）；内容只按 (service, metric, quotaIndex) 管理。
- **hero = 内容列表第一条**：B 布局把第一条放大为顶部 hero，其余条目列表滚动。
- **溢出根治 = 自适应高度 + 超限滚动**：body 目标高度按内容测算，clamp 到 `[110, 屏幕可用高 × 0.6]`，超出内部滚动。
- collapsed 刘海双槽（leading 进度条 / trailing 文字）保持现状。

### 本轮目标

- 修正表面身份：
  - Settings 恢复半透明磨砂（撤回上一轮 `SettingsGlassBackground`、侧栏、`GlassPanel` 的实心深色改动）。
  - HUD 浮窗保持深色刘海融合（沿用 `SolidPanelBackground` / notch surface）。
- 浮窗布局：
  - 新增布局模式 `overlayLayout`（AppStorage，默认 `summary`）。
  - 实现 B 摘要布局：顶部 hero（第一条，大数字，贴合刘海）+ 下方其余条目滚动列表。
  - A/C 本轮不实现，代码留出模式分支占位（非 summary 时暂时回退到现有列表）。
- 自适应高度（解决溢出）：
  - `NotchGeometryCalculator.notchFrames` 增加 `expandedHeight` 参数（默认保留常量）。
  - `hostedSurfaceLayout` 的 body 高度改为从 `surfaceSize.height - menuBarHeight` 推导，不再依赖固定常量。
  - `NotchHostPanelManager` 按内容条目数与模式估算 `expandedHeight`，clamp 到 `[110, 屏幕可用高 × 0.6]`，在展开/内容变化/屏幕变化时重算并 setFrame。
- Settings 配合：
  - 小组件页移除"样式"选择；预设/已添加只按 (service, metric) 管理；新增"布局模式"选择器；第一条标注"主指标 (hero)"。
- 不破坏数据：不动 `state.json`、不清 `WidgetConfig` 存储、不改凭据/fetcher。

### 实施步骤

1. **Theme 拆双 surface family**
   - `Theme` 增加 `glass`（Settings：material + 细边 + 轻高光）与 `notch`（HUD：深色渐变实底）两组表面定义。
   - `SettingsGlassBackground`、Settings 侧栏、平台侧栏、`GlassPanel` 恢复/改用 `glass` 家族（半透明磨砂）。
   - 浮窗 `SolidPanelBackground`、`NotchHostedSurfaceView` 用 `notch` 家族。
   - brandAccent / status / spacing / radius / typography 保持共用。

2. **内容模型去样式**
   - 新增 `overlayLayout` AppStorage（`summary` / `drawer` / `paged`），默认 `summary`。
   - HUD 内容仍取 `store.widgets`（有序）；渲染忽略 `WidgetConfig.style`。
   - 保留存储字段，避免破坏已保存配置与解码。

3. **B 摘要布局视图**
   - 复用/扩展 `OverlayListView`：新增 hero 区（第一条放大：大号数值 + provider 强调色图标 + 进度条），其余条目走现有 row + 竖向滚动。
   - 抽 hero row 与普通 row 为可复用子视图，供后续 A/C 共用。
   - `NotchHostedSurfaceView.bodyPanel` 与 `FloatingPanelView` 按 `overlayLayout` 选择布局；非 `summary` 暂回退现有列表。

4. **自适应高度几何**
   - `NotchGeometryCalculator.notchFrames(screenFrame:geometry:expandedHeight:)` 加参数，默认 `expandedHeight`。
   - `hostedSurfaceLayout` body 高度改为 `(surfaceSize.height - menuBarHeight) * progress`。
   - `NotchHostPanelManager`：新增按内容估算高度的纯逻辑（hero ≈ 固定高 + 其余行 × 行高，clamp `[110, screen.visibleFrame.height × 0.6]`），在 `refreshGeometry` / 展开 / widget 变化时使用。
   - 观察 `widgetStore` 变化触发重算（Observation）。

5. **几何测试更新**
   - 更新 `NotchGeometryCalculatorTests` 中依赖固定 110 的断言；新增自适应高度用例（给定 expandedHeight 得到对应 frame / body 高度；clamp 边界）。

6. **Settings 小组件页改造**
   - 移除样式选择 UI 与相关绑定；预设/已添加只显示 (service, metric)。
   - 新增"布局模式"选择器（摘要/抽屉/分页；抽屉/分页标注"即将支持"或暂时可选但回退）。
   - "当前效果/已添加"第一条标注"主指标 (hero)"。
   - 恢复该页磨砂质感与统一 token。

7. **验证**
   - `swift test`（含更新后的几何测试）
   - `xcodegen generate`（新增文件）后 `xcodebuild ... build`
   - 手动：
     - Settings 三页恢复磨砂科技感、文字清晰。
     - 浮窗 B 布局：hero 贴合刘海、下方滚动、内容多时不再截断。
     - 自适应高度在 1 条 / 多条 / 超多条下的表现（clamp 生效、超限滚动）。
     - collapsed 与 expanded 切换仍与刘海融合、无双浮窗/漂移回归。

### 验证

- 更新并通过几何单测（自适应高度 + clamp 边界）。
- 全量 `swift test` 无回退。
- app 构建通过。
- 手动确认两套表面身份、B 布局溢出解决、刘海融合无回归。

### 风险

- `expandedHeight` 参数化会牵动 `NotchGeometryCalculator` 及其测试；必须同步更新断言，避免几何回归（该模块历史上多次回归）。
- 自适应高度改变展开 body 尺寸，需复核 snapZone、hit mask、hover region 是否仍正确；body 变高不应影响 collapsed 的刘海融合。
- 观察 widgetStore 触发重算要防抖/防重复 setFrame，避免与浮窗生命周期（上一轮 `isRestoringState` 守卫）冲突。
- Settings 恢复磨砂是对上一轮"实心深色统一"的部分回退；provider 强调色映射、brandAccent 收敛保留不动。
- A/C 布局本轮仅占位；Settings 若提供其选项，需明确回退行为，避免用户选了没效果。

### 本轮实现结果（2026-07-08）

- **Theme 拆双 surface family**：`Theme` 新增 `GlassWindowBackground` 与 `.glassCard()`（Settings 半透明磨砂），保留 `SurfaceLevel` + `.themedCard()`（HUD 深色）。
  - Settings 恢复磨砂：`SettingsGlassBackground` 回到 material + 高光渐变；侧栏回 `.regularMaterial`；平台侧栏回 `.ultraThinMaterial`；平台 `GlassPanel` 与 toast 改 `.glassCard()`。
  - HUD 保持 `SolidPanelBackground`（深色刘海融合）不变。
- **内容模型去样式 + 布局模式**：
  - 新增 `OverlayLayout`（`summary`/`drawer`/`paged`）与 `overlayLayout` AppStorage。
  - 重写 `OverlayListView.swift`：`OverlayContentView` 分发；`OverlaySummaryView`（B：hero + 滚动列表）；`OverlayListView`（列表）；`OverlayHeroRow` / `OverlayListRow` / `UsageBar` 复用组件。
  - `NotchHostedSurfaceView` 与 `FloatingPanelView` 改用 `OverlayContentView`，内容用固定 `widgetSizeScale`（溢出滚动而非缩字）。
  - `WidgetConfig.style` 保留存储但渲染忽略；未清数据。
- **自适应高度（溢出根治）**：
  - `NotchGeometryCalculator.notchFrames` / `hostedSurfaceLayout` 增加可选 `expandedHeight` 参数；body 高度改由 `surfaceSize.height - menuBarHeight` 推导。
  - 新增 `adaptiveExpandedHeight(itemCount:isSummary:availableHeight:)`，clamp 到 `[110, 可用高 × 0.6]`。
  - `NotchHostPanelManager.computeFrames` 按 widget 数 + 布局算高度；`animateToExpanded` 展开前重算几何；`windowDidResize` 增加 `isResettingHostedFrame` 守卫（自适应 reassert 会改尺寸，防止误切 detached）。
  - 视图 `surfaceLayout` 从 `hostState.frames` 推导同一高度传入。
- **Settings 配合**：
  - 浮动面板设置：`overlayMode`(紧凑/分组) 选择器替换为 `overlayLayout`（摘要/列表）+ 说明；`paged` 本轮不放出。
  - 小组件页"当前效果"预览改为直接渲染真实 `OverlayContentView`（深色面板），summary 模式标注"主指标 (hero)"；移除旧的按服务分组 chip 预览与其死代码（`WidgetPreviewGroup(View)` / `WidgetPreviewItem` / `groupedWidgets` / `removeWidget`）。
- **几何测试**：新增 `customExpandedHeightDrivesFrameAndBody` / `adaptiveHeightGrowsWithItemsAndClamps` / `adaptiveHeightNeverBelowDefault`；既有固定高度断言用默认参数仍通过。
- **未删除**：`CompactOverlayContent` / `GroupedOverlayView` 现已完全无引用（死代码），本轮未删以控制范围。
- **已知限制**：A(drawer) 已可用（等高列表），C(paged) 未实现；widget 数变化仅在下次展开/屏幕变化时重算面板高度（展开中新增暂靠滚动，不实时长高）。

### 验证结果（2026-07-08）

- `swift test`：通过，160 个测试通过（含 3 个新增自适应高度用例）。
- `xcodebuild ... build`：通过，无 error（本轮无新增源文件，未跑 xcodegen）。

### 待手动验证

- Settings 三页恢复半透明磨砂科技感、文字清晰（亮/暗外观 + Reduce Transparency）。
- HUD 浮窗 B 布局：hero 贴合刘海、下方滚动；内容多时不再截断（自适应长高到上限再滚动）。
- Settings 浮动面板切"摘要/列表"，浮窗实时反映；小组件页预览与真实 HUD 一致、hero 标注正确。
- collapsed ↔ expanded 切换与刘海融合无回归、无双浮窗（上一轮 `isRestoringState` + 本轮 `isResettingHostedFrame` 守卫）。

## 当前重点：设计 token + 材质/强调色统一（已实现，待手动体验验证）

### 问题

目前整个 app 的视觉语言不统一，是后续所有 UI 抛光的最大阻碍：

- **三套互不相干的表面质感**：
  - Settings 外壳 `.regularMaterial` 磨砂 + 白色渐变叠层（`SettingsWindow.swift` `SettingsGlassBackground`）。
  - 平台页侧栏 `.ultraThinMaterial` + `白 0.035` 叠层（`PlatformListView.swift`）。
  - 平台详情卡片 `GlassPanel`：`.thinMaterial` + `白 0.06` + 描边 + 阴影（`PlatformListView.swift:1148`）。
  - 浮窗：上一轮改的 `SolidPanelBackground` 实心深色渐变。
- **两套强调色并存**：Settings 主侧栏和多处用系统蓝 `Color.accentColor`（共 16 处），平台侧栏改用了 provider 品牌色（`serviceAccentSwiftUIColor`）。
- **魔法数字散落**：圆角 5/6/8/10/14/16 混用；透明度 0.035/0.06/0.08/0.12/0.13/0.16 到处硬编码；间距 4/8/9/10/12/14 无栅格。
- **字体无 ramp**：大量 `.font(.system(size:))` 直接写，数值/标签层级不统一。

结论：单点抛光无法解决"拼凑感"，必须先建立单一来源的设计 token，并统一材质和强调色。

### 本轮目标

- 建立一套集中的设计 token（app 侧 SwiftUI 层，命名如 `Theme`）：
  - **颜色层级**：`surface.base / raised / overlay`、`border.subtle / strong`、`text.primary / secondary / tertiary`、统一 `brandAccent`、status 语义色（`ok / warn / error / idle`）。
  - **圆角梯子**：如 `radius.sm=8 / md=12 / lg=16`。
  - **间距梯子**：4/8/12/16/24（8pt 栅格为主）。
  - **材质身份**：全 app 统一一种表面身份。既然浮窗（产品主角）已是实心深色，Settings 也往"更实、更暗"靠，收敛磨砂叠层的随意用法。
  - **字体 ramp**：`title / headline / body / caption` + 数值统一 `monospacedDigit`。
- 用 token 收敛现有三处表面：
  - `SettingsGlassBackground`、平台侧栏背景、`GlassPanel` 改为引用统一 token（surface + border + radius + shadow），保留各自布局，只换底层样式来源。
  - `SolidPanelBackground`（浮窗）复用同一套 surface/边框 token，保证浮窗和 Settings 卡片是"同一种材质的不同层级"。
- 强调色收敛：
  - Settings 主侧栏（小组件/平台/通用）选中态、通用交互强调统一用 `Theme.brandAccent`，替换系统 `Color.accentColor`。
  - provider 品牌色**只保留做"身份标识"**（图标 tint、平台侧栏小圆点/强调条），不再和主 UI 强调色混用。
- 不改功能、不改数据模型、不改布局结构：本轮只替换样式来源，不动 fetcher、state、几何、浮窗生命周期。

### 方案取舍

- **推荐：新增 `Theme` 常量集合 + 少量 ViewModifier/背景 helper，逐处替换样式来源**
  - 优点：地基清晰、风险可控、后续抛光都能复用。
  - 缺点：本轮改动点分散在多个文件（但都是样式替换，无逻辑变化）。
- 更激进：引入完整 design system（Environment 注入主题、支持多主题切换）——超出当前需要，暂不做。
- 保守：只统一颜色不碰材质——无法解决三套质感割裂，达不到"精美"目标。

### 实施步骤

1. **定义 token**
   - 新增 `token_hud/Design/Theme.swift`：集中 `Theme.Color`（surface/border/text/brandAccent/status）、`Theme.Radius`、`Theme.Spacing`、`Theme.Typography`。
   - 颜色用固定 RGB / `Color` 常量，先按当前浮窗深色基调取值，保证 Settings 与浮窗同源。
2. **统一表面 helper**
   - 抽 `Theme` 提供的卡片背景 modifier（如 `.themedSurface(level:)`），统一 fill + border + radius + shadow。
   - `SolidPanelBackground`、`GlassPanel`、`SettingsGlassBackground`、平台侧栏背景改为引用同一 helper/token。
3. **强调色替换**
   - 全局把 Settings 里非 provider 语义的 `Color.accentColor`（16 处）替换为 `Theme.Color.brandAccent`。
   - 保留 `serviceAccentSwiftUIColor` 仅用于 provider 身份标识处。
4. **状态色与 pill 收敛**
   - `StatusPill`、"已配置 N" 绿色胶囊、状态点统一走 `Theme.Color.status`。
5. **字体 ramp 落地（最小范围）**
   - 先在 Settings 标题/说明/数值和浮窗列表主数值接入 `Theme.Typography`，不强制一次性替换所有 `.font`。
6. **验证**
   - `swift test`
   - `xcodegen generate`（如新增文件）后 `xcodebuild ... build`
   - 手动：三页 + 浮窗展开/collapsed 视觉是否统一（材质、强调色、圆角、间距），有无对比度/可读性回退。

### 验证

- 全量 `swift test` 保证无逻辑回退（本轮应为纯样式改动）。
- app target 构建通过。
- 手动对照：Settings 三页与浮窗是否读起来像"同一个 app"——统一材质身份、单一强调色、一致圆角与间距。

### 风险

- 统一材质会改变 Settings 现有观感（从磨砂转向更实的深色），需要手动确认亮/暗系统外观和 Reduce Transparency 下的可读性。
- token 取值一次定死可能不完美；本轮以"建立单一来源 + 收敛现有魔法数字"为目标，具体色值后续可微调。
- 改动点分散（16 处 accentColor + 多处 material），需逐处替换后统一验证，避免遗漏造成新的不一致。
- 本轮不动 provider 强调色映射、浮窗几何与生命周期、数据模型。

### 本轮实现结果（2026-07-08）

- 新增 `token_hud/Design/Theme.swift`：集中 `Palette`（surface base/raised/overlay、border subtle/strong、text primary/secondary/tertiary、`brandAccent`、status ok/warn/error/idle）、`Radius`（sm8/md12/lg16）、`Spacing`（4/8/12/16/24）、`SurfaceLevel` 渐变，以及 `.themedCard(level:cornerRadius:padding:)` 修饰器。
  - `brandAccent` 选用 periwinkle-indigo `(0.50, 0.52, 0.98)`，刻意区别于系统蓝、绿色 status、provider 身份色。
- 表面统一到 token：
  - 浮窗 `SolidPanelBackground` 改用 `Theme.SurfaceLevel.raised.gradient` + `borderSubtle`。
  - 平台详情 `GlassPanel` 从 `.thinMaterial` 磨砂改为 `.themedCard`（实心深色渐变）。
  - Settings 外壳 `SettingsGlassBackground` 从 `.regularMaterial` + 白渐变改为 `SurfaceLevel.base.gradient` 实心深底。
  - Settings 侧栏与平台侧栏去掉 `.regularMaterial` / `.ultraThinMaterial`，改为 base 之上的极轻白色 tint，靠 `borderSubtle` 分隔。
- 强调色收敛：
  - Settings 主侧栏选中态、KeyRecorder 录制态、平台配额进度条正常态、小组件预设 chip 强调统一 `brandAccent`。
  - provider 身份色（`serviceAccentSwiftUIColor`）保留于平台侧栏图标/强调条、小组件预设 chip 图标。
  - `PlatformRowView.swift` 为死代码（无引用），本轮未改其残留 `accentColor`。
- status 色收敛：平台"已配置 N"胶囊、配额告警走 `Theme.Palette.status*`。
- 细节：平台页 reset toast 改 `.themedCard(level:.overlay)` 并加入淡入淡出 + 上移过渡（`showResetMessage` 包 `withAnimation`）。

### 验证结果（2026-07-08）

- `swift test`：通过，157 个测试通过。
- `xcodegen generate` 后 `xcodebuild ... build`：通过，无 error。

### 待手动验证

- Settings 三页与浮窗展开态并排看是否像"同一个 app"：统一深色实心材质、单一 periwinkle 强调色、一致圆角/间距。
- 亮/暗系统外观、Reduce Transparency 下 Settings 文字对比度是否仍清晰（材质从磨砂转实心的主要风险点）。
- 通用页 `Form(.grouped)` 在新深色底上的观感（已知后续 tier 项：原生 Form 与自定义页风格仍有差异，本轮未改）。
- provider 身份色是否仍能一眼区分平台，且不与 brandAccent 混淆。

## 当前重点：展开面板大数字列表 + 实心深色卡片 + 启动双浮窗修复（已实现，待手动体验验证）

### 问题

用户对照参考项目 Token Monitor 后反馈三个问题：

1. **首次点开时两个浮窗重叠**。
2. **整体透明度/质感与参考差距大**——参考是接近不透明的深色实体卡片，token_hud 现在用 `.regularMaterial` 磨砂 + 半透明黑，在亮背景下发灰发糊。
3. **浮窗里字体太小看不清**。

现状排查（已读 `NotchHostPanelManager.swift`、`NotchHostedSurfaceView.swift`、`NotchHostRootView.swift`、`FloatingPanelView.swift`、`CompactOverlayContent.swift`、`GroupedOverlayView.swift`、`NotchGeometryCalculator.swift`、`AppDelegate.swift`）：

- 问题 3 根因有两层：
  - **布局层**：`CompactOverlayContent` 把所有 widget 横向塞进一个 `ScrollView`，每个都是 8~12pt 小 chip，widget 一多字体必然小。
  - **回归层**：上一轮（"数值等宽字体与 Provider 强调色映射"）把各 widget 主数值从 `design: .rounded` 改成 `design: .monospaced`。等宽字形每字符更宽，widget 固定宽度 + `minimumScaleFactor(0.6~0.7)` 导致数字被自动缩小，反而更小更细。本轮需要修正这个副作用。
- 问题 2 根因：`NotchHostedSurfaceView.bodyPanel` 和 `FloatingPanelView` 都是 `.regularMaterial` + `Color.black.opacity(0.58~0.70)` 叠加，是磨砂玻璃质感；参考项目是接近不透明的深灰渐变卡片 + 细亮边 + 柔和外阴影，质感更"实"。
- 问题 1 根因已由真机日志确认（**不是 SkyLight 副本**，是启动恢复的时序竞争）：
  - `savedMode: hosted` → 走 `.hostedCollapsed` 分支。
  - 该分支 `setFrameWithDiagnostics` 调 `win.setFrame` 把 overlay 从默认 (200,200,300,60) 拉到展开尺寸 (455,814,560,142)，这个 resize **同步触发 `windowDidResize`**。
  - `windowDidResize` 里"hosted 不该 resize → `transitionTo(.detached)`"于是中途把恢复流程切成 detached（`switch detached` 日志），随后 `.hostedCollapsed` 分支继续 `prepareOverlayForDisplay` 又把 overlay order front。
  - 结果 `restore state complete`：`mode: detached` 且 `detachedVisible: true` / `overlayVisible: true` 两个窗口都可见。
  - `windowDidMove` 已有 `isResettingHostedFrame` 守卫，但 `windowDidResize` 没有，且恢复流程整体无守卫。
  - **已实现修复**：新增 `isRestoringState` 守卫，`restoreState()` 全程置位，`windowDidResize` / `windowDidMove` 在恢复期间直接早返回，杜绝恢复中途误切 detached。

用户已确认方向：
- 布局：展开面板重做成**大数字竖向列表**（参考项目形态）。
- 质感：改成**实心深色渐变卡片**（去磨砂模糊）。

### 本轮目标

- 展开面板（hosted expanded body 与 detached 浮窗共用内容）从横向 chip 改为**竖向大数字列表**：
  - 每行一个服务：左侧 provider 强调色图标 + 名称，右侧大号数值，下方/右侧配进度条。
  - 数值字号显著加大、可读性优先；服务多时用竖向滚动，不再把字压小。
  - 复用现有 provider 强调色映射与 `WidgetValueComputer`，不改数据来源。
- 卡片质感改为**实心深色渐变卡片**：
  - hosted expanded body 与 detached `FloatingPanelView` 统一改成深灰竖向渐变实底（接近不透明）+ 0.8pt 细亮边 + 柔和外阴影。
  - 去掉/弱化 `.regularMaterial` 磨砂，避免亮背景发灰。
  - collapsed top cap 继续保持接近刘海黑度以维持融合，不做过度玻璃化。
- 修正上一轮 monospaced 主数值缩小的副作用：
  - 保留 `.monospacedDigit()`（数字等宽对齐仍要），但主数值字形不再统一用 `design: .monospaced`；根据新大数字列表的实际宽度决定字体，确保不被 `minimumScaleFactor` 压缩。
- 修复启动双浮窗：
  - 先抓 `[NotchDiagnostics]` 日志确认是"两个真窗口都可见"还是"SkyLight 委托副本"。
  - 根据根因收敛显示路径：启动/切换时保证同一时刻只有一个窗口可见；如为 SkyLight 委托副本，调整委托后原窗口的可见性/清理顺序。
- 不改数据模型：不动 `state.json` schema、fetcher、凭据逻辑、刘海吸附/脱离几何策略。

### 实施步骤

1. **抓取问题 1 根因日志（阻塞后续修复）**
   - 请用户重启 app，复现首次双浮窗重叠，抓取 Xcode/Console 里 `[NotchDiagnostics] restore state complete` 及前后 `surface prepared` / `surface strategy configured` 段落。
   - 依据 `detachedVisible` / `overlayVisible` / `overlayDelegatedToSkyLight` 判断根因分支，再决定第 5 步的具体修法。

2. **大数字列表内容视图**
   - 在 `GroupedOverlayView` 基础上（或新建 `OverlayListView`）实现竖向列表行：
     - 左：`serviceAccentSwiftUIColor(for:)` 图标 + provider 名。
     - 右：大号主数值（复用 `WidgetRenderer` 的 `formattedValue` 逻辑或抽取共享格式化），下方细进度条。
   - 每行一个主指标；同服务多 widget 时保留次要行或折叠，避免重新变回一排小 chip。
   - 字号以展开 body 高度（`expandedHeight = 110`）为基准放大，主数值至少接近参考观感。

3. **接入展开面板与浮窗**
   - hosted expanded：`NotchHostedSurfaceView.bodyPanel` 的内容改用新列表视图。
   - detached：`FloatingPanelView` 内容改用同一列表视图，保持两态一致。
   - collapsed 态与 status slot 不变。

4. **实心深色渐变卡片**
   - 抽一个共享卡片背景（如 `SolidPanelBackground`）：深灰竖向 `LinearGradient` 实底 + `Color.white.opacity(~0.12)` 细边 + 柔和 `shadow`。
   - 替换 `NotchHostedSurfaceView.bodyPanel` 和 `FloatingPanelView` 里的 `.regularMaterial` + 半透明黑叠加。
   - 检查亮/暗桌面背景下对比度，确保不发灰、文字清晰。

5. **修复启动双浮窗（依赖第 1 步结论）**
   - 根据日志：
     - 若为两个真窗口都可见：收紧 `restoreState()` / `prepareOverlayForDisplay` 的 orderOut 顺序，保证互斥。
     - 若为 SkyLight 委托副本：调整委托时机与原窗口可见性处理。
   - 增补可测的纯逻辑（如"给定 restoreMode 只应有一个窗口可见"）到 core，如果能抽出判断。

6. **收尾字体修正**
   - 复查 `TextWidget`/`AggregateWidget`/`BarWidget`/`RingWidget`/`MultiWidget`/`ModelBreakdownWidget`：如果这些仍用于新列表，按实际宽度决定是否保留 `design: .monospaced`；被大数字列表取代的路径相应调整。

### 验证

- 自动：
  - `swift test`
  - `xcodebuild -project token_hud.xcodeproj -scheme token_hud -destination 'platform=macOS' build`（新增文件先 `xcodegen generate`）。
- 手动：
  - 启动 app，确认首次不再出现两个浮窗重叠（对照日志 `overlayVisible` / `detachedVisible` 只有一个 true）。
  - 展开刘海面板和 detached 浮窗，确认大数字清晰可读、卡片质感实、亮背景不发灰。
  - 多服务时列表竖向滚动，字体不被压小。

### 风险

- 动到 `NotchHostPanelManager` 浮窗生命周期历史上多次回归，第 5 步必须以日志根因为准、小步改，不盲改。
- 去磨砂改实心渐变后，collapsed 与刘海融合的黑度要单独校准，避免展开态和收起态质感割裂。
- 大数字列表会改变展开 body 的理想高度，`adaptiveScale` / `expandedHeight` 可能需要同步调整，注意别撑破刘海几何。
- 本轮会修正上一轮 monospaced 主数值改动；provider 强调色映射保留不动。

### 本轮实现结果（2026-07-08）

- **问题 1（启动双浮窗）已修**：
  - `NotchHostPanelManager` 新增 `isRestoringState` 守卫，`restoreState()` 全程置位（`defer` 复位）。
  - `windowDidResize` / `windowDidMove` 在恢复期间直接早返回，杜绝恢复中 `setFrame` 的 resize 同步触发 `transitionTo(.detached)`。
- **问题 3（字体太小）**：
  - 展开面板内容从横向 chip 改为大数字竖向列表 `OverlayListView`（新文件）：每行一个 widget，左侧 provider 强调色图标 + 服务名/指标名，右侧 20pt 主数值，下方细用量条；行数多时竖向滚动，不再压小字体。
  - 抽取 `WidgetMetricComputer`（新文件），把原 `WidgetRenderer` 里 ~250 行的 fraction/formattedValue/formattedDetail/icon/metricTitle 计算集中为单一来源；`WidgetRenderer` 改为委托，行为不变。
  - 回退上一轮把 chip 主数值改成 `design: .monospaced` 的副作用：7 个 widget 主数值改回 `.rounded`，保留 `.monospacedDigit()` 做数字对齐。
- **问题 2（质感）**：
  - 新增 `SolidPanelBackground`（新文件）：深灰竖向渐变实底（接近不透明）+ 0.8pt 细亮边 + 柔和外阴影，去掉 `.regularMaterial` 磨砂。
  - `NotchHostedSurfaceView.bodyPanel` 与 `FloatingPanelView` 背景统一改用 `SolidPanelBackground`。
  - collapsed top cap 保持原深黑度不变（仅展开 body 与 detached 玻璃化改实心）。
- **未删除**已无引用的 `CompactOverlayContent` / `GroupedOverlayView`（本轮不顺手清理，保持范围集中）。
- **未改动** `expandedHeight = 110` 几何常量：为避免破坏刘海几何测试，列表在现有高度内滚动；如需更多行同屏可见，后续单独评估加高 body。

### 验证结果（2026-07-08）

- `swift test`：通过，157 个测试通过。
- `xcodegen generate` 后 `xcodebuild -project token_hud.xcodeproj -scheme token_hud -destination 'platform=macOS' build`：通过。

### 待手动验证

- 启动 app：确认首次不再出现两个浮窗重叠（对照日志 `restore state complete` 应只有一个窗口 `Visible: true`）。
- 展开刘海面板 / detached 浮窗：确认大数字清晰、卡片是实心深色渐变、亮桌面背景下不发灰。
- widget 较多时：确认列表竖向滚动、字体不被压小。
- 切换 collapsed / expanded：确认顶部与刘海仍融合、无灰边或质感割裂。

## 当前重点：数值等宽字体与 Provider 强调色映射（已实现，待手动体验验证）

### 问题

参考竞品 Token Monitor（Electron，一个多工具 AI 用量监控组件，见 https://github.com/Javis603/token-monitor）截图后，发现其 UI 质感两个特点在 `token_hud` 上还没有对应实现：

- 核心数字（token 数、百分比、剩余时间）统一用等宽字体，视觉上有明显的"数据/终端感"，和标签文字形成字体层次。
- 每个 provider 有稳定的品牌强调色，贯穿进度条、图标 tint，用户靠颜色就能扫描区分平台，不需要逐行读文字。

现状排查：

- `token_hud/Widgets/*.swift` 里，`TextWidget`、`BarWidget`、`AggregateWidget` 已经用了 `.monospacedDigit()`，但 `RingWidget`、`ModelBreakdownWidget`、`MultiWidget`、`StatusWidget`、`CountdownWidget` 没有统一加上；且现有字体全部是 `design: .rounded`，不是真正等宽字形（`SF Mono`/`monospaced`），"数据感"比参考产品弱。
- 颜色方面完全没有 provider 级别的品牌色映射：
  - `RingWidget.ringColor` / `BarWidget.barColor` 目前只按"剩余量/使用率"分三档（绿/黄/红），是纯状态色，和 provider 身份无关。
  - `PlatformListView.swift`、`PlatformRowView.swift`、`WidgetListEditor.swift` 里的选中态、状态点、进度 `tint` 全部用系统 `Color.accentColor` 或红/黄阈值色，没有 per-service 颜色。
  - 目前唯一的 service 到展示名映射是 `WidgetListEditor.swift:83 serviceDisplayName(_:)`，覆盖 `claude / openai / codex / gemini / deepseek / anthropic / minimax / mimo`，没有配套颜色表。

### 本轮目标

- 统一小组件数值的等宽处理：
  - 所有渲染数值（不含单位文字、标签文字）都加 `.monospacedDigit()`。
  - 每个 widget 的"主数值"（大字号那一行，如 `TextWidget`/`AggregateWidget` primary value、`RingWidget` 中心值、`BarWidget` 主标签、`ModelBreakdownWidget` 数值列）额外使用 `design: .monospaced`，获得更强"数据感"；标签、单位、次要说明保持现状字体。
- 新增 provider 强调色映射，覆盖当前 8 个 service（claude/openai/codex/gemini/deepseek/anthropic/minimax/mimo）+ 未知 service 的兜底色：
  - 映射放在 `Sources/token_hudCore`（跨平台、可测试），用 RGB 分量表示颜色，不直接依赖 SwiftUI `Color`。
  - App 侧提供 `Color` 转换 helper，供 widget 和 Settings 复用。
  - 应用范围：widget 图标/ring track tint、`PlatformListView`/`PlatformRowView` 的平台图标、选中态强调条、状态点。
  - **不替换**现有红/黄/绿"剩余量预警色"：`ring`/`bar` 的进度值颜色继续用状态色（这是之前几轮已验证的用量语义），品牌色只用于"识别用途"（图标 tint、侧栏强调条、分组标题色块），两者叠加而不是互相覆盖。
- 保持行为不变：不改 `state.json` schema、不改数据拉取逻辑、不改现有 widget 布局/尺寸策略。

### 实施步骤

1. **核心层新增颜色映射**
   - 在 `Sources/token_hudCore` 新增文件（如 `ServiceAccentColor.swift`），定义 `struct ServiceAccentColor { let red, green, blue: Double }` 和 `func serviceAccentColor(for service: String) -> ServiceAccentColor`，覆盖 8 个已知 service，未知 service 返回中性灰兜底色。
   - 为映射增加 Swift Testing 覆盖：已知 service 返回预期颜色、未知 service 返回兜底色、大小写不敏感（如果现有 service id 有大小写不一致场景需要确认）。

2. **App 侧颜色转换 helper**
   - 在 app target 增加 `Color(_ accent: ServiceAccentColor)` 或类似 extension，转换成 SwiftUI `Color`，放在合适的共享位置（如 `Widgets/WidgetRenderer.swift` 附近或新建 `Widgets/ServiceColor+SwiftUI.swift`）。

3. **应用到 widget 图标/track**
   - `RingWidget`：track 描边或 icon 部分使用 provider 强调色，进度值颜色保持现有状态色不变。
   - `BarWidget`/其他 widget 涉及 provider 图标的位置，统一用强调色 tint。

4. **应用到 Settings 平台列表**
   - `PlatformListView.swift` / `PlatformRowView.swift` 的平台图标、侧栏选中强调条、状态点颜色改用 provider 强调色，替代目前统一的 `Color.accentColor`。
   - 不改变现有红/黄状态阈值色的语义（配额告警仍用状态色）。

5. **统一数值等宽字体**
   - 逐个检查 `RingWidget`、`ModelBreakdownWidget`、`MultiWidget`、`StatusWidget`、`CountdownWidget`，给数值 Text 补上 `.monospacedDigit()`。
   - 每个 widget 的主数值字体从 `design: .rounded` 改为 `design: .monospaced`（如果视觉上过重，可保留字重不变，只切字体 design）。
   - 手动检查改字体后是否有截断/宽度变化导致的布局挤压，必要时微调 `frame`/`lineLimit`。

6. **验证**
   - 自动：
     - `swift test --filter Widget`
     - `swift test`（新增 `ServiceAccentColor` 测试一并跑过）
     - `xcodebuild -project token_hud.xcodeproj -scheme token_hud -destination 'platform=macOS' build`
   - 手动：
     - 打开刘海 hosted 展开态和 detached 浮窗，检查各 widget 样式下数字字体变化是否协调、是否有截断或挤压。
     - 添加多个不同 provider 的小组件，确认强调色能一眼区分且和现有红/黄/绿用量警示色不冲突、不混淆。
     - 打开 Settings → 平台页，切换不同 provider，确认图标/状态点颜色符合预期且原有配额告警色不受影响。

### 验证

- 新增 Swift Testing 覆盖 `ServiceAccentColor` 的已知/未知 service 分支。
- 全量 `swift test` 确保不影响现有 widget 格式化和平台解析测试。
- Xcode app 构建通过。
- 手动检查真实 HUD 和 Settings 视觉效果，因为字体/颜色观感不是纯测试能完全覆盖的。

### 风险

- 品牌色和状态色（红/黄/绿）如果视觉上离得太近，可能造成"识别色"和"警示色"混淆；本轮需要在应用时刻意让两者用在不同的视觉部位（如图标 tint vs 进度条本体），而不是同一元素叠加两种语义色。
- 主数值切换为 `design: .monospaced` 后字宽可能变化，尤其是 compact 尺寸的 widget，需要手动检查是否会在极小 scale 下截断或溢出。
- `serviceDisplayName` 目前是 `WidgetListEditor.swift` 内的 `private` 函数，`PlatformListView`/`PlatformRowView` 可能各自有独立的展示名逻辑；新增颜色映射时如果发现重复定义，只做最小整理（复用同一份 core 映射），不顺手做大范围去重重构。

### 本轮实现结果（2026-07-08）

- 新增 `Sources/token_hudCore/ServiceAccentColor.swift`：
  - `ServiceAccentColor` 纯 RGB 结构体，`serviceAccentColor(for:)` 覆盖 8 个已知 service（大小写不敏感），未知 service 返回中性灰兜底色。
  - 8 个已知颜色两两不同，且都与兜底灰色区分开（`Tests/token_hudCoreTests/ServiceAccentColorTests.swift` 覆盖）。
- 新增 `token_hud/Widgets/ServiceColor+SwiftUI.swift`：`Color(_ accent: ServiceAccentColor)` 转换 + `serviceAccentSwiftUIColor(for:)` app 侧入口。
- Widget 应用强调色（仅用于识别，不替换用量状态色）：
  - `RingWidget`/`CountdownWidget`：track 描边从固定白色半透明改为 `service` 强调色（未传 `service` 时保留原白色描边），进度弧颜色不变。
  - `BarWidget`：底部轨道同样改为 `service` 强调色，进度条本身颜色不变。
  - `AggregateWidget`：图标 tint 改为 `service` 强调色。
  - `MultiWidget`：子行图标 tint 改为 `config.service` 强调色。
  - `WidgetRenderer` 在构造 `RingWidget`/`BarWidget`/`AggregateWidget`/`CountdownWidget` 时传入 `config.service`。
- Settings 平台侧栏应用强调色：
  - `PlatformListView.swift` 的 `PlatformSidebarRow` 左侧强调条、平台图标改用 `serviceAccentSwiftUIColor(for: provider.id)`，选中态背景/描边透明度沿用原有数值。
  - `StatusDot`/`StatusPill`（配额/授权状态）未改动，继续使用状态色语义。
  - 确认 `PlatformRowView.swift` 当前未被任何视图引用（死代码），本轮未改动。
- 统一数值等宽处理：
  - 给 `RingWidget`、`CountdownWidget`、`StatusWidget`（次要 label）、`MultiWidget`、`ModelBreakdownWidget`（tokens + cost 两列）补上 `.monospacedDigit()`。
  - 主数值字体 `design` 从 `.rounded` 改为 `.monospaced`：`TextWidget.text`、`AggregateWidget.value`、`RingWidget` 中心 label、`BarWidget` 主 label、`CountdownWidget` label、`MultiWidget` 子行 value、`ModelBreakdownWidget` token 数列；标签/次要文字（单位、说明、cost 列）保持原字体。
- 新增文件被识别需要重新生成工程：运行 `xcodegen generate` 后 `token_hud.xcodeproj` 才能编译通过（新增 Swift 文件不会被旧 `.xcodeproj` 自动感知，这是本仓库已有约定）。

### 验证结果

- `swift test`：通过，157 个测试通过（含新增 `Service accent colors` 4 个测试）。
- `xcodebuild -project token_hud.xcodeproj -scheme token_hud -destination 'platform=macOS' build`：通过（先执行 `xcodegen generate` 后）。

### 待手动验证

- 打开刘海 hosted 展开态和 detached 浮窗，检查各 widget 数字字体是否协调、有无截断或挤压（尤其是极小 compact scale）。
- 添加多个不同 provider 的小组件，确认强调色能一眼区分，且和现有红/黄/绿用量警示色不会混淆（两者应出现在不同视觉部位：图标/轨道 vs 进度值本身）。
- 打开 Settings → 平台页，切换 Claude/OpenAI/Codex/Gemini/DeepSeek/Anthropic/MiniMax/MiMo，确认侧栏图标和强调条颜色符合预期，原有配额告警色（`StatusDot`/`StatusPill`）未受影响。

## 当前重点：Xcode 运行时 LLDB attach failed 修复（待确认）

### 问题

用户在 Xcode 运行 app 时看到：

- `Could not attach to pid`
- `attach failed (attached to process, but could not pause execution; attach failed)`

本轮排查结论：

- 直接运行 Debug 产物时，app 可以常驻运行，没有立即崩溃。
- 当前 Xcode Debug 产物包含 `token_hud.debug.dylib`，构建设置里 `ENABLE_DEBUG_DYLIB = YES`。
- 该产物带有 `com.apple.security.get-task-allow = true`，不是缺少调试授权。
- 命令行 LLDB 附加到 `ENABLE_DEBUG_DYLIB=YES` 的进程时复现同样错误。
- 用同一份代码临时构建 `ENABLE_DEBUG_DYLIB=NO` 后，LLDB 可以正常 attach/detach。

因此根因锁定为当前 Xcode/LLDB 与 Debug Dylib 模式组合下无法暂停该 macOS app 进程，而不是 app 业务代码崩溃。

### 本轮目标

- 让 Xcode 运行 `token_hud` 时能正常启动并附加调试器。
- 保持 Debug 可调试能力和现有 app 行为不变。
- 不改 UI、状态模型、权限逻辑和 runtime 行为。

### 实施步骤

1. 在 `project.yml` 的 target build settings 中显式设置 `ENABLE_DEBUG_DYLIB: "NO"`。
2. 同步更新 `token_hud.xcodeproj/project.pbxproj` 中 Debug/Release 对应 build settings，避免 Xcode 当前项目继续使用旧值。
3. 重新构建验证：
   - `xcodebuild -project token_hud.xcodeproj -scheme token_hud -destination 'platform=macOS' build`
4. 运行构建产物并用 LLDB attach 验证：
   - app 进程保持运行。
   - `lldb -p <pid> -o detach -o quit` 可以成功暂停并 detach。

### 验证

- `xcodebuild` build 通过。
- `codesign -d --entitlements :-` 仍保留 `com.apple.security.get-task-allow = true`。
- 构建产物不再生成/依赖 `token_hud.debug.dylib`。
- LLDB attach 成功，Xcode 不应再出现同类 attach failed。

### 风险

- 关闭 `ENABLE_DEBUG_DYLIB` 只影响 Xcode 的新式 Debug Dylib 调试模式；常规源码断点和 LLDB 调试仍可用。
- 当前项目同时维护 `project.yml` 和已生成的 `.xcodeproj`，需要同步修改两处，避免下次打开 Xcode 和下次生成项目配置不一致。
- 如果后续升级 Xcode 后该 bug 被修复，可以再评估是否恢复 Debug Dylib。

## 当前重点：App 动画、溢出与重复操作稳定性深度体检（已实现，待手动体验验证）

### 问题

用户希望再做一次全 App 深度体检，重点优化：

- 动画不连贯。
- 页面溢出。
- 开启应用或重复操作时可能出现的 bug。

本轮已阅读：

- `PLAN.md`
- `docs/project-summary.md`
- `docs/work-log/2026-06-01-notch-fusion-smooth.md`
- `docs/work-log/2026-06-08-notch-restore-stale-frame.md`
- `docs/work-log/2026-06-11-startup-collapse-accessibility.md`
- `token_hud/Overlay/NotchHostPanelManager.swift`
- `token_hud/Overlay/NotchHostedSurfaceView.swift`
- `token_hud/Overlay/NotchHostRootView.swift`
- `Sources/token_hudCore/NotchSurfacePolicy.swift`
- `token_hud/Settings/SettingsWindow.swift`
- `token_hud/Settings/PlatformListView.swift`
- `token_hud/Settings/WidgetListEditor.swift`
- `token_hud/State/StateWatcher.swift`
- `token_hud/State/AppWatcher.swift`

初步体检发现的高风险点：

- 刘海 hosted 浮窗的状态机仍有重复操作风险：
  - `toggle()` 隐藏窗口时只移除 mouse move monitor，没有统一取消 collapse timer、mouseDown/mouseUp monitor 和拖拽状态；如果隐藏前有 collapse timer 排队，后续可能把 overlay 又拉回前台。
  - `isDragging` 依赖 local mouseUp monitor 复位；如果 mouseUp 丢失，后续 hover 会被 `guard !isDragging` 阻断，`saveState()` 也会因为 `isDragging` 直接返回。
  - `screenParametersChanged()` 在 hosted expanded 时重新打开 `isMovableByWindowBackground`，和“hosted frame 始终 canonical”的约束需要重新核对。
- 动画路径分散：
  - hosted/collapsed/expanded/detached 的切换、`prepareOverlayForDisplay`、`setFrame`、`orderFront/orderOut` 和 SwiftUI `withAnimation` 分散在多个函数里，重复点击/hover 可能产生时序竞争。
  - Widget 内部 ring/bar/countdown 也有独立 animation，和外层 expanded/collapsed 动画同时发生时可能显得不连贯。
- Settings 页存在布局溢出风险：
  - `SettingsWindow` 固定 `900x620`，sidebar 和 detail 均有固定宽度，窗口被系统缩放或内容变长时缺少统一最小宽度/换行策略。
  - `PlatformListView` 仍有多处固定宽度（sidebar 260、label/value width、status pill），长 provider 名、长路径、长错误和权限文案可能挤压。
  - `WidgetListEditor` 的预览、分组预览和小组件管理区包含多个固定 card width / fixed height，配置数量多时容易横向或纵向拥挤。
  - `KeyRecorder` 没有 `onDisappear` 清理 local monitor，重复打开/关闭设置页时可能留下录制状态。
- 重复操作并发风险：
  - `PlatformListView.refresh()` 每次点击都会启动新的 `Task`，没有按平台做 in-flight guard；连续点击可能出现旧结果覆盖新结果。
  - `resetMessage` 使用多个 `DispatchQueue.main.asyncAfter`，旧 timer 可能清掉新的提示。
  - `StateWatcher` 在 state file 不存在时用 `asyncAfter` 重试；路径变化或 stop/start 后旧重试闭包可能在新一轮运行中继续触发，造成重复 watcher 或多次 read。

### 本轮目标

- 让启动、hover、隐藏/显示、拖拽、吸附、屏幕变化这些浮窗动作更稳：
  - 关闭窗口或切换状态时统一清理 timer/monitor/drag state。
  - 重复 hover、重复点击菜单项、重复拖拽不会让 overlay 意外重新出现、卡住或忽略 hover。
  - hosted frame 继续保持 canonical，不引入新的漂移路径。
- 让动画更连贯：
  - hosted 展开/收起只由一个清晰的 transition coordinator 驱动。
  - 减少外层 surface 动画与内部 widget 动画互相抢节奏。
  - 不做大规模视觉重做，只修掉明显不顺和状态竞争。
- 修复页面溢出：
  - Settings 三页在当前窗口宽度下不横向溢出、不重叠。
  - 长文本、长路径、长错误、长平台状态统一换行/截断。
  - 小组件多、模型多、服务多时仍可滚动查看，不撑破容器。
- 加固重复操作：
  - 刷新、授权刷新、清空数据、快捷键录制、state watcher 重启都要避免旧任务覆盖新状态。
- 保留已有行为：
  - 不改平台认证数据模型。
  - 不改 state.json schema。
  - 不回滚前几轮 Settings 磨砂、小组件分组删除、启动收起和权限入口改动。

### 方案取舍

- **推荐方案：集中体检 + 小步修复**
  - 先加/调整 core 纯逻辑测试和少量 app 侧生命周期 guard。
  - 优点：能覆盖这次提到的启动/重复操作问题，风险受控。
  - 缺点：不会一次性重构所有 Settings 大文件。
- **更激进方案：重构浮窗状态机和 Settings 页面结构**
  - 把 `NotchHostPanelManager` 拆成状态机/窗口控制器/monitor 管理器，把 Settings 大文件拆分。
  - 优点：长期结构更干净。
  - 缺点：改动面大，容易引入新回归，不适合当前已有多轮未提交视觉改动的工作区。
- **保守方案：只修肉眼可见溢出和一个两个动画点**
  - 优点：最快。
  - 缺点：无法覆盖“开启应用或重复操作时”的深层 bug。

本轮建议采用“集中体检 + 小步修复”。

### 实施步骤

1. **建立体检清单与可测策略**
   - 复核现有 `NotchTransitionPolicy`、`NotchHoverRegionPolicy`、`NotchRestorePolicy` 测试覆盖。
   - 增加或调整纯逻辑测试，覆盖：
     - 隐藏窗口时 pending collapse 不应再次显示 overlay。
     - 拖拽结束/取消后 drag state 必须复位。
     - repeated hover collapse/expand 的 token gate 不接受旧 timer。
     - state file missing retry 在 stop/start 或路径变化后不产生旧重试副作用。

2. **加固刘海浮窗状态机**
   - 增加一个内部 cleanup 方法，用于隐藏、detach、teardown、screen change 前清理：
     - collapse timer
     - mouseDown/mouseUp monitor
     - dragging flag
   - `toggle()` hide 分支调用 cleanup，避免隐藏后旧 timer 把 overlay order front。
   - mouseUp monitor 丢失时增加兜底：切换到 detached/hidden/teardown 时强制 `isDragging = false`。
   - 复核 expanded 是否还需要 `isMovableByWindowBackground = true`；如果会破坏 canonical frame，改为更明确的 body mouseDown → detach 路径。
   - 保持 `hostState.expansionProgress` 是 hosted 动画的唯一视觉进度。

3. **统一动画节奏**
   - 为 hosted 展开/收起抽出单一 spring 参数，避免多个地方硬编码。
   - 在 body 逐渐出现阶段降低内部 widget animation 抢节奏的概率；必要时只让外层 opacity/scale 动，内部数值动画保留在数据变化场景。
   - `NotchHostRootView` 避免对 `expansionProgress` 外再叠加多余隐式动画。

4. **修复 Settings 页面溢出**
   - `SettingsWindow` 增加合理最小宽高和 detail 区自适应约束。
   - `PlatformListView`：
     - header / 状态 pill / 操作按钮继续使用 `ViewThatFits` 或换行策略。
     - value/path/error/token 文案统一 middle truncation 或 disclosure。
     - 固定宽度字段改为 min/max 或 flexible layout。
   - `WidgetListEditor`：
     - 当前效果/推荐/管理区限制 card 最小最大宽度。
     - widget 多时优先滚动，不撑破外层。
     - service/model label 加强截断。
   - `KeyRecorder` 增加 `onDisappear` 停止录制并移除 monitor。

5. **加固重复操作与并发**
   - `PlatformListView` 增加 per-platform refreshing 状态：
     - 同平台刷新进行中时禁用按钮或合并点击。
     - 旧结果不能覆盖新结果。
   - `resetMessage` 改用 message token，旧 `asyncAfter` 只能清理自己创建的消息。
   - `StateWatcher` missing-file retry 增加 generation token，stop/path change 后旧 retry 无效。
   - 检查 `CodexFetcher` / `APIPlatformFetcher` 的 timer reschedule 是否会重复安装；如果已有 guard，记录不改。

6. **验证**
   - 自动验证：
     - `swift test --filter NotchSurfacePolicy`
     - `swift test --filter NotchGeometryCalculator`
     - `swift test --filter Widget`
     - `swift test`
     - `xcodebuild -project token_hud.xcodeproj -scheme token_hud -destination 'platform=macOS' build`
   - 手动验证：
     - 启动 app 多次，顶部 HUD 不闪大面板、不漂移。
     - 快速 hover 刘海、移出、再 hover，动画不跳、不重影。
     - 连续点击菜单栏开关浮窗，隐藏后不会被旧 timer 拉回前台。
     - expanded body 拖动、松手、再吸附回刘海，drag state 不残留。
     - 连续点击平台刷新/授权刷新，按钮状态和提示不互相覆盖。
     - Settings 小组件/平台/通用页在默认宽度和较窄宽度下没有文字重叠、横向撑破或按钮挤出。

### 验证

- 单元测试覆盖新增策略或生命周期 helper。
- 全量 Swift 测试确保 core 行为不回退。
- Xcode app build 确保新增文件/修改能进入 app target。
- 手动重点验证真实 macOS 窗口和 hover/drag 行为，因为这部分不是纯测试能完全覆盖。

### 风险

- hosted 浮窗拖拽逻辑历史上多次修改，本轮必须小步验证，避免重新引入“透明大窗口漂移”。
- macOS 全局/local event monitor 在不同激活状态下行为不同；代码里要以清理和兜底为主，不能依赖某个事件一定到达。
- Settings 页面文件已经较大，本轮只做局部布局和生命周期修复，不顺手做大拆分。
- 当前工作区已有多轮未提交 UI 改动，本轮不会回滚它们；如果某些视觉问题来自之前改动，会在其基础上继续修正。

### 本轮实现结果（2026-06-17）

- 浮窗生命周期加固：
  - 新增 `NotchPanelLifecyclePolicy` 和测试，明确 hide/teardown/switchToDetached 需要清理的 timer、monitor 和 drag state。
  - `NotchHostPanelManager` 的 hide、teardown、switchToDetached 改用统一 cleanup。
  - hide/teardown 会取消 collapse timer、移除 mouse move/down/up monitor，并复位 `isDragging`。
  - switchToDetached 会取消 collapse 和 mouse move/down monitor，但保留 mouseUp 路径与 `isDragging`，避免拖拽中的 transient frame 被写盘。
- 动画节奏优化：
  - 移除 `NotchHostRootView` 对 `expansionProgress` 的额外隐式 animation。
  - hosted 展开/收起的 spring 参数集中在 `NotchHostPanelManager.hostedTransitionAnimation`。
- 重复操作加固：
  - `PlatformListView` 增加 per-platform `refreshingPlatformIDs`，同平台刷新进行中会忽略重复点击。
  - `resetMessage` 使用 `NotchTransitionGate` token，旧延迟清理不能清掉新提示。
  - `StateWatcher` 缺文件重试使用 generation token，stop/path change 后旧 retry 失效。
  - `StateWatcher.stop()` 避免 dispatch source cancel handler 和 stop 本身重复 close 同一个 file descriptor。
  - `KeyRecorder` 在 disappear 和清除快捷键时停止录制并移除 local monitor。
- 溢出处理：
  - Settings window 默认内容尺寸改为 900x620，最小尺寸 760x560。
  - `SettingsWindow` root 从固定 frame 改为 min/ideal/max 自适应 frame。
  - 平台页 header status pills 使用 `ViewThatFits`，窄宽度下自动换行。
  - `InfoRow` 改为横向/纵向自适应，长值 middle truncation。
  - 小组件页 header 使用 `ViewThatFits`，推荐 chip 的 service/metric 文案增加截断保护。
- 已沉淀 work-log：
  - `docs/work-log/2026-06-17-app-health-pass.md`

### 验证结果

- `swift test --filter NotchSurfacePolicy`：通过，19 个测试通过。
- `swift test --filter NotchGeometryCalculator`：通过，50 个测试通过。
- `swift test --filter Widget`：通过，37 个测试通过。
- `swift test`：通过，153 个测试通过。
- `xcodebuild -project token_hud.xcodeproj -scheme token_hud -destination 'platform=macOS' build`：通过。

### 待手动验证

- 快速打开/隐藏浮窗，确认隐藏后不会被旧 collapse timer 拉回前台。
- 快速 hover 刘海、移出、再 hover，确认展开/收起不跳、不重影。
- expanded body 拖动到 detached，再吸附回刘海，确认 drag state 不残留。
- 在平台页连续点击刷新/授权刷新，确认按钮和提示稳定。
- 缩窄 Settings window，检查平台页和小组件页是否仍有文字重叠或横向撑破。

## 当前重点：启动浮窗自动收起与辅助功能授权弹窗修复（已实现，待手动体验验证）

### 问题

用户反馈两个启动体验问题：

- 顶部浮窗打开时会以大尺寸/大字体状态卡在屏幕顶部，部分内容被刘海遮挡；必须再做一次操作才会缩起来，卡顿感明显。期望启动后直接自动收起。
- 系统反复弹出“辅助功能访问”授权提示，并要求输入密码授权。

本轮已阅读：

- `PLAN.md`
- `docs/work-log/2026-06-08-notch-restore-stale-frame.md`
- `docs/work-log/2026-06-01-notch-fusion-smooth.md`
- `Overlay/NotchHostPanelManager.swift`
- `Overlay/GlobalHotkeyManager.swift`
- `App/AppDelegate.swift`
- `Sources/token_hudCore/NotchGeometryCalculator.swift`

初步定位：

- 浮窗问题和历史 `notch-restore-stale-frame` 属同一类：app 启动恢复了旧的 detached/expanded 尺寸或顶部附近的窗口状态。当前已有 stale frame guard，但启动默认值和恢复顺序仍偏宽松，可能让“看起来像 hosted 展开态”的窗口以 detached 形态显示出来。
- 当前 `restoreState()` 的默认 saved mode 是 `"detached"`，这与产品主形态“刘海融合 HUD（hosted）”不一致；没有可靠状态时应优先恢复 hosted collapsed，而不是显示自由浮窗。
- 当前 app 启动时会无条件执行：
  - `hotkeyManager.setup()` 安装全局键盘监听。
  - `GlobalHotkeyManager.requestAccessibility()` 主动触发系统辅助功能授权弹窗。
- `GlobalHotkeyManager.setup()` 无论用户是否配置了全局快捷键，都会安装 global event monitor；这会放大系统权限提示出现频率。

### 本轮目标

- 启动后顶部 HUD 默认进入 hosted collapsed 状态：
  - 没有可靠历史状态时，默认收起到刘海位置。
  - 如果历史 detached frame 靠近刘海、菜单栏或 hosted expanded 区域，视为不可靠，直接恢复 hosted collapsed。
  - 避免 first frame 先显示大面板再收起。
- 保留真正的 detached 使用场景：
  - 用户把浮窗拖到屏幕中部/远离刘海区域时，重启后仍可恢复自由浮窗。
  - 不粗暴清空所有 detached 状态。
- 停止启动时反复弹辅助功能授权：
  - app 启动不主动调用 `AXIsProcessTrustedWithOptions(prompt: true)`。
  - 未配置全局快捷键时不安装 global key monitor。
  - 已配置快捷键但未授权时，只在设置页给出明确入口，由用户主动触发授权。
- 让全局快捷键仍可用：
  - 用户授权后，app 重新激活或设置变化时刷新 global monitor。
  - local monitor 保留，app 前台时快捷键仍可响应。

### 实施步骤

1. **补充/调整纯逻辑测试**
   - 在 `NotchGeometryCalculatorTests` 中覆盖顶部附近、大尺寸、与 menu bar/hosted expanded 区域相交的 detached frame。
   - 验证远离刘海的 detached frame 不会被误判为 stale。
   - 如需要，增加“无 saved mode 默认 hosted collapsed”的恢复策略测试，优先放在 core 可测逻辑里。

2. **收紧启动恢复策略**
   - 将没有 saved mode 时的默认恢复从 detached 调整为 hosted collapsed。
   - 在 `restoreState()` 中先设置 `hostState.mode = .collapsed` 和 `expansionProgress = 0`，再显示 overlay window，减少首帧大面板闪现。
   - 对 saved detached frame 增加更保守的顶部/刘海区域判断；命中时不显示 detached window，直接恢复 hosted collapsed。
   - 保持远离顶部的 detached frame 原样恢复。

3. **修复辅助功能弹窗触发方式**
   - 移除 `AppDelegate.applicationDidFinishLaunching` 中启动即请求辅助功能权限的逻辑。
   - `GlobalHotkeyManager.setup()` 改为：
     - 总是安装 local monitor。
     - 仅当用户配置了有效全局快捷键且 `AXIsProcessTrusted()` 为 true 时安装 global monitor。
     - 监听 `UserDefaults.didChangeNotification` 和 app 激活事件，必要时刷新 global monitor。
   - 避免重复安装 monitor，`teardown()` 清理新增 observer。

4. **设置页增加明确授权入口**
   - 在通用/浮窗快捷键设置区域显示辅助功能状态。
   - 当用户已配置全局快捷键但未授权时，展示简短提示和“打开/请求辅助功能权限”按钮。
   - 只有点击按钮时才调用 `GlobalHotkeyManager.requestAccessibility()`。
   - 文案控制简洁，不做大段说明。

5. **验证**
   - 自动验证：
     - `swift test --filter NotchGeometryCalculator`
     - `swift test --filter Widget`
     - `swift test`
     - `xcodebuild -project token_hud.xcodeproj -scheme token_hud -destination 'platform=macOS' build`
   - 手动验证：
     - 启动 app，顶部 HUD 直接处于刘海 collapsed 状态，不出现大字体面板卡住。
     - 关闭/重启 app，远离刘海的自由浮窗仍能恢复。
     - 启动 app 时不自动弹出辅助功能授权。
     - 配置全局快捷键后，设置页显示权限状态；点击授权入口后再授权。
     - 授权完成并回到 app 后，全局快捷键可用。

### 验证

- 单元测试覆盖启动恢复几何判断，避免再次把顶部旧 detached frame 当成可恢复浮窗。
- 编译验证 app target。
- 手动检查权限弹窗只由用户在设置页点击触发，不在普通启动时触发。

### 风险

- 如果用户刻意把 detached 浮窗贴近顶部但不想吸附刘海，本轮会更倾向于把它恢复为 hosted collapsed；这是为了解决启动遮挡刘海和卡住问题的取舍。
- macOS 辅助功能权限状态不会实时推送给 app；需要通过 app 重新激活、设置变化或重启来刷新 global monitor。本轮会在 app 激活时刷新，降低用户感知成本。
- 如果系统提示来自其他权限链路（例如 Keychain），本轮只解决截图中明确的辅助功能授权；后续需按新截图/日志继续拆分。

### 本轮实现结果（2026-06-11）

- 新增 `NotchRestorePolicy`，把启动恢复策略从窗口管理器中抽成可测试的 core 逻辑：
  - 缺失 saved mode 时默认恢复 hosted collapsed。
  - saved detached frame 靠近刘海/hosted surface 时视为 stale，恢复 hosted collapsed。
  - 远离顶部工作区的 detached frame 保持自由浮窗恢复。
- `NotchHostPanelManager.restoreState()` 改用 `NotchRestorePolicy`：
  - hosted 恢复时先设置 `.collapsed` 和 `expansionProgress = 0`。
  - hosted surface 恢复 frame 时不强制显示首帧，避免大面板先闪出来。
  - stale detached frame 继续从 UserDefaults 中移除。
- 移除 app 启动时主动请求辅助功能权限的逻辑。
- `GlobalHotkeyManager` 改为按需安装 global monitor：
  - local monitor 始终保留，app 前台可用。
  - 只有配置了有效快捷键且辅助功能已授权时，才安装 global monitor。
  - 监听 UserDefaults 变化和 app 激活，授权后回到 app 会刷新监听状态。
- Settings 通用 → 浮动面板区域增加辅助功能授权入口：
  - 只有已配置快捷键且未授权时显示。
  - 只有点击“授权”按钮时才触发系统权限提示。
- 已沉淀 work-log：
  - `docs/work-log/2026-06-11-startup-collapse-accessibility.md`

### 验证结果

- `swift test --filter NotchGeometryCalculator`：通过，50 个测试通过。
- `swift test --filter Widget`：通过，37 个测试通过。
- `swift test`：通过，150 个测试通过。
- `xcodebuild -project token_hud.xcodeproj -scheme token_hud -destination 'platform=macOS' build`：通过。

### 待手动验证

- 启动 app，顶部 HUD 应直接处于刘海 collapsed 状态，不再显示大字体展开面板卡住。
- 启动 app 不应自动弹出辅助功能授权弹窗。
- 在 Settings → 通用 → 浮动面板配置快捷键后，如未授权，应只在设置页显示授权入口。
- 授权完成并回到 app 后，全局快捷键应恢复可用。

## 当前重点：Settings 全局简洁化与磨砂玻璃视觉（已实现，待手动体验验证）

### 问题

用户希望排查整个 app 里 UI 不够简洁清爽、文字溢出和排版不合理的问题，并把页面与浮窗统一调整为“半透明但不要太透”的磨砂质感。

本轮已确认：

- 用户提到的“赛题页面”按当前仓库实际结构理解为 Settings 设置页面，重点是平台页。
- 当前 app 主要视觉面包括：
  - Settings 外壳：`Settings/SettingsWindow.swift`
  - 平台页：`Settings/PlatformListView.swift`
  - 小组件页：`Settings/WidgetListEditor.swift`
  - 自由浮窗：`Overlay/FloatingPanelView.swift`
  - 刘海 hosted 浮窗：`Overlay/NotchHostedSurfaceView.swift`
  - 浮窗内容：`Overlay/CompactOverlayContent.swift`、`Overlay/GroupedOverlayView.swift`、`Widgets/*`

初步排查：

- Settings window 当前是普通 `NSWindow` + `Color(nsColor: .windowBackgroundColor)`，整体没有透明/磨砂层。
- Settings sidebar 和平台页 sidebar 使用纯系统背景，detail 区与 sidebar 层级分割偏硬，不够轻。
- 平台页详情里 `GroupBox` 多、说明文字长，尤其是 Codex extras、MiniMax/MiMo 能力说明、usageUnsupported 详情，容易形成大段文字墙。
- 平台页 header 在窄宽度下同时放标题、多个状态 pill 和刷新按钮，存在挤压风险。
- 平台列表行只靠小圆点 + pill 表达状态，选中背景较弱，视觉扫描性一般。
- 浮窗自由态和刘海 hosted 态目前接近纯黑不透明：
  - `FloatingPanelView` 使用 `Color.black.opacity(0.75)`。
  - `NotchHostedSurfaceView` top/body 使用 `Color.black.opacity(0.96~0.97)`。
  - 视觉稳定但不符合“透透的磨砂质感”。
- 浮窗内容横向排列时缺少 overflow 保护，组件多时紧凑态可能拥挤。

### 本轮目标

- 给 Settings 设置窗口建立统一的半透明磨砂基底：
  - 窗口本身透明，内容用 SwiftUI material/半透明层承载。
  - 透明度控制在可读优先，不做过透的玻璃。
  - sidebar、detail、卡片边界更轻、更统一。
- 简化平台页布局：
  - 平台 sidebar 更清爽，状态不挤压平台名。
  - detail header 在窄宽度下不溢出。
  - 长说明默认收起或压缩成短句，必要信息仍可展开查看。
  - 当前数据/认证/查询能力/重置区域保持清晰，但减少重卡片感。
- 优化文字溢出：
  - 长 key/email/path/状态说明使用 `lineLimit`、`truncationMode(.middle)`、`ViewThatFits` 或换行策略。
  - 按钮组在宽度不足时自动换行。
  - 状态 pill 不撑破容器。
- 优化浮窗玻璃质感：
  - 自由浮窗背景改为深色半透明 material + 细描边 + 更轻阴影。
  - 刘海 hosted 展开 body 改为更柔和的玻璃层；collapsed top cap 仍保持足够黑度以融合刘海，但可加入轻微 material/高光边界。
  - resize grip 降低视觉存在感。
- 保持交互和数据模型不变：
  - 不改 credential/keychain、fetcher、state.json。
  - 不改刘海吸附/脱离策略。
  - 不改 widget 配置存储。

### 实施步骤

1. **建立 Settings 磨砂窗口外壳**
   - 在 `App/AppDelegate.swift` 的 settings window 创建处：
     - 设置 `win.isOpaque = false`。
     - 设置 `win.backgroundColor = .clear`。
     - 视情况启用透明 titlebar/fullSizeContentView，使磨砂背景覆盖更完整。
   - 在 `Settings/SettingsWindow.swift`：
     - 用统一的半透明 material 背景替换纯 `windowBackgroundColor`。
     - sidebar 使用 `.regularMaterial` 或深浅适中的半透明底。
     - detail 区使用轻透明层，不让整个页面变成完全透明。

2. **抽取轻量视觉 helper（仅限 Settings 内部）**
   - 在 `SettingsWindow.swift` 或 `PlatformListView.swift` 局部增加少量 helper：
     - glass 背景 shape。
     - subtle border。
     - compact section/card 样式。
   - 不新建复杂 design system；只解决当前页面重复的背景/描边/阴影。

3. **整理 Settings sidebar**
   - 降低选中 row 的厚重色块，改为半透明 tint + 左侧轻强调或更浅背景。
   - 保持按钮高度稳定，不让字体/图标挤压。
   - 避免 sidebar 背景和标题栏区域冲突。

4. **整理平台页左栏**
   - `PlatformSidebarRow` 改为更紧凑可扫描：
     - 平台名 `lineLimit(1)`。
     - 状态 pill 缩短并限制宽度。
     - 选中态更清楚但不使用大块重色。
   - 已配置数量 badge 改成更轻的玻璃 badge。
   - 左栏背景改为半透明 material，与 Settings 总背景融合。

5. **整理平台页详情 header**
   - header 使用 `ViewThatFits`：
     - 宽屏：标题/状态与刷新按钮同一行。
     - 窄屏：按钮组换到下一行。
   - 状态 pill 允许收缩，不挤压 provider 名称。
   - 刷新/授权刷新按钮使用图标优先，文字保持简短。

6. **压缩平台页卡片与长说明**
   - 将认证、查询能力、当前数据、重置卡片改为更轻的 glass card。
   - `PlatformCapabilityPanel` 默认只显示能力类型与凭据，详细解释保留在 Disclosure。
   - `PlatformMetricsPanel` 中长错误/不支持说明使用简短主文案 + 可展开详情，避免直接铺满页面。
   - Codex extras、MiMo credential summary 的长 label 使用 `fixedSize(horizontal: false, vertical: true)` 和更紧凑 spacing，必要时改短文案。

7. **优化小组件页与通用页一致性**
   - 小组件页现有卡片背景过多使用 `Color.secondary.opacity`，统一调整到轻 glass card。
   - 通用页 `Form` 如系统样式与透明背景冲突，改成更透明的 section 背景或保留系统 Form 但放入统一 material 容器。
   - 不改变上一轮“当前效果按模型分组与删除”的行为。

8. **优化自由浮窗**
   - `FloatingPanelView` 背景从纯黑透明改为：
     - 深色半透明主层。
     - material/blur 质感。
     - 细白描边和更轻阴影。
   - 保持浮窗不太透，确保 widget 文本仍可读。
   - resize grip 透明度降低，避免抢视觉。
   - compact 内容在空间不足时至少不产生明显重叠；必要时加横向滚动或收紧 spacing。

9. **优化刘海 hosted 浮窗**
   - `NotchHostedSurfaceView` 的 expanded body 使用更柔和的半透明 glass。
   - collapsed top cap 保持接近刘海黑度，不牺牲融合感；只增加微弱边界/高光，避免变成灰色浮块。
   - 状态 slot 的文字和进度条保留可读性。

10. **验证与手动检查**
   - 编译和测试：
     - `swift test --filter Widget`
     - `swift test --filter NotchGeometryCalculator`
     - `swift test`
     - `xcodebuild -project token_hud.xcodeproj -scheme token_hud -destination 'platform=macOS' build`
   - 手动检查：
     - Settings 三页都呈现半透明磨砂，但文字不透底难读。
     - 平台页 Codex/MiMo/MiniMax/OpenAI 等长说明不溢出。
     - 缩窄 Settings 窗口时 header、按钮、状态 pill 不重叠。
     - 自由浮窗在浅色/深色桌面背景下都有足够对比度。
     - 刘海 collapsed/expanded 不出现灰边、重影或过透。

### 验证

- 自动：
  - `swift test --filter Widget`
  - `swift test --filter NotchGeometryCalculator`
  - `swift test`
  - `xcodebuild -project token_hud.xcodeproj -scheme token_hud -destination 'platform=macOS' build`
- 手动：
  - 打开 Settings → 小组件 / 平台 / 通用，检查磨砂背景、文本溢出、滚动和卡片间距。
  - 平台页逐个切换 provider，重点看 Codex、MiniMax、MiMo、OpenAI 的说明和状态。
  - 切换浮窗紧凑/分组模式，检查自由浮窗与刘海 hosted 展开态。
  - 调整窗口宽度，检查标题、按钮、pill 是否换行或截断合理。

### 风险

- macOS material 在不同系统外观、壁纸和 Reduce Transparency 设置下表现不同；需要以可读性优先，不能为了“透”牺牲对比度。
- Settings window 透明 titlebar 可能影响当前手动预留的 `chromeTopInset`，需要重新检查红黄绿按钮和 sidebar 顶部间距。
- 刘海 collapsed 状态如果改得太透，会破坏与真实刘海融合；collapsed 只做轻微优化，expanded 和 detached 才更明显玻璃化。
- 平台页文件已经较大，本轮只做布局和样式整理，不顺手拆旧 `PlatformRowView.swift` 或重构 fetcher。
- 上一轮 Settings 当前效果分组改动仍未手动验收，本轮不能覆盖或回滚相关行为。

### 本轮实现结果（2026-06-09）

- Settings window 创建处改为透明承载：
  - `NSWindow.isOpaque = false`
  - `NSWindow.backgroundColor = .clear`
- `SettingsWindow` 外壳改为统一 material 磨砂背景：
  - sidebar 使用更轻的 material 底。
  - detail 区增加轻透明层。
  - sidebar 选中态从重色块改为轻 tint + 左侧强调条。
  - ScrollView/Form 隐藏默认滚动背景，减少系统纯色块。
- 平台页左栏优化：
  - 改为 material 背景。
  - row 增加轻描边和选中态强调。
  - 平台名、状态 pill 增加 `lineLimit` / `minimumScaleFactor`，降低挤压风险。
- 平台详情优化：
  - header 使用 `ViewThatFits`，窄宽度下按钮组自动换到下一行。
  - 认证、查询能力、当前数据、重置区域从 `GroupBox` 改为轻玻璃卡片 `GlassPanel`。
  - 当前数据无数据/不支持时只显示短状态，详细说明放入 Disclosure，避免文字墙。
  - Codex/MiMo/API key 等长说明增加换行/截断保护。
- 自由浮窗优化：
  - 背景从纯黑半透明改为 `.regularMaterial` + 深色半透明覆盖 + 细描边。
  - 阴影更轻，resize grip 透明度降低。
  - 紧凑内容增加横向 overflow 保护。
- 刘海 hosted 浮窗优化：
  - expanded body 改为 material + 深色半透明覆盖 + 轻描边。
  - collapsed top cap 保持较深黑度以贴合刘海，同时增加轻微边界。
  - 分组 overlay 行内 widget 增加横向 overflow 保护，service label 防溢出。

### 验证结果

- `xcodebuild -project token_hud.xcodeproj -scheme token_hud -destination 'platform=macOS' build`：通过。
- `swift test --filter Widget`：通过，37 个测试通过。
- `swift test --filter NotchGeometryCalculator`：通过，47 个测试通过。
- `swift test`：通过，147 个测试通过。
- 最终再次运行 `xcodebuild -project token_hud.xcodeproj -scheme token_hud -destination 'platform=macOS' build`：通过。

### 待手动验证

- 打开 Settings 三页，确认磨砂透明程度不过透，文字仍清晰。
- 平台页逐个切换 Codex、MiniMax、MiMo、OpenAI，确认长说明不溢出且页面更清爽。
- 缩窄 Settings window，确认 header、状态 pill、刷新按钮不会重叠。
- 切换浮窗紧凑/分组模式，确认自由浮窗内容不会明显挤压。
- 测试刘海 collapsed/expanded，确认顶部仍与刘海融合，没有灰边或过透。

---

## 当前重点：Settings 当前效果按模型分组与快捷删除（已实现，待手动体验验证）

### 问题

Settings 小组件页的“当前效果”预览目前把所有已添加小组件横向堆在一起：

- 不同平台/模型的小组件混在同一行，数量稍多时视觉层级不清。
- 用户新增一个效果后，如果发现加错，需要去下方“已添加”列表里找对应项删除；预览区本身没有直接删除入口。
- 预览区文案提示可以拖拽预设到这里，但已添加后的排序能力主要藏在下方列表，当前区域的编辑边界不够清楚。

本轮已阅读：

- `PLAN.md`
- `docs/project-summary.md`
- `docs/work-log/2026-05-10-widget-settings-preview.md`
- `docs/work-log/2026-06-07-widget-recommendations-notch-collapsed.md`
- `Settings/WidgetListEditor.swift`

用户已在视觉草图中选择方案 A：

- “当前效果”按模型/平台分组展示。
- 每个预览项提供删除按钮。
- 拖拽排序继续由下方“已添加”列表负责，避免预览区同时承担真实 HUD 预览和完整列表编辑器两套职责。

### 本轮目标

- 优化“当前效果”区域视觉结构：
  - 按 `WidgetConfig.service` 分组展示。
  - 每组显示平台/模型名称和组件数量。
  - 每个组件继续复用现有 `WidgetRenderer`，保持预览接近真实 HUD。
- 在预览项上提供明确删除入口：
  - 点击删除后从 `WidgetStore.widgets` 移除对应 `WidgetConfig`。
  - 删除行为与下方 `WidgetRow` 删除保持一致。
- 明确排序入口：
  - “当前效果”主要负责预览、分组和快捷删除。
  - “已添加”列表继续负责拖动排序。
  - 调整提示文案，避免暗示预览区支持已添加项排序。
- 保持现有添加方式：
  - 预设仍可点击添加。
  - 预设仍可拖到“当前效果”预览或“已添加”列表。

### 实施步骤

1. **调整 `WidgetPreviewPanel` 数据入口**
   - 将 `WidgetPreviewPanel` 从只读 `widgets: [WidgetConfig]` 改为可写 `@Binding var widgets: [WidgetConfig]`。
   - 保留 `state: StateFile`。
   - 在 `WidgetListEditor` 调用处传入 `Bindable(store).widgets`。

2. **新增分组模型**
   - 在 `WidgetPreviewPanel` 内部按 `service` 分组。
   - 分组顺序保持用户当前小组件顺序中的首次出现顺序，避免按字母排序打乱用户心理模型。
   - 每组内部顺序保持 `store.widgets` 当前顺序。
   - 分组标题使用现有 `serviceDisplayName(_:)`；组件标题继续用 `metricTitle(_:)`。

3. **重做非空预览布局**
   - 将当前单一横向 `ScrollView + HStack` 改为垂直滚动的分组布局。
   - 每组内使用横向滚动或可换行布局承载多个预览项，优先保证不同 service 的边界清楚。
   - 保留深色预览背景、HUD 字体/颜色可读性和 `panelAdaptiveScale`。
   - 预览区高度根据分组布局适度提高或设定最小/最大高度，避免内容拥挤。

4. **给预览项添加删除按钮**
   - 每个预览 item 外层增加轻量容器，右上或尾部放 `xmark` 图标按钮。
   - 按钮使用 `.buttonStyle(.plain)`，并加 `.help("移除")`。
   - 删除逻辑使用 `widgets.removeAll { $0.id == config.id }`。
   - 删除按钮不遮挡 `WidgetRenderer` 的主要内容。

5. **更新提示文案**
   - 空状态文案保留“从下方预设添加，或拖拽预设到这里”。
   - 非空 header 或说明明确为“按模型分组 · 拖动排序在下方已添加列表”。
   - 下方“已添加”列表继续显示“拖动调整顺序”。

6. **检查 drop 行为**
   - 保持 `WidgetPreviewPanel` 外层 `.onDrop` 现有行为。
   - 确认预览 item 的删除按钮不会破坏拖入预设到预览区。

### 验证

- `swift test --filter Widget`
- `swift test`
- `xcodebuild -project token_hud.xcodeproj -scheme token_hud -destination 'platform=macOS' build`
- 手动验证：
  - 打开 Settings → 小组件。
  - 当前效果按 Codex、Claude、MiniMax、MiMo 等 service 分组。
  - 添加多个平台的小组件后分组顺序符合添加顺序。
  - 点击预览项删除按钮后，对应组件从预览和“已添加”列表同时消失。
  - 下方“已添加”列表仍可拖动排序；排序后预览分组内顺序同步更新。
  - 将预设拖到当前效果区域仍能添加。

### 风险

- `WidgetListEditor.swift` 已经较大，本轮应控制改动范围，只在预览区局部抽取小视图，不做无关重构。
- 预览项加容器和删除按钮可能让真实 HUD 预览感变弱，需要保持容器轻量，避免看起来像另一套卡片列表。
- 如果分组过多，固定高度预览区可能仍会拥挤；需要使用滚动区域和清晰标题控制密度。
- SwiftUI `Button` 与 `onDrop`/滚动手势可能有交互冲突，需手动检查拖入和点击删除都可用。

### 本轮实现结果（2026-06-08）

- 新增 `WidgetServiceGrouping` / `WidgetServiceGroup`：
  - 按 `WidgetDescriptor.service` 分组。
  - 分组顺序保持 service 首次出现顺序。
  - 组内 widget 顺序保持当前小组件顺序。
- `WidgetPreviewPanel` 改为接收 `@Binding var widgets`，预览区可以直接删除已添加组件。
- “当前效果”非空状态改为：
  - 垂直展示 service 分组。
  - 每组内横向展示该 service 的预览项。
  - 每个预览项保留 `WidgetRenderer` 渲染，并新增 `xmark.circle.fill` 删除按钮。
- Header 文案改为显示组数、组件数，并提示排序在下方列表完成。
- 保留预览区域 drop 行为，预设仍可拖到“当前效果”区域添加。

### 验证结果

- `swift test --filter serviceGroupsPreserveFirstAppearanceAndWidgetOrder`：通过。
- `swift test --filter Widget`：通过，37 个测试通过。
- `swift test`：通过，147 个测试通过。
- `xcodebuild -project token_hud.xcodeproj -scheme token_hud -destination 'platform=macOS' build`：通过。

### 待手动验证

- 打开 Settings → 小组件，确认“当前效果”按 Codex、Claude、MiniMax、MiMo 等 service 分组。
- 点击预览项删除按钮后，对应组件从预览和下方“已添加”列表同时消失。
- 下方“已添加”列表拖动排序后，预览区分组和组内顺序同步更新。
- 将预设拖到“当前效果”区域仍能添加。

---

## 当前重点：Settings 窗口标题栏安全区错位修复（已实现，待手动体验验证）

### 问题

用户截图反馈 Settings 页面仍存在明显 UI 错位：

- 左侧 sidebar 的背景和首个选中项侵入窗口红黄绿按钮/标题栏区域。
- 右侧“小组件”标题贴近标题栏下方分割线，视觉上被压住。
- 推荐组件区域首屏被迫贴近顶部，整体像内容没有避开 macOS titlebar/toolbar safe area。

本轮已阅读：

- `PLAN.md`
- `docs/work-log/2026-06-06-settings-platform-query.md`
- `docs/work-log/2026-05-10-widget-settings-preview.md`
- `docs/work-log/2026-06-07-widget-recommendations-notch-collapsed.md`
- `Settings/SettingsWindow.swift`
- `Settings/WidgetListEditor.swift`
- `App/AppDelegate.swift`

初步排查：

- Settings 外层目前是 `NavigationSplitView`，sidebar 内使用 `List` 和 `.navigationTitle("Settings")`。
- Settings 窗口由 AppKit 手动创建：`NSWindow(styleMask: [.titled, .closable, .miniaturizable])`，再直接把 `NSHostingView(rootView: SettingsWindow())` 设为 `contentView`。
- 在当前 macOS 样式下，`NavigationSplitView/List` 的 sidebar 背景会延伸到标题栏/toolbar 区域，导致 sidebar 顶部和红黄绿按钮区域视觉重叠。
- 内部 `WidgetListEditor.padding()` 只能移动右侧内容，无法解决 sidebar 背景侵入 titlebar 的根因。

### 本轮目标

- 让 Settings 内容明确避开 macOS 标题栏区域：
  - 左侧导航首项不再贴近红黄绿按钮。
  - 右侧页面标题不再贴到 toolbar 分割线。
  - sidebar 背景不再显得覆盖标题栏。
- 保持当前信息结构：
  - 小组件 / 平台 / 通用三段导航。
  - 小组件页推荐、预览、刘海收起态、管理组件功能不丢。
- 不引入新的复杂视觉系统，本轮只处理外壳错位和必要的顶部间距。

### 实施步骤

1. **替换 Settings 外层导航壳**
   - 不再依赖 `NavigationSplitView + List` 的系统 sidebar 标题栏融合行为。
   - 改成自定义 `HStack`：
     - 左侧固定宽度 sidebar。
     - 右侧 detail 内容。
     - 中间 `Divider`。
   - 自定义 sidebar 使用普通 `Button`/`Label` row，显式控制顶部 padding。

2. **显式预留标题栏安全区**
   - 在 Settings 根视图统一定义顶部 inset，例如 `settingsChromeTopInset`。
   - sidebar 和 detail 都从该 inset 之后开始布局。
   - 保留窗口原生标题 `token_hud Settings`，不在内容区重复大标题压到 titlebar。

3. **右侧内容容器统一**
   - 为 `WidgetListEditor`、`PlatformListView`、`GeneralSettingsView` 提供一致的 detail 容器。
   - 避免每个子页面自己猜测顶部安全距离。
   - 如 `PlatformListView` 已有内部分栏，外层只给顶部/边界，不改平台页内部逻辑。

4. **视觉检查**
   - 检查截图中的窗口宽度下：
     - 红黄绿按钮与 sidebar 不重叠。
     - sidebar 第一项有稳定顶部留白。
     - 右侧标题和推荐组件不贴标题栏分割线。
   - 检查三页切换不会出现内容跳高。

5. **验证**
   - 编译 Settings 相关 SwiftUI。
   - 跑现有 widget/settings 相关测试，确认数据逻辑未变。
   - app target 构建通过。

### 验证

- `swift test --filter WidgetRecommendation`
- `swift test --filter ProviderCapability`
- `swift test`
- `xcodebuild -project token_hud.xcodeproj -scheme token_hud -destination 'platform=macOS' build`
- 手动验证：
  - 打开 Settings，小组件页不再侵入标题栏。
  - 切换“平台 / 通用”顶部间距一致。
  - 缩小到截图类似宽度时，sidebar 和 detail 不重叠、不裁切。

### 风险

- 自定义 sidebar 会失去少量系统 `NavigationSplitView` 默认行为，例如系统自动 sidebar toggle；但当前窗口是固定设置页，这个取舍可接受。
- 顶部 inset 如果写死过大，会浪费垂直空间；需要控制在只避开 titlebar 的范围。
- `PlatformListView` 内部已有 sidebar/detail 分栏，外层容器不能再额外压缩太多宽度。

### 本轮实现结果（2026-06-08）

- `SettingsWindow` 外层从 `NavigationSplitView + List` 改为自定义 `HStack` 壳：
  - 左侧固定宽度 sidebar。
  - 中间 `Divider`。
  - 右侧 detail 内容区。
- 自定义 sidebar 使用普通 `Button + Label` row，不再依赖系统 sidebar 的标题栏融合样式。
- sidebar 和 detail 都显式使用 `chromeTopInset` 预留顶部安全区，避免内容贴近窗口标题栏/红黄绿按钮区域。
- 小组件页和通用页放入 `ScrollView` detail 容器；平台页保留现有内部双栏，只在外层增加顶部 inset。
- 保留现有三个入口：
  - 小组件
  - 平台
  - 通用

### 验证结果

- `swift test --filter WidgetRecommendation`：通过，4 个测试通过。
- `swift test --filter ProviderCapability`：通过，10 个测试通过。
- `swift test`：通过，146 个测试通过。
- `xcodebuild -project token_hud.xcodeproj -scheme token_hud -destination 'platform=macOS' build`：通过。

### 待手动验证

- 打开 Settings，小组件页 sidebar 不再侵入红黄绿按钮/标题栏区域。
- 右侧“小组件”标题和说明不再贴近顶部分割线。
- 切换“平台 / 通用”，顶部间距应保持一致。
- 缩到截图类似宽度时，sidebar 与 detail 不应重叠或裁切。

---

## 当前重点：启动浮窗旧样式/重叠形状排查（已实现，待手动体验验证）

### 问题

用户反馈：App 一打开时，刘海/浮窗区域仍会出现一个重叠形状，且视觉像旧版浮窗样式，整体很丑。

本轮已阅读：

- `docs/work-log/2026-05-31-notch-collapsed-status.md`
- `docs/work-log/2026-06-04-notch-fusion-rebuild.md`
- `docs/work-log/2026-06-04-notch-policy-cleanup.md`
- `docs/work-log/2026-06-04-notch-compact-pills.md`
- `Overlay/NotchHostPanelManager.swift`
- `Overlay/NotchHostedSurfaceView.swift`
- `Overlay/NotchHostRootView.swift`
- `Overlay/FloatingPanelView.swift`
- `Sources/token_hudCore/NotchGeometryCalculator.swift`

初步排查：

- 旧的 `NotchFusionView` / `NotchCollapsedView` / `NotchExpandedView` / `NotchEarView` 没有继续被引用，问题不像是旧文件直接回流。
- 当前 `detachedWindow` 和 `overlayWindow` 都使用同一个 `NotchHostRootView`，再由全局 `hostState.mode` 决定渲染 `FloatingPanelView` 还是 `NotchHostedSurfaceView`。
- 如果 UserDefaults 中保存的是 `detached`，但保存的 detached frame 实际贴近刘海/顶部区域，启动恢复会直接显示旧 `FloatingPanelView` 样式；现有清理逻辑只判断 `frames.snapZone.contains(candidateTop)`，可能漏掉贴近顶部但 top-center 没落入 snap zone 的坏 frame。
- 如果 UserDefaults 中保存的是 `hosted`，启动会恢复为 collapsed hosted surface；需要确认首帧是否只绘制 `topCap`，没有把 body 或旧浮窗背景露出来。

### 本轮目标

- 定位启动时“旧样式/重叠形状”的具体来源：
  - 是 detached window 被错误恢复到顶部。
  - 还是 overlay hosted surface 首帧绘制不正确。
  - 或者两个 NSPanel 同时可见。
- 修复启动恢复策略：
  - 不允许贴近刘海/菜单栏的 detached frame 以 detached 形态恢复。
  - hosted 启动时只显示新版 collapsed surface，不显示旧浮窗背景/resize grip。
  - 启动阶段确保只有一个窗口可见。
- 保留用户真正拖出来的 detached 浮窗位置，不误删正常桌面区域的自由位置。

### 实施步骤

1. **补充启动恢复诊断**
   - 在 `restoreState()` 增加更明确的日志：
     - saved mode。
     - saved detached frame。
     - 是否判定为 stale/top-near frame。
     - restore 后 detached/overlay 是否可见。
   - 复用现有 `[NotchDiagnostics]` 前缀，方便真机控制台过滤。

2. **收紧 stale detached frame 判定**
   - 新增纯逻辑方法，例如 `NotchGeometryCalculator.isStaleHostedLikeDetachedFrame(...)`。
   - 判定维度不只看 `topCenter in snapZone`：
     - frame 顶部贴近屏幕顶部/菜单栏区域。
     - frame 与 hosted expanded/collapsed 区域有明显交集。
     - frame 宽高接近 hosted surface 或旧 body 形态。
   - 命中后不再恢复 detached frame，改走 hosted collapsed 或默认 detached 安全位置。

3. **修正 restore 状态顺序**
   - 在显示任一窗口前，先明确 `hostState.mode`、`expansionProgress` 和目标 frame。
   - restore hosted 时先 `detachedWindow.orderOut(nil)`，再显示 overlay。
   - restore detached 时先 `overlayWindow.orderOut(nil)`，再显示 detached。
   - 必要时把 detached/overlay root view 拆成带 `WindowRole` 的 root，避免隐藏窗口在状态变化时渲染另一种样式造成首帧残影。

4. **检查 hosted collapsed 首帧绘制**
   - 确认 `NotchHostedSurfaceView` 在 `expansionProgress == 0` 时：
     - body height 为 0 且不可见。
     - 不出现 `FloatingPanelView` 的圆角卡片、阴影、resize grip。
     - top cap 宽度符合 compact 目标。
   - 如果首帧动画从旧 progress 进入，强制 restore 前将 `expansionProgress = 0` 且关闭不必要的隐式动画。

5. **测试覆盖**
   - 增加或更新 `NotchGeometryCalculatorTests`：
     - 顶部附近 detached frame 会被识别为 stale。
     - 正常屏幕中部 detached frame 不会被误判。
     - hosted collapsed layout 在 progress 0 时 body 高度为 0。
   - 如 restore 逻辑可拆成纯函数，补对应单元测试；否则用构建验证和真机日志辅助。

### 验证

- `swift test --filter NotchGeometryCalculator`
- `swift test --filter NotchSurfacePolicyTests`
- `swift test`
- `xcodebuild -project token_hud.xcodeproj -scheme token_hud -destination 'platform=macOS' build`
- 手动验证：
  - 删除/保留不同 UserDefaults 状态启动，观察是否只出现一个窗口。
  - 上次吸附在刘海后重启，启动应是新版 collapsed 状态。
  - 上次拖到桌面中部后重启，启动应恢复正常 detached 浮窗。
  - 不再出现旧 `FloatingPanelView` 样式叠在刘海顶部。

### 风险

- stale frame 判定过宽会误伤用户确实想放在屏幕顶部附近的 detached 浮窗；需要只针对明显贴近刘海/菜单栏和 hosted surface 的 frame。
- SkyLight / publicPanel 的窗口层级差异可能导致真机首帧表现与单元测试不同；需要保留诊断日志用于下一轮定位。
- 如果两个窗口共享 root view 是根因，改动会涉及窗口创建结构，需小心避免破坏拖拽脱离和重新吸附。

### 本轮实现结果（2026-06-08）

- 新增 `NotchGeometryCalculator.shouldDiscardSavedDetachedFrame(...)`：
  - 继续保留旧的 `topCenter in snapZone` 判定。
  - 额外识别贴近 hosted expanded surface 的历史 detached frame。
  - 额外识别贴在菜单栏/刘海 hosted 横向区域的 detached frame。
- `restoreState()` 启动恢复逻辑改为：
  - 打印 saved mode、frames、candidate frame、discard 决策和最终窗口可见性。
  - 如果保存的 detached frame 被判定为 stale/top-near frame，则删除该 saved frame。
  - stale frame 命中时不再恢复默认旧浮窗，而是恢复 hosted collapsed。
  - restore hosted 时先 `detachedWindow.orderOut(nil)`，restore detached 时先 `overlayWindow.orderOut(nil)`，降低两个窗口同时可见风险。
- 新增测试覆盖：
  - 顶部/刘海附近残留 detached frame 即使 top-center 没落入 snapZone，也会被识别为 stale。
  - 正常屏幕中部 detached frame 不会被误删。
- 根因和处理沉淀到 `docs/work-log/2026-06-08-notch-restore-stale-frame.md`。

### 验证结果

- `swift test --filter NotchGeometryCalculator`：通过，47 个测试通过。
- `swift test --filter NotchSurfacePolicyTests`：通过，16 个测试通过。
- `swift test`：通过，146 个测试通过。
- `xcodebuild -project token_hud.xcodeproj -scheme token_hud -destination 'platform=macOS' build`：通过。

### 待手动验证

- 上次把浮窗吸附到刘海后重启：启动应恢复新版 hosted collapsed，而不是旧圆角浮窗卡片。
- 上次拖到桌面中部后重启：仍应恢复正常 detached 浮窗。
- 如果历史保存了贴近顶部的坏 frame，首次启动会自动清理并回到 hosted collapsed；控制台可用 `[NotchDiagnostics] restore` 过滤确认。

---

## 当前重点：Keychain 静默刷新与按平台授权刷新（已实现，待手动体验验证）

### 问题

用户反馈：明明 Settings 已经能显示平台数据，仍然经常弹出 macOS Keychain 权限窗口，要求允许 `token_hud` 读取密钥。

排查确认：

- Settings 显示“有数据”很多来自 `~/.token-hud/state.json` 缓存，不代表当前进程已经获得 Keychain secret 读取权限。
- 后台启动/定时刷新已经走 `allowUserInteraction: false`，理论上不弹系统框。
- 但当前 Settings 里的手动刷新和保存后刷新仍会调用：
  - `PlatformListView.refresh(provider:)`
  - `APIPlatformFetcher.fetchSingle(platform:)`
  - 内部再用 `allowUserInteraction: true` 读取 API key/cookie。
- 因此用户点击刷新、保存凭据后自动刷新、或某些 Settings 操作触发刷新时，macOS 会弹 Keychain 授权框。

### 本轮目标

- 默认所有刷新都先静默读取 Keychain，不弹系统权限窗口。
- 如果某个平台静默读取不到 secret，但 metadata 显示该平台确实配置过凭据，则该平台显示“需要授权刷新”。
- 用户明确点击“授权刷新”时，才允许 `allowUserInteraction: true`，让 macOS 弹一次授权窗口。
- 保存 key/cookie 后不要立刻走允许弹窗的 Keychain 读取；优先：
  - 只刷新 credential snapshot。
  - 或后续单独增加“用刚保存的值立即查询”的路径，本轮先避免保存后自动弹窗。
- UI 粒度按平台展示：哪个平台需要授权，就只在该平台详情和 row 中体现，不全局打扰。

### 实施步骤

1. **增加刷新结果语义**
   - 为 `APIPlatformFetcher.fetchSingle` 增加返回结果，例如：
     - `updated`
     - `noCredential`
     - `needsAuthorization`
     - `noData`
   - 静默读取 secret 失败且 `hasCredential(for:) == true` 时返回 `needsAuthorization`。
   - 保持后台 `fetchAll(allowUserInteraction: false)` 不弹窗。

2. **拆分静默刷新与授权刷新**
   - 新增 `fetchSingle(platform:allowUserInteraction:)` 或等价重载。
   - Settings 普通“刷新”按钮调用 `allowUserInteraction: false`。
   - 新增“授权刷新”按钮调用 `allowUserInteraction: true`。
   - `CodexFetcher` 也按同样思想处理 Codex extras：
     - 普通 Codex 本地 usage 不需要 Keychain。
     - 可选 Admin/API extras 只有授权刷新时才读。

3. **Settings 平台页状态提示**
   - `PlatformListView` 增加 `authorizationNeededPlatformIDs` state。
   - 普通刷新返回 `needsAuthorization` 时，把该平台标记为需要授权。
   - 平台 row 和详情 header 增加小型橙色提示：
     - `需要授权刷新`
   - 详情页在该平台需要授权时显示按钮：
     - `授权刷新`
   - 成功授权刷新后清除该平台的需要授权状态。

4. **保存凭据后不自动弹窗**
   - `onCredentialChanged` 不再直接触发允许交互的刷新。
   - 保存成功后只刷新 snapshot；需要查询时用户点普通刷新，若静默不行再显示授权刷新。

5. **验证**
   - 编译验证 UI。
   - 手动验证：
     - 打开 Settings、切换平台、普通刷新不弹 Keychain 窗口。
     - 对需要授权的平台，普通刷新后出现“需要授权刷新”按钮。
     - 点击“授权刷新”才弹 macOS 授权框。
     - 授权成功后刷新数据，并清除提示。

### 验证

- `swift test --filter ProviderCapability`
- `swift test`
- `xcodebuild -project token_hud.xcodeproj -scheme token_hud -destination 'platform=macOS' build`

### 风险

- 静默读取被系统拒绝时无法区分“真的没有 secret”与“有 secret 但 ACL 不允许静默读取”；本轮用 `hasCredential` metadata 作为判断依据。
- 老的 Keychain item ACL 可能依旧需要用户点一次“始终允许”；本轮只保证这一步发生在明确点击“授权刷新”时。
- 如果保存 key 后不自动查询，用户需要多点一次刷新；这是为避免保存后立即弹权限窗的有意取舍。

### 本轮实现结果（2026-06-08）

- `APIPlatformFetcher.fetchSingle` 改为默认静默刷新，并返回结构化结果：
  - `updated`
  - `noCredential`
  - `needsAuthorization`
  - `noData`
- Settings 平台页普通“刷新”现在调用 `allowUserInteraction: false`，不会主动弹出 macOS Keychain 密码框。
- 仅当静默读取失败、且该平台 metadata 显示已经配置过凭据时，平台 row 和详情页才显示橙色“需要授权刷新 / 需授权”状态。
- 详情页新增“授权刷新”按钮；只有点击这个按钮时才调用 `allowUserInteraction: true`，允许系统弹出 Keychain 授权窗口。
- 保存 API key、Cookie、Claude session key、Codex extras key 后不再自动触发交互式刷新，只刷新 credential snapshot 并提示后续刷新会先静默查询。
- 旧的 Settings 视图中用于展示已保存 key/cookie 的读取改成静默读取或 metadata 检查，避免打开/切换设置页时触发 Keychain 弹窗。
- `SessionKeyExtractor.loadFromKeychain()` 改为静默读取，避免 Claude row 仅展示已保存 session key 时弹窗。

### 验证结果

- `swift test --filter ProviderCapability`：通过，10 个测试通过。
- `swift test`：通过，144 个测试通过。
- `xcodebuild -project token_hud.xcodeproj -scheme token_hud -destination 'platform=macOS' build`：通过。

### 待手动验证

- 打开 Settings、切换平台、查看已配置状态：不应弹 Keychain 密码框。
- 点击普通“刷新”：不应弹 Keychain 密码框。
- 如果某个平台需要 Keychain 授权，普通刷新后应显示“需要授权刷新”。
- 点击“授权刷新”：只对当前平台触发 macOS Keychain 授权框。
- 授权成功后对应平台刷新数据，并清除“需要授权刷新”提示。

---

## 当前重点：Settings 页面适配修复与简化精修（已实现，待手动体验验证）

### 问题

用户截图反馈 Settings 存在两类问题：

- **平台页适配瑕疵**
  - 右侧详情区顶部卡片在当前窗口宽度下横向并排，内容被裁切到标题栏附近。
  - `认证` 与 `查询能力` 两个卡片同时占据首屏横向空间，文字过多、视觉拥挤。
  - 平台列表 row 状态标签偏多，当前选中项面积较大，整体显得重。
- **小组件页过于复杂**
  - 首屏同时展示推荐、预览、刘海收起态、已添加、添加组件，信息层级过多。
  - 推荐卡片过大且多列铺开，已添加/添加组件两块同时出现，操作区占用太高。
  - 刘海收起态配置虽然有用，但默认展开会进一步增加页面复杂度。

本轮已阅读：

- `docs/work-log/2026-05-10-widget-settings-preview.md`
- `docs/work-log/2026-06-07-widget-recommendations-notch-collapsed.md`
- `Settings/WidgetListEditor.swift`
- `Settings/PlatformListView.swift`

### 本轮目标

- 修复平台页横向裁切：
  - 右侧详情改成更稳的单列/自适应布局，避免顶部卡片被窗口宽度挤压。
  - 卡片内部长文案不再把布局撑宽。
- 简化平台页视觉：
  - 顶部只保留平台名、关键状态和刷新。
  - `认证` 作为主卡片，`查询能力` 改成更轻的摘要或折叠说明。
  - 重置操作下沉，避免一进入页面就看到一排危险按钮。
- 简化小组件页：
  - 首屏只保留三个主要区块：
    - 精简推荐条。
    - 当前效果预览。
    - 刘海收起态紧凑配置。
  - `已添加` 和 `添加组件` 合并为一个“管理组件”区域，默认更紧凑。
  - “添加组件”预设不再默认大面积网格铺开，改为轻量横向/折叠入口。
- 保持现有功能不丢：
  - 推荐添加、预览、拖拽排序、自定义组件、刘海左右来源选择都保留。

### 实施步骤

1. **平台页布局改为稳态单列**
   - `PlatformDetailView` 中 `认证 + 查询能力` 的 `HStack` 改为单列或 `ViewThatFits`。
   - `PlatformCapabilityPanel` 改成 compact summary：显示两行关键值，长说明使用更短文案或 `DisclosureGroup`。
   - `PlatformCredentialPanel` 的 GroupBox 保持全宽，内部按钮用 `ViewThatFits` 或换行容器，避免横向溢出。

2. **平台页状态与重置降噪**
   - `PlatformSidebarRow` 状态只保留一个关键 data pill + 一个小认证 dot；减少 row 高度。
   - `PlatformResetPanel` 默认折叠为“重置与清理”，展开后再显示重置按钮。
   - `InfoRow` 的 value 限制宽度并允许中间截断，避免 email/path 撑宽。

3. **小组件推荐区压缩**
   - `ConfiguredWidgetRecommendationPanel` 改为更轻的横向 ScrollView 或最多两行 compact chips。
   - 移除多余副文案，保留标题、缺失数量、补齐按钮。
   - 推荐 chip 减小高度，长指标名截断但不挤压按钮。

4. **小组件管理区合并**
   - 把 `ActiveWidgetsPanel` 和 `AddWidgetsPanel` 合并成一个 `WidgetManagementPanel`：
     - 顶部 segmented / picker 切换“已添加”和“添加”。
     - 默认展示“已添加”，添加预设作为次级 tab。
   - 保留拖拽排序和自定义按钮。

5. **刘海收起态配置压缩**
   - `NotchCollapsedSettingsPanel` 改为 compact：预览 + 两个 picker 一行优先，宽度不够时自动换行。
   - 减少外层卡片感，和预览区视觉统一。

6. **验证**
   - 核心逻辑不应改变，优先编译验证。
   - 运行现有 widget/notch tests，确保配置模型未回归。
   - app 编译后手动检查：
     - 平台页当前窗口宽度下不再裁切。
     - 小组件页首屏明显更简洁，且所有原功能入口仍可找到。

### 验证

- `swift test --filter WidgetRecommendation`
- `swift test --filter NotchCollapsedStatusTests`
- `swift test`
- `xcodebuild -project token_hud.xcodeproj -scheme token_hud -destination 'platform=macOS' build`

### 风险

- 过度折叠可能让新增用户找不到“添加组件”；需要保留清晰的 tab/按钮入口。
- 平台页如果把查询能力压得太轻，用户可能不理解为什么普通 API key 不能查账单；保留短说明和可展开详情。
- 本轮以布局和视觉为主，不改数据模型；如果后续需要更精致的设置架构，可再拆 Settings 子页面。

### 本轮实现结果（2026-06-08）

- 平台页详情从 `认证 + 查询能力` 横向并排改为单列布局，避免右侧卡片在当前窗口宽度下被挤压和裁切。
- 平台页 `查询能力` 改成轻量摘要：
  - 首行只显示当前用量路径。
  - 详细说明放入 `DisclosureGroup`。
- 平台页 `重置` 改为默认折叠的“重置与清理”，危险操作不再占据首屏。
- 平台列表 row 降噪：
  - 保留认证状态点。
  - 只显示一个数据状态 pill，减少 row 高度和标签拥挤。
- `InfoRow` 对 email/path/key 等长字段增加最大宽度、中间截断和缩放，降低撑宽风险。
- 小组件页推荐区从多列大网格改为横向 compact chips：
  - 标题压缩为“推荐组件”。
  - `补齐缺失` 按钮显示缺失数量。
  - chip 只保留核心信息和加号/勾选图标。
- 刘海收起态配置改成 `ViewThatFits` 自适应：
  - 宽度足够时标题、预览、左右 picker 同行。
  - 宽度不足时自动换成两行。
- `已添加` 和 `添加组件` 合并为 `WidgetManagementPanel`：
  - 使用 segmented picker 切换“已添加 / 添加”。
  - 默认展示“已添加”，添加预设作为次级 tab。
  - 保留拖拽排序、自定义组件、点击添加预设能力。

### 验证结果

- `swift test --filter WidgetRecommendation`：通过，4 个测试通过。
- `swift test --filter NotchCollapsedStatusTests`：通过，2 个测试通过。
- `swift test`：通过，144 个测试通过。
- `xcodebuild -project token_hud.xcodeproj -scheme token_hud -destination 'platform=macOS' build`：通过。

### 待手动验证

- Settings → 平台：右侧详情在截图中的窗口宽度下不再裁切到顶部栏，不再出现两列卡片互相挤压。
- Settings → 平台：重置操作默认折叠，查询能力说明可展开。
- Settings → 小组件：首屏只突出推荐、预览、刘海收起态和一个管理区，整体更简洁。
- Settings → 小组件：切换到“添加”后仍可添加预设和打开自定义组件。

---

## 当前重点：MiniMax 普通 API Key 与 Token Plan 查询能力分离（已实现，待手动体验验证）

### 问题

用户当前配置了 MiniMax API token，并期望至少能查询剩余金额。

结合 `docs/model-usage-query-practices.md` 和当前实现，MiniMax 这里有两类凭据：

- **Token Plan key**：可调用官方 `GET https://www.minimax.io/v1/token_plan/remains`，能返回 Token Plan quota / 用量 / Credits。
- **普通 Open Platform API key**：可调用模型或 `/v1/models` 验证 key 是否可用，但目前没有公开稳定的余额查询 API。

当前实现虽然已经把 “no active token plan subscription” 从“查询异常”降级为 `usageUnsupported`，但 UI 仍容易让用户误解：

- “已配置”看起来像已经具备余额/套餐查询能力。
- “暂无数据 / 用量不支持”没有明确说明是普通 key 的能力边界。
- MiniMax 设置里没有把 Token Plan 查询凭据和普通调用 key 的用途分开表达。

### 本轮目标

- MiniMax 普通 API key 验证成功时，显示为“API Key 已连接，但无法查询余额/套餐”，而不是让用户误以为查询失败。
- MiniMax Token Plan remains 成功时，继续展示 quota / credits / 使用率。
- Settings 的 MiniMax 详情页明确区分：
  - Token Plan Key：用于套餐/额度查询。
  - Open Platform API Key：用于模型调用验证，不保证可查余额。
- 小组件推荐逻辑避免在仅有普通 MiniMax key、没有 Token Plan 数据时默认推荐“余额/用量”组件。
- 更新 MiniMax 文档沉淀，记录“普通 API key 不能直接查余额；如需余额，需要后续控制台登录/cookie JSON 路径”。

### 实施步骤

1. **先补失败测试**
   - 在 `ProviderCapabilityTests` 或新增 MiniMax 状态测试中覆盖：
     - MiniMax `/v1/models` 验证成功但无 Token Plan remains 时，应归类为“凭据有效但用量查询不支持”。
     - 该状态不应显示为“查询异常”或“暂无数据”。
   - 在小组件推荐测试中覆盖：
     - 只有 MiniMax 普通 key、无 MiniMax quotas 时，不自动推荐 MiniMax 用量组件。
     - 有 MiniMax quotas 时，才推荐 MiniMax Token / 使用率类组件。

2. **增强状态语义**
   - 复用或扩展 `ProviderQueryError.usageUnsupported` 的表现层文案。
   - 如现有枚举无法表达清楚，可新增更细的 provider-specific detail helper，但不大改 `state.json` 主结构。
   - MiniMax fallback `/v1/models` 成功时写入规范状态，含义是“API Key 可用，但余额/套餐查询无公开接口”。

3. **优化 Settings MiniMax 详情**
   - MiniMax 卡片文案改为：
     - `Token Plan Key`：可查询套餐 remains。
     - `Open Platform API Key`：可验证调用；余额/账单暂不能通过公开 API 查询。
   - 当前数据区遇到 `usageUnsupported` 时，为 MiniMax 显示更具体解释，避免泛用“用量不支持”太模糊。
   - 保留现有保存/重置入口，不在本轮引入不稳定网页抓取。

4. **收紧推荐组件来源**
   - 推荐引擎不要仅凭 MiniMax key 已配置就推荐 MiniMax 用量组件。
   - 推荐 MiniMax 组件的条件改为：
     - state 中已有可展示 MiniMax quota；或
     - 后续明确配置了 Token Plan key。
   - 避免用户普通 key 配置成功后，小组件页自动出现永远没数据的 MiniMax widget。

5. **文档更新**
   - 更新 `docs/model-usage-query-practices.md` MiniMax 段落：
     - ordinary API key 的可用能力是“调用验证”。
     - 余额/账单查询无公开稳定 API。
     - 后续可研究控制台登录 JSON 路径，但不能作为本轮默认方案。

### 验证

- `swift test --filter ProviderCapability`
- `swift test --filter WidgetRecommendation`
- `swift test`
- `xcodebuild -project token_hud.xcodeproj -scheme token_hud -destination 'platform=macOS' build`
- 手动验证：
  - MiniMax 普通 API key 配置后，Settings 显示“API Key 已连接 / 无法查询余额套餐”，不显示“查询异常”。
  - MiniMax 没有 Token Plan 数据时，小组件推荐区不再自动推荐 MiniMax 用量组件。
  - 如果 state 中已有 MiniMax quota，MiniMax 组件仍可被推荐和展示。

### 风险

- MiniMax 可能存在未公开的控制台余额 JSON 接口，但本轮不引入未验证 cookie 抓取，避免把不稳定路径做成主能力。
- 如果用户手里的 token 实际是 Token Plan key，但账户没有 active subscription，UI 会显示“无套餐数据”；这符合后端语义，但需要用户换正确 key 或检查订阅。
- 推荐逻辑依赖 `state.json` 是否已有 quotas，首次配置 Token Plan key 后需要刷新一次才能出现 MiniMax 推荐组件。

### 本轮实现结果（2026-06-08）

- `WidgetRecommendationEngine.recommendations` 新增可选 `state` 参数。
- MiniMax 推荐规则从“只要 Keychain 有 MiniMax API key 就推荐”改为：
  - 只有 `state.json` 中已有 MiniMax quota 证据时，才推荐 MiniMax monthly tokens / usage percent 组件。
  - 仅有普通 Open Platform API key 时，不再自动推荐 MiniMax 用量组件。
- Settings → 小组件页的推荐入口已接入 `watcher.effectiveState`，可以根据当前 MiniMax 数据决定是否展示推荐。
- Settings → 平台页对 MiniMax 的 `usageUnsupported` 显示做了 provider-specific 文案：
  - 状态胶囊显示“无套餐数据”。
  - 当前数据区解释普通 Open Platform API key 只能验证调用，公开接口不能查询余额/套餐。
- MiniMax API key 输入说明改为明确区分 Token Plan key 和普通 Open Platform key。
- `docs/model-usage-query-practices.md` 已补充 MiniMax 普通 key / Token Plan key 的边界和推荐组件规则。

### 验证结果

- `swift test --filter WidgetRecommendation`：通过，4 个 Widget recommendation 测试通过。
- `swift test --filter ProviderCapability`：通过，10 个 ProviderCapability 测试通过。
- `swift test`：通过，144 个测试通过。
- `xcodebuild -project token_hud.xcodeproj -scheme token_hud -destination 'platform=macOS' build`：通过。

### 待手动验证

- Settings → 平台 → MiniMax：普通 Open Platform API key 查询后应显示“无套餐数据”，不再显示“查询异常”或让人误以为可查余额。
- Settings → 小组件：MiniMax 只有普通 key、无 quota 数据时，不应自动出现在推荐组件里。
- 如果后续 MiniMax remains 返回 quota，MiniMax 用量组件应重新出现在推荐区。

---

## 当前重点：优化小组件推荐区表达，避免被误解为状态区（已实现）

### 问题

用户反馈 Settings → 小组件页顶部绿色区域看起来像“状态”，不清楚它有什么用。

实际实现中，这块区域是“已配置平台推荐组件”：

- 根据已配置平台生成可添加的小组件。
- 点击“补齐推荐”会把缺失推荐插入当前小组件列表最前面。

当前问题是视觉表达错误：

- 整块绿色背景让它像平台状态，而不是可添加组件。
- 卡片没有区分“已添加 / 未添加”。
- 没有足够明确的操作提示。
- 已添加的推荐仍然和未添加项长得一样，用户无法判断是否还需要操作。

### 本轮目标

- 把顶部区域从“绿色状态卡”改成“可添加的小组件推荐”。
- 明确每个推荐项的状态：
  - 已添加：灰化/勾选，弱化操作。
  - 未添加：显示清晰的“添加”操作。
- 保留“补齐推荐”能力，但让它成为次级批量操作。
- 减少绿色面积，只保留小型状态点/标签用于表达“来自已配置平台”。
- 不改推荐生成逻辑、不改小组件数据模型、不改刘海收起态配置逻辑。

### 实施步骤

1. **重命名推荐区文案**
   - 标题从“已配置推荐”改为“可添加的小组件推荐”。
   - 副文案说明“来自已配置平台，可加入当前小组件”。

2. **调整推荐区布局**
   - 去掉大面积绿色背景和绿色描边。
   - 使用普通设置页卡片背景。
   - 推荐项改为更轻的 chip / list row。

3. **区分已添加与未添加**
   - 基于 `WidgetConfig.descriptor.semanticKey` 判断推荐是否已存在于当前列表。
   - 已添加：
     - 显示 `已添加` / checkmark。
     - 灰色弱化。
   - 未添加：
     - 显示 `添加` 按钮。
     - 点击后把该推荐插入当前小组件列表最前面。

4. **保留批量补齐**
   - `补齐推荐` 保留在右上角，但文案改为“补齐缺失”。
   - 仅当存在未添加推荐时可点击。

5. **验证**
   - 编译验证 Settings UI。
   - 手动验证：
     - 已添加项不再像可重复添加项。
     - 未添加项可单独添加。
     - “补齐缺失”不会重复添加。

### 验证

- `swift test --filter Widget`
- `xcodebuild -project token_hud.xcodeproj -scheme token_hud -destination 'platform=macOS' build`

### 风险

- 推荐区如果过于弱化，用户可能又找不到“补齐推荐”；需要保留清晰标题和批量按钮。
- 只做 UI 表达，不改变推荐算法，所以平台是否推荐仍沿用上一轮决策。

### 本轮实现结果（2026-06-08）

- 推荐区标题改为“可添加的小组件推荐”，副文案说明来源于已配置平台。
- 去掉大面积绿色背景和绿色描边，改为普通设置页卡片背景。
- 推荐项改为更轻的 row/chip：
  - 已添加项显示 `已添加` 和 checkmark，并弱化为灰色。
  - 未添加项显示独立 `添加` 按钮。
- 点击单个推荐项的“添加”会把该组件插到当前小组件列表最前面。
- 批量按钮文案改为“补齐缺失”，仅当存在未添加推荐时可点击。
- 推荐算法、刘海收起态配置、平台查询逻辑均未改动。

### 验证结果

- `swift test --filter Widget`：通过，34 个 Widget 相关测试通过。
- `xcodebuild -project token_hud.xcodeproj -scheme token_hud -destination 'platform=macOS' build`：通过。

---

## 当前重点：Settings 已配置可见性、小组件默认添加与刘海收起态配置（已实现，待手动体验验证）

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

### 本轮实现结果（2026-06-07）

- 新增 `WidgetDescriptor`、`WidgetRecommendationEngine`、`NotchCollapsedStatusConfiguration`、`NotchCollapsedStatusEngine` 到 core：
  - 已配置平台可生成推荐小组件。
  - 推荐补齐按语义去重。
  - 刘海收起态左右 slot 可分别指定来源，并在来源无数据或组件被删时回退自动值。
- Settings → 平台页：
  - 顶部显示“已配置 N”。
  - 已配置平台排在列表前面，未配置平台保留原相对顺序。
- Settings → 小组件页：
  - 最前面新增“已配置推荐”区域。
  - “补齐推荐”会把缺失推荐组件插到当前小组件列表最前面。
  - 当前小组件列表为空时自动填充已配置平台推荐；没有可推荐项时回退默认组件。
  - 新增“刘海收起态”区域，左右 slot 可分别选择自动、当前小组件或已配置推荐指标，并带 compact 预览。
- 刘海 hosted 收起态：
  - `NotchHostedSurfaceView` 改为读取 `notchCollapsedLeadingSource` / `notchCollapsedTrailingSource`。
  - 左侧进度条和右侧百分比可来自不同指标。
  - 保持原有 compact 小格形态，不扩大触发区或改动 hover 状态机。
- 小组件视觉：
  - 调整 bar/text/status/aggregate 的字号、字重、数字等宽和状态色。
  - Settings 预览区改为更克制的暗色 HUD 背景。
- `xcodegen generate` 在当前机器上写入现有 `.xcodeproj` 时失败，报目标已存在；本轮已手动把新增 Swift 文件加入 `token_hud.xcodeproj/project.pbxproj`。

### 验证结果

- `swift test --filter Widget`：通过，34 个 Widget 相关测试通过。
- `swift test --filter NotchCollapsedStatusTests`：通过，2 个刘海收起态测试通过。
- `swift test`：通过，142 个测试通过。
- `xcodebuild -project token_hud.xcodeproj -scheme token_hud -destination 'platform=macOS' build`：通过。

### 待手动验证

- 打开 Settings → 小组件，确认最前面出现“已配置推荐”。
- 点击“补齐推荐”，确认已配置平台组件插入到当前列表最前面，且重复点击不会产生重复组件。
- Settings → 平台页确认已配置平台排在前面，顶部显示已配置数量。
- 在“刘海收起态”中分别调整左侧/右侧来源，确认刘海收起后内容随配置变化。
- 真机确认小组件新字体和颜色在展开 HUD、Settings 预览、刘海 compact 小格里都自然。

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
