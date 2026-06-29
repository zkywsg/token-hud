# 短期计划

这个文件跟踪当前项目正在进行的实现工作。保持内容小而可执行；可长期保留的决策沉淀到 `docs/`。

## 当前重点：UI 一致性清理 — 进度颜色统一、死代码移除、格式化逻辑去重（待实现）

### 问题

UI 审查发现三类高优先级问题：

1. **进度颜色阈值和 RGB 值不一致** — 6 处独立定义红/黄/绿颜色，阈值和 RGB 均有漂移：
   - `OverlayModelCardStyle.swift`（0.85/0.65）：`(1.0,0.27,0.32)` / `(1.0,0.78,0.22)` / `(0.26,0.82,0.50)`
   - `NotchHostedSurfaceView.swift`（0.85/0.65）：`(1.0,0.27,0.32)` / `(1.0,0.84,0.10)` / `(0.25,0.86,0.48)`
   - `WidgetListEditor.swift`（0.85/0.65）：`(1.0,0.28,0.34)` / `(1.0,0.76,0.20)` / `(0.30,0.86,0.55)`
   - `BarWidget.swift`（0.8/0.5）：`(1.0,0.28,0.34)` / `(1.0,0.76,0.20)` / `(0.30,0.86,0.55)`
   - `StatusWidget.swift`（0.8/0.5）：同 BarWidget
   - `RingWidget.swift`：直接用 `.green/.yellow/.red` 系统色

2. **`PlatformRowView.swift`（1184 行）是死代码** — 该文件包含 `PlatformRowView`、`APIKeyGroupView`、`APIPlatformRow`、`MiMoConsoleConnectorSheet`、`MetricsDetailView` 等，全部没有外部引用，已被 `PlatformListView.swift` 完全取代。

3. **`formattedValue` / `fraction` 逻辑重复** — `OverlayMetricTile`（OverlayModelCardStyle.swift:252-425）和 `WidgetRenderer`（WidgetRenderer.swift:163-161 + 65-160）有几乎完全相同的 `formattedValue`（22 个 case）和 `fraction`（22 个 case）计算逻辑，以及 `quotaFor` / `creditQuota` / `quotaFraction` 辅助函数。新增 metric 时必须两处同步更新，维护风险高。

### 本轮目标

- 统一所有进度条/环形图/状态指示器的红/黄/绿阈值和 RGB 值。
- 删除 `PlatformRowView.swift` 死代码。
- 将 `formattedValue` 和 `fraction` 合并到 `token_hudCore` 的共享函数中，消除跨文件重复。
- 不改数据模型、fetcher、Keychain、刘海窗口状态机、Settings 功能逻辑。

### 实施步骤

1. **新增共享颜色 token**
   - 在 `Sources/token_hudCore` 新增 `ProgressColorScheme.swift`。
   - 定义 `public enum ProgressColorScheme`，提供：
     - `static func color(for usage: Double) -> Color`：统一阈值 0.85 红 / 0.65 黄 / 其它绿。
     - 三个固定的 `Color` 常量：`.red`、`.yellow`、`.green`。
   - 阈值选择 0.85/0.65（当前大多数文件使用此值），RGB 选一组统一值。
   - 添加 Swift Testing 测试覆盖阈值边界。

2. **替换所有内联进度颜色**
   - `OverlayModelCardStyle.swift` `progressColor` → 调用 `ProgressColorScheme.color(for:)`。
   - `NotchHostedSurfaceView.swift` `progressColor(for:)` → 同上。
   - `WidgetListEditor.swift` `progressColor(for:)` → 同上。
   - `BarWidget.swift` `barColor` → 同上（注意 BarWidget 的 fraction 是 remaining，需反转）。
   - `StatusWidget.swift` `color` → 同上。
   - `RingWidget.swift` `ringColor` → 同上（从系统色改为统一 RGB 色）。

3. **提取共享 `formattedValue` 和 `fraction` 到 core**
   - 在 `Sources/token_hudCore/WidgetValueComputer.swift` 新增：
     - `public static func formattedMetricValue(metric: WidgetMetric, service: Service?, configService: String) -> String`
     - `public static func metricFraction(metric: WidgetMetric, service: Service?) -> Double`
   - 内部复用已有的 `formattedRemaining`、`usageFraction`、`formattedCredits` 等。
   - `OverlayMetricTile.formattedValue` / `fraction` 改为调用共享函数。
   - `WidgetRenderer.formattedValue` / `fraction` 改为调用共享函数。
   - `OverlayMetricTile` 和 `WidgetRenderer` 保留各自的 `quotaFor` / `creditQuota` / `quotaFraction` 私有辅助（因为它们依赖各自的 `state` 和 `config`），但核心 switch-case 逻辑只在一处。
   - 统一空值返回：`"-"`（当前 OverlayMetricTile 用 `"-"`，WidgetRenderer 用 `"—"`），统一为 `"-"`。
   - 添加 Swift Testing 测试覆盖主要 metric 的格式化输出和 fraction 计算。

4. **删除 `PlatformRowView.swift`**
   - 确认零外部引用（已确认）。
   - 删除 `token_hud/Settings/PlatformRowView.swift`。
   - 运行 `xcodegen generate` 同步 `.xcodeproj`（如果 xcodegen 失败则手动从 pbxproj 移除）。

5. **验证**
   - 自动验证：
     - `swift test --filter ProgressColorScheme`
     - `swift test --filter WidgetValueComputer`
     - `swift test`
     - `git diff --check`
     - `xcodebuild -project token_hud.xcodeproj -scheme token_hud -destination 'platform=macOS' build`
   - 手动验证：
     - 浮窗 grouped/sectioned 模式进度条颜色一致。
     - Settings 预览区进度条颜色一致。
     - 刘海收起态进度条颜色一致。
     - BarWidget / RingWidget / StatusWidget 颜色与卡片内 tile 一致。
     - 所有 metric 数值显示不变（formattedValue 输出等价）。

### 验证

- 新增 `ProgressColorScheme` 和 `WidgetValueComputer` 扩展的单元测试确保阈值和格式化不回退。
- 全量 `swift test` 确保 core 逻辑不回退。
- app build 确保删除死代码和重构后编译通过。

### 风险

- `formattedValue` 提取到 core 后，OverlayMetricTile 和 WidgetRenderer 的私有 `quotaFor` / `creditQuota` 仍保留在各自文件中；共享函数需要接收 `Service?` 参数而非直接访问私有 state。
- BarWidget 的 fraction 语义是 remaining（bar width = 1 - fraction），颜色需要反转后调用共享函数；实现时要注意语义差异。
- RingWidget 当前用系统 `.green/.yellow/.red`，改为自定义 RGB 后视觉会有轻微变化；这是预期的一致化。
- 删除 `PlatformRowView.swift` 前已确认零引用，风险极低。

### 本轮实现结果（2026-06-28）

- 新增 `ProgressColorScheme`（`token_hud/Overlay/ProgressColorScheme.swift`）：
  - 统一阈值 0.85 红 / 0.65 黄 / 其它绿。
  - 统一 RGB：红 `(1.0,0.28,0.34)`、黄 `(1.0,0.78,0.22)`、绿 `(0.28,0.84,0.52)`。
  - 提供 `color(for:)` 静态方法。
- 替换 6 处内联进度颜色为 `ProgressColorScheme.color(for:)`：
  - `OverlayModelCardStyle.swift` `progressColor`
  - `NotchHostedSurfaceView.swift` `progressColor(for:)`
  - `WidgetListEditor.swift` `progressColor(for:)`
  - `BarWidget.swift` `barColor`（usage = 1 - fraction 反转后调用）
  - `StatusWidget.swift` `color`（阈值从 0.8/0.5 统一到 0.85/0.65）
  - `RingWidget.swift` `ringColor`（从系统色改为统一 RGB）
- 新增 `WidgetMetricComputer`（`token_hud/Widgets/WidgetMetricComputer.swift`）：
  - `formattedValue(metric:service:configService:quotaFor:creditQuota:)`：22 个 case 的格式化逻辑。
  - `fraction(metric:service:quotaFor:creditQuota:quotaFraction:)`：22 个 case 的 usage fraction 计算。
- `WidgetRenderer` 和 `OverlayMetricTile` 的 `formattedValue` / `fraction` 改为调用 `WidgetMetricComputer`，消除跨文件重复。
- 删除 `PlatformRowView.swift`（1184 行死代码）。
- `CodexAuthStatus` 枚举迁移到 `PlatformListView.swift`（唯一使用处）。

### 验证结果

- `swift test`：通过，176 个测试通过。
- `xcodebuild -project token_hud.xcodeproj -scheme token_hud -destination 'platform=macOS' build`：通过，`BUILD SUCCEEDED`。
- `git diff --check`：通过。

### 待手动验证

- 浮窗 grouped/sectioned 模式进度条颜色一致。
- Settings 预览区进度条颜色一致。
- 刘海收起态进度条颜色一致。
- BarWidget / RingWidget / StatusWidget 颜色与卡片内 tile 一致。
- 所有 metric 数值显示不变（formattedValue 输出等价）。

---

## 当前重点：MiMo 凭据输入拆分 — API Key 与 Token Plan Key（待实现）

### 问题

当前 MiMo 的 API Key 和 Token Plan Key 共用同一个输入框和 Keychain 账户（`mimoAPIKey`）。用户输入 `tp-` 或 `sk-` 开头的 key 后，代码通过前缀自动判断类型。这有几个问题：

- 用户无法同时配置两种 key（一个按量、一个套餐）。
- 输入框标签写着「Token Plan / API Key」，语义不清。
- `tp-` key 和 `sk-` key 的用途完全不同，混在一起容易误操作。

### 本轮目标

- 将 MiMo 的 Token Plan Key 和 API Key（按量付费）拆分为两个独立输入框。
- Keychain 存储拆分：`mimoTokenPlanKey` 和 `mimoAPIKey`。
- 自动迁移：如果旧 `mimoAPIKey` 中存的是 `tp-` 开头的 key，自动迁移到新账户。
- fetcher 逻辑不变：cookie 优先 → token plan key → API key 验证。
- 不改其它平台、不改 state.json schema、不改 widget 模型。

### 实施步骤

1. **KeychainHelper 增加 Token Plan Key 存储**
   - 新增 `saveMiMoTokenPlanKey(_:)` / `loadMiMoTokenPlanKey(allowUserInteraction:)` / `hasMiMoTokenPlanKey()` / `deleteMiMoTokenPlanKey()`。
   - Keychain account 为 `"mimoTokenPlanKey"`，与现有 `"mimoAPIKey"` 分开。

2. **ProviderCredentialSnapshot 拆分字段**
   - 新增 `mimoTokenPlanKey: String?` 字段。
   - `miMoAPIKeyRole` 改为只看 `apiKeys["mimo"]`（现在只可能是 `sk-` 或 unknown）。
   - 新增 `hasMiMoTokenPlanKey: Bool`（检查 `mimoTokenPlanKey != nil`）。
   - `hasMiMoTokenPlanCredential` 改为检查 `mimoConsoleCookie != nil || mimoTokenPlanKey != nil`。
   - `maskedMiMoTokenPlanKey` 计算属性。
   - `status(for:)` 的 `.apiKeyAndConsoleCookie` 分支同步更新。

3. **APIPlatformFetcher.fetchMiMo() 调整加载顺序**
   - cookie 优先（不变）。
   - 新增：尝试 `KeychainHelper.loadMiMoTokenPlanKey(allowUserInteraction:)`，有则用 `tp-` key 路径。
   - 最后：尝试 `KeychainHelper.loadAPIKey(for: "mimo", allowUserInteraction:)`，走旧 API key 验证路径。
   - fetchAll 和 hasCredential 同步更新。

4. **PlatformListView UI 拆分**
   - `mimoCredentialContent` 中 `apiKeyContent(platformID:)` 替换为两个独立区域：
     - Token Plan Key 输入框（标签「Token Plan Key」，placeholder `tp-…`）。
     - API Key 输入框（标签「API Key」，placeholder `sk-…`）。
   - 各自保存到对应的 Keychain 账户。
   - `mimoCredentialSummary` 同步更新显示逻辑。
   - 旧 `MiMoAPIKeyRoleStore` 可以简化或移除（角色不再需要猜测）。

5. **自动迁移**
   - 首次加载 credential snapshot 时，如果 `mimoAPIKey` 是 `tp-` 开头且 `mimoTokenPlanKey` 为空，自动迁移到新账户并清空旧账户。
   - 迁移逻辑放在 snapshot 构建处或 AppDelegate 启动时。

6. **验证**
   - `swift test`
   - `xcodebuild -project token_hud.xcodeproj -scheme token_hud -destination 'platform=macOS' build`
   - 手动验证：
     - Settings 平台页 MiMo 区域显示两个独立输入框。
     - 保存 `tp-` key 后能正确显示和查询。
     - 保存 `sk-` key 后能正确显示和验证。
     - 旧的 `tp-` key 自动迁移，不丢失。

### 风险

- 迁移逻辑如果出错，可能让用户需要重新输入 key；迁移前应先检查旧值是否已迁移。
- `ProviderCredentialSnapshot` 加字段后，所有构造调用处都需要更新（`.empty`、Settings 里的构建）。
- 如果用户同时配了 cookie 和 tp- key，fetcher 仍走 cookie 优先；拆分后不影响优先级。

---

## 已完成：修复 hosted 浮窗启动残留与展开裁切（已实现，待手动体验验证）

### 问题

用户最新截图显示，app 一打开就进入异常的半展开/乱码状态：

- hosted 浮窗启动后没有稳定处于 collapsed，仅显示出 expanded 内容残片。
- 再次触摸刘海位置后，展开内容仍然被裁切，顶部和底部都有内容缺失。
- 背后 settings 页面和上方 hosted surface 同时显示，说明不只是视觉卡片问题，而是 hosted 状态与窗口 frame/content layout 没有稳定同步。

本轮系统化排查到的关键风险：

- hosted overlay 的物理 window frame 一直使用 expanded frame，collapsed/expanded 主要靠 `hostState.expansionProgress` 控制视觉显示。
- `restoreState()`、`refreshHostedGeometryAndFrame()`、`screenParametersChanged()`、`hostedLayoutInputsChanged()` 都可能重设 expanded frame；如果重设时 `mode` / `expansionProgress` / hit mask 没有同步，就会出现 collapsed 状态下 expanded 内容残留。
- `windowDidResize(_:)` 在 hosted 模式下直接 `transitionTo(.detached)`，但 hosted frame 高度会随 `expandedBodyHeight` 改变，布局输入变化或系统 reflow 有可能误触发 detached/异常混合状态。
- 当前 `NotchHostedSurfaceView.bodyPanel` 在 collapsed 时仍构造 expanded content，只靠 `rect.height`、`opacity`、`.clipped()`隐藏；如果 body rect 或 progress 在启动时不是严格 0，就会看到内容残片。
- 之前连续围绕 card 宽度/高度做了多轮修补，说明需要先修正 hosted surface 的状态边界，再继续调视觉。

### 本轮目标

- app 启动/恢复 hosted 模式时必须稳定进入 collapsed：
  - `mode == .collapsed`
  - `expansionProgress == 0`
  - 只显示 top cap / info ears，不显示 expanded body 内容残片。
- 触摸刘海后展开必须按完整 body 高度显示内容；如果内容超出，则清晰地纵向滚动，而不是被不可见地裁切。
- hosted window 的系统 resize/reflow 不应误触发 detached 或残留布局。
- 不改 fetcher、Keychain、widget 数据模型和设置页面业务逻辑。

### 实施步骤

1. **补充状态边界测试**
   - 优先在 `Sources/token_hudCore` 增加小策略，避免把 AppKit manager 逻辑写死在不可测试代码里。
   - 覆盖：
     - hosted restore 必须重置 progress 到 0。
     - hosted system resize/reflow 不应被当成用户 detach。
     - expanded body 内容高度不足时必须启用 scrolling 或增高，而不是裁切。

2. **收紧 hosted restore / show 入口**
   - 在 `restoreState()` 和 `toggle()` hosted 分支中集中调用一个 `enterHostedCollapsed(...)` helper。
   - helper 负责：
     - cancel timers / remove expanded-only monitors。
     - `hostState.mode = .collapsed`
     - `hostState.expansionProgress = 0`
     - refresh geometry + set expanded surface frame。
     - apply hosted style + install hover monitor。

3. **隔离系统 resize 与用户 detach**
   - 调整 `windowDidResize(_:)`：
     - hosted 且 `isResettingHostedFrame == true` 时忽略。
     - hosted window 被系统 reflow/布局输入变化触发时，reassert hosted frame，而不是直接 `transitionTo(.detached)`。
     - 只有明确的用户拖拽/resize 行为才走 detach。

4. **防止 collapsed 渲染 expanded content 残片**
   - `NotchHostedSurfaceView.bodyPanel` 在 `opacity` 很低或 `rect.height` 接近 0 时不构造 expanded content。
   - 继续保留 top cap/status slots。
   - 这样即便 SwiftUI 初始 layout 有一帧不同步，也不会把 expanded cards 画出来。

5. **修正展开高度兜底**
   - 复查 `NotchExpandedLayoutPolicy` 的 card-row 估算与真实 grouped 内容。
   - 如果 3 组 7 组件仍会超出，优先让 `expandedAllowsVerticalScrolling = true` 并确保 `ScrollView` 有稳定高度。
   - 必要时把 adaptive 展开高度上限从过低的比例调整到更适合当前纯黑卡片布局，但保留屏幕上限。

6. **记录与验证**
   - 更新本 PLAN 的实现结果。
   - 追加 `docs/work-log/2026-06-22-floating-hud-model-cards.md` 或新建 `2026-06-23-hosted-surface-state.md`，记录这次架构性根因。
   - 自动验证：
     - `swift test --filter NotchSurfacePolicy`
     - `swift test --filter NotchExpandedLayoutPolicy`
     - `swift test`
     - `git diff --check`
     - `xcodebuild -project token_hud.xcodeproj -scheme token_hud -destination 'platform=macOS' build`
   - 手动验证：
     - 退出重开 app，不出现 expanded 内容残片。
     - 鼠标触摸刘海后展开，内容完整显示或可滚动。
     - 离开刘海区域后能稳定自动收起。
     - settings 页面背后不再被异常浮窗遮挡成混合状态。

### 验证

- 这轮必须以状态边界为主，不能继续只调卡片尺寸。
- 自动测试需要覆盖 restore/resize/scrolling 的核心策略；真实 app 截图仍是最终验收依据。

### 风险

- hosted surface 依赖 AppKit window frame + SwiftUI progress 双状态，改动要集中，不要分散打补丁。
- 忽略 hosted resize 过宽可能掩盖真实用户 detach；需要用 `isResettingHostedFrame`、drag state 和 mode 明确区分。
- 如果只隐藏 collapsed expanded content 而不修复状态机，可能掩盖根因；因此必须同步修 restore/resize 边界。

### 本轮实现结果（2026-06-23）

- 新增 `NotchHostedResizePolicy`：
  - hosted frame reset 期间的 resize 直接忽略。
  - hosted 非拖拽 resize/reflow 只 reassert canonical hosted frame。
  - 只有 expanded 且正在拖拽时才允许 detach。
- 新增 `NotchHostedBodyPresentationPolicy`：
  - collapsed 或低透明度阶段不渲染 expanded content，避免启动时出现 card 残片。
- `NotchHostPanelManager` 新增 `enterHostedCollapsed(...)`：
  - `toggle()` hosted 分支和 `restoreState()` hosted 分支统一走同一个 collapsed 入口。
  - 入口会取消 collapse timer、清理 expanded-only monitors、重置 drag 状态、刷新几何、设置 `mode = .collapsed` 和 `expansionProgress = 0`。
- `windowDidResize(_:)` 改为使用 `NotchHostedResizePolicy`，不再把 hosted 的系统 resize/reflow 直接当成 detached。
- `NotchHostedSurfaceView.bodyPanel` 只在 body 高度和 content opacity 达到阈值后构造 expanded content。
- `NotchExpandedLayoutPolicy` adaptive 高度同时考虑 service card rows 和 widget content rows，避免 3 组 7 组件继续按两行卡片低估高度。

### 验证结果

- TDD RED：
  - 新增 hosted resize/body presentation 策略测试先因缺少策略类型失败。
- `swift test --filter NotchSurfacePolicy --filter NotchExpandedLayoutPolicy`：通过，35 个测试通过。
- `swift test`：通过，176 个测试通过。
- `xcodebuild -project token_hud.xcodeproj -scheme token_hud -destination 'platform=macOS' build`：通过，`BUILD SUCCEEDED`。
- `git diff --check`：通过。

### 待手动验证

- 退出重开 app 后 hosted 浮窗应只显示 collapsed top cap / info ears，不再出现 expanded card 残片。
- 再触摸刘海展开时，3 组 7 组件应完整显示或可滚动，不应出现不可见裁切。
- 离开刘海区域后应稳定收起。

## 当前重点：修复 Model Cards 二次排版问题（已实现，待手动体验验证）

### 问题

用户最新截图显示，上一轮 Model Cards 修复仍没有达到预期：

- MiMo 首张卡片顶部像被黑色 top cap 压住，服务名区域不完整。
- DeepSeek 只有 1 个指标，却被拉成整条超宽大黑框，右侧出现大面积空白。
- Codex Plus 卡片在下方被裁切，整体看起来仍像“整行黑盒堆叠”，不是预览中的精致卡片系统。

本轮排查到的根因：

- `GroupedOverlayView` 仍使用纵向 `VStack` 渲染每个服务，`OverlayModelCard` 在父容器里自然撑满整条面板宽度。
- `OverlayMetricGrid` 只解决了 card 内 widget 的排列，没有解决“服务 card 本身”的自适应宽度和多列排列。
- `NotchHostedSurfaceView.bodyPanel` 内容从 body 顶部直接开始，视觉上和上方 top cap 分隔不足，展开后首张卡容易显得被菜单栏黑色区域压住。
- `FloatingPanelView.calculateAdaptiveScale` 仍按旧的 `serviceCount * 32 + 16` 估算 grouped 内容高度，脱离面板缩放时也可能把新 card 布局压得过小。

### 本轮目标

- grouped 浮窗改成“服务卡片网格”，而不是每个服务一张全宽横条卡。
- 单指标服务 card 只占合理宽度，不再撑出大块空黑；多指标服务在 card 内继续用 metric grid。
- hosted 刘海展开面板顶部增加合理内容避让/间距，让首张卡不会贴住或看起来被 top cap 吃掉。
- detached 浮窗也使用同一套 grouped card 估算，避免缩放后再次出现文字/卡片比例失衡。
- 不改数据模型、fetcher、Keychain、刷新逻辑、拖拽吸附状态机。

### 实施步骤

1. **锁定布局根因**
   - 对照 `GroupedOverlayView`、`OverlayModelCardStyle`、`NotchHostedSurfaceView`、`FloatingPanelView` 当前实现。
   - 保留上一轮 `NotchExpandedLayoutPolicy` 的高度兜底，不先回退。

2. **增加服务级 card grid**
   - 在 `OverlayModelCardStyle.swift` 增加服务卡片网格 helper，例如 `OverlayServiceCardGrid`。
   - grouped 模式用 adaptive columns 排列服务 card：
     - 每张服务 card 有合理 min/max width。
     - 面板足够宽时 DeepSeek / MiMo 这类单指标服务可以并排。
     - 面板较窄时自动退回单列。

3. **收紧 card 和 tile 尺寸**
   - 调整 card padding、metric tile min/max width、value/label 字号和 spacing。
   - 目标是减少“大黑盒”感，同时保持长数值不溢出。

4. **修复 hosted 顶部视觉遮挡**
   - 在 `NotchHostedSurfaceView.bodyPanel` 给 expanded content 增加轻量 top inset 或分隔策略。
   - 只调整内容内边距/布局，不破坏 top cap 和 body 的几何融合。

5. **同步 detached panel 自适应缩放**
   - `FloatingPanelView.calculateAdaptiveScale` 改用接近 card grid 的高度估算，而不是旧 row 模型。
   - 防止脱离浮窗放大/缩小时继续把新布局压坏。

6. **记录与验证**
   - 更新本 PLAN 实现结果。
   - 追加 `docs/work-log/2026-06-22-floating-hud-model-cards.md` 的 follow-up，记录这次真正的二次根因。
   - 自动验证：
     - `swift test --filter NotchExpandedLayoutPolicy`
     - `swift test --filter NotchSurfacePolicy`
     - `swift test`
     - `git diff --check`
     - `xcodebuild -project token_hud.xcodeproj -scheme token_hud -destination 'platform=macOS' build`
   - 手动验证：
     - 真实 hosted 浮窗首张 card 不被顶部压住。
     - DeepSeek 单指标 card 不再占满整行。
     - 3 个服务、7 个组件时不出现明显裁切。
     - detached panel 中 grouped card 视觉比例稳定。

### 验证

- 这次修复重点是 SwiftUI 真实布局，自动测试只能覆盖策略不回退；最终必须以真实 app 截图确认。
- 如果可行，优先用现有本地 app 运行后的截图对比当前问题截图。

### 风险

- adaptive grid 在窄面板下仍会退回单列，这是合理降级；不能为了并排继续压缩字体。
- top inset 过大可能让展开面板显得浪费高度，需要控制在小范围。
- 现有工作树已有多轮未提交改动，本轮只改 overlay 布局、detached 缩放估算和相关文档，不回退既有改动。

### 本轮实现结果（2026-06-22）

- `GroupedOverlayView` 从服务 card 的纵向全宽堆叠，改为 `OverlayServiceCardGrid` adaptive card grid。
- `OverlayModelCardStyle` 增加服务卡片 min/max width、hosted body top inset，并收紧 card/tile spacing。
- `OverlayMetricGrid` 对单 widget 服务使用 full-width metric tile，多 widget 继续使用 adaptive grid，减少单指标服务卡右侧空黑。
- `NotchHostedSurfaceView.bodyPanel` 顶部增加轻量内容 inset，降低首张 card 被 top cap 压住的视觉问题。
- `NotchExpandedLayoutPolicy` adaptive 高度从“按服务数堆叠 card”改为“按 card rows”估算。
- `FloatingPanelContentLayoutPolicy` 增加 grouped Model Cards 的 detached 自适应缩放估算，`FloatingPanelView` 不再使用旧的 `serviceCount * 32 + 16`。

### 验证结果

- TDD RED：
  - `FloatingPanelContentLayoutPolicy` 新测试先因缺少 `adaptiveScale` API 失败。
  - `NotchExpandedLayoutPolicy` 新期望锁定 3 个服务时不再按 3 张全宽 card 堆叠估算高度。
- `swift test --filter NotchExpandedLayoutPolicy --filter FloatingPanelContentLayoutPolicy`：通过，7 个测试通过。
- `swift test --filter NotchSurfacePolicy`：通过，25 个测试通过。
- `swift test`：通过，171 个测试通过。
- `xcodebuild -project token_hud.xcodeproj -scheme token_hud -destination 'platform=macOS' build`：通过，`BUILD SUCCEEDED`。
- `git diff --check`：通过。

### 待手动验证

- 真实 hosted 浮窗首张 card 不再被顶部黑色区域压住。
- DeepSeek 这类单指标服务不再占满整行大黑框。
- 3 个服务、7 个组件时不出现明显裁切。
- detached panel 中 grouped card 缩放比例稳定。

## 当前重点：修复 Model Cards 真实浮窗效果偏差（已实现，待手动体验验证）

### 问题

用户截图显示，当前真实浮窗明显没有达到 B 方案预览效果：

- 展开浮窗中卡片内容被裁切，顶部/底部观感像被黑色面板吃掉。
- 单个服务 card 过空、过高，内容没有形成预览中的紧凑指标网格。
- 当前卡片只是把旧 `WidgetRenderer` 塞进新外壳，视觉仍像旧 HUD widget 的残留，而不是 Model Cards。

按系统化排查后的根因：

- `NotchExpandedLayoutPolicy` 仍使用旧 row 模式估算高度：`serviceCount * 32 + padding`。
- 新 Model Cards 每个服务实际需要约 80-100pt，高度估算过低导致 body 高度不足，出现裁切/滚动区不自然。
- `OverlayWidgetFlow` 实际仍是水平 `ScrollView + HStack`，没有实现 spec 里的 compact grid/wrap flow。
- card body 直接渲染旧 `WidgetRenderer`，旧 widget 的尺寸和样式是为横向小 HUD 设计的，不适合卡片内部展示。

### 本轮目标

- 让 B 方案在真实浮窗里接近预览：紧凑、精致、按服务成卡片，不再出现大块空黑和明显裁切。
- adaptive 展开高度按 Model Cards 估算，服务多时优先给足高度，超过屏幕上限再滚动。
- grouped / sectioned card body 使用卡片专用 metric tile：
  - 每个 widget 展示为紧凑指标块。
  - value / label 层级明确。
  - 多个 widget 在 card 内按网格/wrap 排列，而不是一条横向旧 widget 列。
- 保留旧 `WidgetRenderer` 给 compact 模式和其它非 card 场景使用。
- 不改 fetcher、Keychain、刷新支持平台、拖拽/吸附状态机。

### 实施步骤

1. **TDD 锁定高度根因**
   - 修改 `Tests/token_hudCoreTests/NotchExpandedLayoutPolicyTests.swift`。
   - 先新增失败测试：adaptive 模式在 3 个 service 时，body height 应足以容纳多张 Model Cards，不应再接近旧的 116pt。
   - 运行 `swift test --filter NotchExpandedLayoutPolicy`，确认测试先失败。

2. **修复 adaptive 展开高度策略**
   - 修改 `Sources/token_hudCore/NotchExpandedLayoutPolicy.swift`。
   - 引入 Model Cards 估算常量，例如：
     - card base height
     - card spacing
     - vertical padding
   - adaptive 模式用 card count 估算 `idealHeight`。
   - 保持 `maxScreenHeightFraction` 上限和超限滚动逻辑。

3. **新增 card 专用 metric tile**
   - 在 overlay 层新增或扩展局部 helper，例如 `OverlayMetricTile` / `OverlayWidgetGrid`。
   - tile 只负责 Model Cards 里的展示，避免污染通用 `WidgetRenderer`。
   - 从 `WidgetConfig` + `StateFile` 计算 value / label / optional progress。
   - 复用 `WidgetValueComputer` 的格式化逻辑；如 `WidgetRenderer` 里的格式化逻辑需要复用，提取轻量 helper，避免复制过多私有逻辑。

4. **重做 grouped / sectioned card body**
   - `GroupedOverlayView`：
     - card body 改用 `OverlayWidgetGrid`。
     - grid 根据 card 宽度自动排 2-3 列或 wrap。
   - `SectionedOverlayView`：
     - 使用同一 grid。
   - `CompactOverlayContent`：
     - 保持旧 `WidgetRenderer`，不变成 card。

5. **收紧 card 尺寸和视觉**
   - 减小 card padding / spacing 到更接近预览。
   - header 和 body 间距减少。
   - card 背景保持低对比，避免“黑色大空盒”。
   - 刷新按钮保持小，不抢视觉中心。

6. **记录与验证**
   - 更新本 PLAN 的实现结果。
   - 如修复涉及布局策略和跨 overlay helper，更新或新增 work-log。
   - 自动验证：
     - `swift test --filter NotchExpandedLayoutPolicy`
     - `swift test --filter NotchSurfacePolicy`
     - `swift test`
     - `git diff --check`
     - `xcodebuild -project token_hud.xcodeproj -scheme token_hud -destination 'platform=macOS' build`
   - 手动验证：
     - 真实 app 中展开浮窗不再裁切卡片。
     - grouped 三个服务时高度足够，视觉接近预览 B。
     - 多 widget card 内排列紧凑，不是旧横向小 widget 列。
     - detached panel 和 sectioned 模式视觉一致。

### 验证

- 必须先看到新增 `NotchExpandedLayoutPolicy` 测试失败，再实现策略修复。
- 自动测试通过后仍需真实 app 截图确认，因为最终问题是视觉效果偏差。

### 风险

- 如果 card 高度估算过高，浮窗可能过大；需要用屏幕比例上限和滚动兜底。
- 从 `WidgetRenderer` 抽取/复用格式化逻辑时要避免影响 Settings 预览和 compact HUD。
- 卡片专用 metric tile 如果复制太多格式化逻辑，后续维护成本会变高；优先提取小 helper 或复用已有 core 计算。

### 本轮实现结果（2026-06-22）

- 新增 `adaptiveModeReservesEnoughHeightForModelCards()` 测试，先复现旧策略在 3 个 service 时只给 `116pt` 高度的问题。
- `NotchExpandedLayoutPolicy` adaptive 模式改为按 Model Cards 估算展开高度：
  - 每个 service 约一张 card。
  - 保留屏幕高度比例上限。
  - 超过上限时继续启用纵向滚动。
- `OverlayModelCardStyle` 新增 card 内部专用 `OverlayMetricGrid` / `OverlayMetricTile`：
  - card body 不再直接塞旧横向 `WidgetRenderer`。
  - 指标以 value / label / optional progress 的紧凑 tile 展示。
  - grid 使用 adaptive columns，让多个 widget 在卡片里自动排布。
- `GroupedOverlayView` 和 `SectionedOverlayView` 的 card body 改用 `OverlayMetricGrid`。
- `CompactOverlayContent` 仍保留旧 `WidgetRenderer`，不受 card tile 影响。

### 验证结果

- TDD RED：`swift test --filter NotchExpandedLayoutPolicy` 先失败，显示 3 个 service 时 `bodyHeight` 为 `116.0`，不满足 `>= 260`。
- `swift test --filter NotchExpandedLayoutPolicy`：通过，5 个测试通过。
- `swift test --filter NotchSurfacePolicy`：通过，25 个测试通过。
- `swift test`：通过，170 个测试通过。
- `git diff --check`：通过。
- `xcodebuild -project token_hud.xcodeproj -scheme token_hud -destination 'platform=macOS' build`：通过，`BUILD SUCCEEDED`。

### 待手动验证

- 真实 app 中 grouped 展开浮窗不再像截图那样裁切 card。
- DeepSeek / Codex / MiMo 等 card 内部显示紧凑 metric tile，而不是旧横向 widget 列。
- detached panel 与 sectioned 模式视觉一致。
- 长服务名、长指标值、多 widget 情况下不重叠。

## 当前重点：浮窗 Model Cards 视觉优化（已实现，待手动体验验证）

### 问题

用户在浮窗 UI 方案预览中选择了 B：Model Cards。当前浮窗仍然偏“服务名 + 横向 widget 列表”的密集排布：

- 服务名、组件、刷新按钮在同一行里抢横向空间。
- 模型/服务增多时，容易显得拥挤或迫使字体继续变小。
- grouped 和 sectioned 两种展开布局的视觉语言还不够统一。
- 纯黑方向已经确定，但浮窗内部层级还不够精致。

本轮已确认设计文档：

- `docs/superpowers/specs/2026-06-22-floating-hud-model-cards-design.md`

详细实施计划：

- `docs/superpowers/plans/2026-06-22-floating-hud-model-cards.md`

### 本轮目标

- 将 grouped 浮窗从 divider row 改为按服务/模型分组的 compact card。
- sectioned 浮窗保留服务 tab，但当前服务内容使用同一套 card shell。
- compact 浮窗保持紧凑，只同步 spacing 和视觉细节，不引入卡片。
- 刷新按钮继续使用现有 `OverlayServiceRefreshButton`，只调整为更适合 card header 的小圆形控制。
- 不修改数据模型、fetcher、Keychain、刘海几何、拖拽、吸附、展开/收起状态机。

### 实施步骤

1. **新增 overlay 局部样式单元**
   - 新建 `token_hud/Overlay/OverlayModelCardStyle.swift`。
   - 提供 card radius、padding、spacing、card shell、widget flow 等小型 helper。
   - 只依赖 SwiftUI 和现有 overlay 环境值。

2. **重做 grouped 展示**
   - 修改 `GroupedOverlayView`。
   - 移除服务之间的 divider row。
   - 每个服务渲染为一个 `OverlayModelCard`。
   - card header 显示服务名、组件数量、刷新按钮。
   - card body 继续使用现有 `WidgetRenderer`，保留 widget 顺序。

3. **统一 sectioned 展示**
   - 修改 `SectionedOverlayView`。
   - 保留服务 tab。
   - 当前服务内容改用相同的 `OverlayModelCard`。
   - tab 视觉收敛到纯黑 card 系统。

4. **轻量对齐 compact 展示**
   - 修改 `CompactOverlayContent`。
   - 只调整 spacing，不把 compact 模式改成卡片。

5. **记录与验证**
   - 新增 `docs/work-log/2026-06-22-floating-hud-model-cards.md`。
   - 更新本 PLAN 的实现结果。
   - 跑自动测试和 app 编译。

### 验证

- `swift test --filter NotchSurfacePolicy`
- `swift test`
- `git diff --check`
- `xcodebuild -project token_hud.xcodeproj -scheme token_hud -destination 'platform=macOS' build`

手动验证：

- grouped 展开浮窗按服务显示 card，文字稳定不乱缩。
- detached 浮窗 grouped 模式也使用同一视觉语言。
- sectioned 模式当前服务内容与 grouped card 风格一致。
- compact 模式仍保持紧凑。
- 长服务名、长指标值不重叠。
- 刷新按钮仍可用且不会连续弹出 Keychain 授权框。

### 风险

- 卡片背景和描边如果太重，会从“精致分组”变成“卡片堆叠”；实现时要保持低对比。
- card 化会增加垂直高度，需依赖现有动态高度/滚动策略，不通过继续压缩核心字体解决。
- 当前工作树已有多轮未提交改动，本轮只改 overlay 视觉和文档，不回退既有修复。

### 本轮实现结果（2026-06-22）

- 新增 `OverlayModelCardStyle`、`OverlayModelCard`、`OverlayWidgetFlow`，作为浮窗 Model Cards 的局部视觉 helper。
- `GroupedOverlayView` 从 divider row 改为 service/model cards。
- `SectionedOverlayView` 使用同一套 card shell 和 widget flow。
- `CompactOverlayContent` 只对齐 spacing，不引入卡片。
- `OverlayServiceRefreshButton` 视觉上收敛为小型 card header control，刷新行为不变。
- 已运行 `xcodegen generate`，让新增 helper 加入 app target。

### 验证结果

- `swift test --filter NotchSurfacePolicy`：通过，25 个测试通过。
- `swift test`：通过，169 个测试通过。
- `git diff --check`：通过。
- `xcodebuild -project token_hud.xcodeproj -scheme token_hud -destination 'platform=macOS' build`：通过，`BUILD SUCCEEDED`。

### 待手动验证

- grouped 展开浮窗按服务显示 card，文字稳定不乱缩。
- detached 浮窗 grouped 模式也使用同一视觉语言。
- sectioned 模式当前服务内容与 grouped card 风格一致。
- compact 模式仍保持紧凑。
- 长服务名、长指标值不重叠。
- 刷新按钮仍可用且不会连续弹出 Keychain 授权框。

## 当前重点：浮窗服务级刷新按钮（已实现，待手动体验验证）

### 问题

用户希望在浮窗上增加一个小刷新按钮，用于对当前查看的内容进行刷新。当前浮窗只能展示 `StateWatcher` 读到的 state 数据，手动刷新入口主要在 Settings 平台页：

- `CodexFetcher` 支持刷新 Codex 本地/套餐数据。
- `APIPlatformFetcher.fetchSingle(platform:allowUserInteraction:)` 支持刷新 DeepSeek、MiniMax、MiMo 等 API/控制台数据。
- `StateWatcher.readNow()` 能在刷新落盘后重新读取 `state.json`。
- 但 `NotchHostRootView` / `FloatingPanelView` / `NotchHostedSurfaceView` 当前没有注入 `CodexFetcher` 和 `APIPlatformFetcher`，overlay 内部没有刷新入口。

本轮理解为：在浮窗的每个服务/分组行旁边增加一个小刷新按钮，点击后只刷新对应服务，而不是刷新全部。

### 本轮目标

- 在浮窗 grouped / sectioned 展示里，为每个可刷新的服务增加一个小的 icon-only refresh button。
- 点击按钮后刷新对应服务：
  - `codex`：调用 `CodexFetcher.fetch(allowUserInteraction: false)`。
  - API 平台：调用 `APIPlatformFetcher.fetchSingle(platform:allowUserInteraction: false)`。
  - 刷新完成后调用 `StateWatcher.readNow()`。
- 默认走静默刷新，不在浮窗里直接触发 Keychain 授权弹窗。
- 如果平台需要授权读取真实 secret，则不在浮窗连续弹窗；后续仍通过 Settings 的“授权刷新”入口处理。
- 保持按钮小、克制，不破坏纯黑 Compact Pro 的浮窗视觉。

### 实施步骤

1. **把刷新依赖注入 overlay**
   - 修改 `NotchHostPanelManager` 初始化参数，增加：
     - `CodexFetcher`
     - `APIPlatformFetcher`
   - `AppDelegate` 创建 `NotchHostPanelManager` 时传入这两个对象。
   - `makeWindow` 里给 `NotchHostRootView` 注入对应 environment。

2. **新增浮窗刷新 action**
   - 在 overlay SwiftUI 层新增小 helper：
     - 根据 service id 判断刷新方式。
     - 使用 `@State` 跟踪当前正在刷新的 service ids。
     - 刷新中显示小 `ProgressView` 或旋转态图标。
   - 不把刷新状态写入 core 数据模型。

3. **在 grouped / sectioned 行加入按钮**
   - `GroupedOverlayView`：
     - 在服务名旁边或右侧加入 icon-only refresh button。
     - 只占很小宽度，不挤压 widget 横向滚动区。
   - `SectionedOverlayView`：
     - 在当前 service 标题旁边加入 refresh button。
   - `CompactOverlayContent`：
     - 本轮先不加逐 widget 按钮，因为 compact 模式没有稳定服务行，直接加会显著拥挤。

4. **刷新行为边界**
   - 不支持刷新的服务不显示按钮，或按钮 disabled。
   - `claude` 当前没有实现可安全静默刷新的 fetcher，本轮不显示刷新按钮。
   - `openai`、`anthropic`、`gemini` 目前只是 API key 状态/unsupported usage，按钮可不显示，避免给用户错误预期。
   - `deepseek`、`minimax`、`mimo`、`codex` 优先支持。

5. **验证**
   - 自动验证：
     - `swift test`
     - `xcodebuild -project token_hud.xcodeproj -scheme token_hud -destination 'platform=macOS' build`
     - `git diff --check`
   - 手动验证：
     - grouped 浮窗中每个支持服务旁边有小刷新按钮。
     - sectioned 模式当前服务标题旁有小刷新按钮。
     - 点击 Codex / DeepSeek / MiniMax / MiMo 刷新按钮后，按钮有短暂 loading 状态，数据刷新后更新显示。
     - 不因点击浮窗刷新按钮弹出 Keychain 连续授权框。

### 验证

- 自动测试主要保证现有 core 和 app target 编译不回退。
- 刷新按钮的真实数据更新需要手动验证，因为涉及本地 auth、Keychain 和网络。

### 风险

- 浮窗空间很小，按钮如果太明显会破坏 HUD 的轻量感；本轮使用 icon-only 小按钮。
- API 平台静默刷新如果遇到 Keychain 需要授权，会返回 needsAuthorization；浮窗不直接弹窗，用户可能需要去 Settings 授权刷新。
- 当前工作树已有多轮未提交改动，本轮只叠加浮窗刷新入口，不回退视觉、Keychain 和刘海几何改动。

### 本轮实现结果（2026-06-20）

- `NotchHostPanelManager` 新增 `CodexFetcher` 和 `APIPlatformFetcher` 依赖，并通过 environment 注入浮窗根视图。
- `AppDelegate` 创建浮窗管理器时传入现有 fetcher 实例，避免 overlay 内部重新创建数据刷新对象。
- `GroupedOverlayView` 在每个支持刷新的服务名旁增加小型 icon-only 刷新按钮。
- `SectionedOverlayView` 在当前服务标题旁增加相同的刷新按钮。
- 新增 `OverlayServiceRefreshButton`：
  - 支持 `codex`、`deepseek`、`minimax`、`mimo`。
  - 刷新中显示小 loading 状态，避免重复点击并发刷新。
  - 刷新完成后调用 `StateWatcher.readNow()`，让浮窗重新读取落盘后的状态。
  - 使用 `allowUserInteraction: false` 静默刷新，避免从浮窗触发连续 Keychain 授权弹窗。
- 暂不为 `claude`、`openai`、`anthropic`、`gemini` 显示按钮，避免给用户错误的“可直接刷新用量”预期。

### 验证结果

- `swift test --filter KeychainAccessPolicy`：通过，2 个测试通过。
- `swift test --filter NotchSurfacePolicy`：通过，25 个测试通过。
- `swift test`：通过，169 个测试通过。
- `git diff --check`：通过。
- `xcodebuild -project token_hud.xcodeproj -scheme token_hud -destination 'platform=macOS' build`：通过，`BUILD SUCCEEDED`。

### 待手动验证

- grouped 浮窗中 Codex / DeepSeek / MiniMax / MiMo 服务名旁出现小刷新按钮。
- sectioned 浮窗当前服务标题旁出现小刷新按钮。
- 点击刷新后按钮有短暂 loading 状态，完成后浮窗数据能更新。
- 点击浮窗刷新按钮不会连续弹出 Keychain 授权框；需要授权的平台仍通过 Settings 处理。

## 当前重点：Keychain 授权弹窗降噪（已实现，待手动体验验证）

### 问题

用户反馈 Settings 小组件页总是弹出系统 Keychain 授权框：

- 弹窗内容是 `token_hud` 想使用钥匙串 `com.tokenHud.sessionKey` 中的机密信息。
- 截图出现在小组件页，说明即使当前没有主动刷新 Claude，也可能因为 UI 状态计算触发 Keychain 访问。
- 历史记录 `docs/work-log/2026-06-06-settings-keychain-popup.md` 已确认过同类根因：SwiftUI 渲染或页面刷新路径里频繁访问 Keychain，会导致系统连续弹授权。

本轮重新排查后，当前代码已经基本避免在 UI body 里读取 secret data，但 `KeychainHelper.hasClaudeSessionKey()` / `hasAPIKey(...)` / `hasMiMoConsoleCookie()` / `hasCodexAdminKey()` 的存在性查询仍然没有显式禁止用户交互。对于旧签名或 ACL 需要确认的 Keychain item，哪怕只是状态检查，也可能触发系统授权弹窗。

更细的调用链：

- `SettingsWindow` 的小组件页会挂载 `WidgetListEditor()`。
- `WidgetListEditor.task` 会调用 `reloadCredentialSnapshot()`。
- `reloadCredentialSnapshot()` 会调用：
  - `KeychainHelper.hasClaudeSessionKey()`
  - `KeychainHelper.hasAPIKey(for:)`
  - `KeychainHelper.hasMiMoConsoleCookie()`
  - `KeychainHelper.hasCodexAdminKey()`
- 平台页 `PlatformListView.task` 也有一套相同的 `reloadCredentialSnapshot()`。
- 当前 `has...` 最终进入 `KeychainHelper.exists(account:)`，这个查询没有设置 `LAContext.interactionNotAllowed = true`。

为什么会“拒绝后还连续弹”：

- 每一次 `SecItemCopyMatching` 都是一次独立的 Keychain 访问请求。
- 用户点“拒绝”只是拒绝当前这一次访问，不会让 app 后续所有访问自动静默失败。
- 小组件页和平台页会在页面创建、切换、保存凭据后重新生成快照；如果一次快照里多个 `has...` 或多次页面重建都触发 Keychain 交互，就会表现为连续弹窗。
- 开发环境里 app 频繁重编译后，Keychain item 的 ACL/代码签名信任关系也可能不稳定；理论上“始终允许”能减少弹窗，但不应该要求用户靠它解决普通 UI 浏览问题。

### 本轮目标

- 让“是否已配置”的 Keychain 状态检查静默执行，不弹系统授权框。
- Settings 小组件页、平台页、推荐组件刷新快照时，不因为检查 Claude session key 或其它凭据存在性而弹窗。
- 保留用户主动操作时的授权能力：
  - 手动保存凭据。
  - 用户主动刷新需要真实 API key/cookie 的平台。
  - 用户主动提取 Claude session key。
- 不改变 Keychain service/account 名称，不迁移或删除用户已有凭据。

### 实施步骤

1. **修复 Keychain 存在性查询**
   - 修改 `KeychainHelper.exists(account:)`：
     - 使用 `LAContext` 并设置 `interactionNotAllowed = true`。
     - 设置 `kSecUseAuthenticationContext`，禁止 `SecItemCopyMatching` 弹出授权 UI。
     - 对 `errSecInteractionNotAllowed` 做降级处理，避免因为旧 ACL 项直接弹窗。

2. **收紧调用语义**
   - 保持 `hasClaudeSessionKey()` 等 `has...` API 作为静默状态检查入口。
   - 保持 `load(... allowUserInteraction:)` 的语义：
     - UI 快照/预览使用 `allowUserInteraction: false`。
     - 用户主动刷新网络数据时才可传 `true`。

3. **复核残留读取路径**
   - 确认 `WidgetListEditor.reloadCredentialSnapshot()` 只调用静默 `has...`。
   - 确认 `PlatformListView.reloadCredentialSnapshot()` 只调用静默 `has...`。
   - 保留 `SessionKeyExtractor.loadFromKeychain()` 的非交互读取，不把它放入频繁渲染路径。

4. **验证**
   - 静态检查：
     - `rg "KeychainHelper\\.load\\(" token_hud`
     - `rg "hasClaudeSessionKey|hasAPIKey|hasMiMoConsoleCookie|hasCodexAdminKey" token_hud`
   - 自动验证：
     - `swift test`
     - `xcodebuild -project token_hud.xcodeproj -scheme token_hud -destination 'platform=macOS' build`
     - `git diff --check`
   - 手动验证：
     - 打开 Settings 小组件页不再弹 Claude session key 授权框。
     - 切换 Settings 页面、重复进入小组件页不连续弹窗。
     - 手动刷新需要真实密钥的平台时，仍能在必要时触发授权。

### 验证

- 自动测试覆盖编译和核心逻辑不回退。
- 这个问题的最终判断依赖 macOS Keychain 真机行为，需要用户在真实 app 中验证弹窗频率。

### 风险

- 对 `errSecInteractionNotAllowed` 的降级如果处理过于保守，UI 可能把已有旧凭据显示为未配置；如果处理过于宽松，可能把需要授权但无法读取的旧凭据显示为已配置。
- 本轮优先目标是“不在普通 UI 浏览时弹窗”；旧 Keychain item 第一次主动读取真实 secret 时，macOS 仍可能弹一次，这是系统权限模型的一部分。
- 当前工作树已有多轮未提交改动，本轮只修改 Keychain 静默查询相关逻辑，不回退视觉和刘海窗口改动。

### 本轮实现结果（2026-06-20）

- 新增 `KeychainAccessPolicy`：
  - `.statusCheck` 永远不允许用户交互。
  - `.secretRead(allowUserInteraction:)` 严格遵循调用方传入的授权意图。
- 新增 `KeychainAccessPolicyTests`：
  - 覆盖状态检查不允许弹窗。
  - 覆盖真实 secret 读取只在显式允许时才可交互。
- `KeychainHelper.load(account:allowUserInteraction:)`：
  - 改为通过 `KeychainAccessPolicy` 判断是否设置非交互 `LAContext`。
- `KeychainHelper.exists(account:)`：
  - 改为 `var query`，并在状态检查中设置 `LAContext.interactionNotAllowed = true`。
  - 所有 `hasClaudeSessionKey()` / `hasAPIKey(...)` / `hasMiMoConsoleCookie()` / `hasCodexAdminKey()` 都走非交互查询。
- 保留用户主动读取 secret 的能力：
  - `allowUserInteraction: true` 的刷新/读取路径仍可触发系统授权。
  - 普通 UI 快照和推荐组件状态检查不应再触发授权框。
- 已沉淀 work-log：
  - `docs/work-log/2026-06-20-keychain-status-check-silent.md`

### 验证结果

- TDD RED：`swift test --filter KeychainAccessPolicy` 先因缺少 `KeychainAccessPolicy` 失败，符合预期。
- `swift test --filter KeychainAccessPolicy`：通过，2 个测试通过。
- `swift test`：通过，169 个测试通过。
- `xcodebuild -project token_hud.xcodeproj -scheme token_hud -destination 'platform=macOS' build`：通过。
- 静态扫描已确认：
  - Settings 小组件页和平台页的 credential snapshot 使用 `has...` 状态检查。
  - 当前挂载的 `SettingsWindow` 未使用旧 `PlatformRowView` / `ServiceConfigView`。

### 待手动验证

- 打开 Settings 小组件页不再连续弹出 Claude session key Keychain 授权框。
- 点击“拒绝”后，页面重建或切换 Settings tab 不再连续重复弹。
- 用户主动授权刷新需要真实 key/cookie 的平台时，系统仍能按需弹授权。

## 当前重点：Pure Black Compact Pro 视觉系统（已实现，待手动体验验证）

### 问题

用户在纯黑方向预览中选择了 C：Compact Pro。上一版 Dynamic Island 磨砂方案仍然存在几个问题：

- 用户已明确希望 UI 方向改为纯黑，不再使用透明或磨砂背板。
- 顶部 HUD、Settings 小组件页、当前效果区的视觉语言还不够统一，部分区域有蓝灰、半透明、纯黑大块混用的问题。
- 当前效果区和推荐区的信息密度、圆角、字重、描边层级不够精致，容易显得粗糙。
- 当模型或组件数量变多时，需要保持高度可变，但字体层级不能被压得越来越小。

### 本轮目标

- 按 C 方向建立纯黑 Compact Pro 基础版：
  - 主背板使用纯黑或接近纯黑实色。
  - 不再用透明、磨砂或渐变作为主要面板质感。
  - 用更准确的字重、字号、间距、hairline 和状态色建立精致感。
- 统一顶部 hosted HUD、Settings 小组件页、推荐组件、当前效果区的视觉语言。
- 收敛圆角和卡片层级，减少卡片套卡片、大块空黑和视觉割裂。
- 保持现有数据模型、拖拽、吸附、hover、动态高度、分组和排序功能不变。
- 为后续主题色、背景色、风格扩展保留空间，但本轮不做完整主题系统。

### 实施步骤

1. **沉淀纯黑视觉规则**
   - 在 SwiftUI 层使用局部 helper 或常量统一：
     - 纯黑/近黑实色背景。
     - hairline 描边透明度。
     - 主/次/弱文字透明度。
     - 8-10pt 紧凑卡片圆角。
   - 移除本轮涉及面板里的 `.thinMaterial`、`.regularMaterial`、`.ultraThinMaterial` 主背景用法。

2. **重做 hosted 顶部 HUD 视觉**
   - 调整 `NotchHostedSurfaceView`：
     - top cap 和 body 改为纯黑实色体系。
     - 保留刘海融合轮廓，但减少大面积空黑和粗糙边界。
     - 左右状态区继续保留有用信息，但不再使用磨砂胶囊贴片感。
     - 固定核心字号层级，避免展开高度变化时文字继续被压小。

3. **统一 Settings 小组件页**
   - 调整 `WidgetListEditor`：
     - 推荐组件、当前效果、已添加组件、添加组件区域改为纯黑 Compact Pro 样式。
     - 当前效果继续按模型分组，优化组标题、数量、组件 chip 和删除按钮的层级。
     - 收敛圆角、描边和内边距，减少嵌套卡片感。
   - 调整 `SettingsWindow`：
     - 侧边栏和详情区从磨砂/蓝灰转为纯黑或近黑实色。
     - 保持选中态清晰，但减少大面积高透明色块。

4. **处理溢出和重复操作风险**
   - 复核服务名、模型名、组件名、按钮文案、数量文案的截断和换行。
   - 确保窄窗口和组件增多时不会横向撑破。
   - 不改窗口几何和动画策略，只确保视觉层不会因高度变化造成文字异常缩放。

5. **验证**
   - 自动验证：
     - `swift test --filter NotchSurfacePolicy`
     - `swift test --filter NotchGeometryCalculator`
     - `swift test`
     - `xcodebuild -project token_hud.xcodeproj -scheme token_hud -destination 'platform=macOS' build`
     - `git diff --check`
   - 手动验证：
     - 刘海收起、展开、再次展开后仍贴合且排版稳定。
     - Settings 小组件页整体为纯黑 Compact Pro 风格。
     - 当前效果区长文本、模型多、组件多时不溢出。
     - 窄窗口下按钮、标题和 chip 不重叠。

### 验证

- 自动测试主要保证核心策略和 app 编译不回退。
- 视觉结果必须通过真实 app 手动验证，重点看纯黑是否足够精致、字体是否稳定、当前效果区是否清爽。

### 风险

- 纯黑方案如果只改颜色，可能会显得过平；必须同步调整字重、间距、描边和信息层级。
- 紧凑布局如果压得过猛，可能牺牲可读性；核心数字和状态仍需留足最小空间。
- 当前工作树已有多轮未提交改动，本轮只叠加视觉系统改动，不回退既有几何、拖拽、高度和权限弹窗相关修复。

### 本轮实现结果（2026-06-20）

- `NotchHostedSurfaceView`：
  - top cap 和 expanded body 主背景改为 `Color.black` 实色。
  - 移除主面板 `.thinMaterial`、`.regularMaterial` 和渐变高光。
  - 左右信息耳朵保留低调可见状态，但改为纯黑体系下的轻描边/轻底色。
- `FloatingPanelView`：
  - 独立浮窗外壳改为纯黑实色，避免从刘海拖出后与 Compact Pro 方向割裂。
- `WidgetListEditor`：
  - 新增局部 `CompactBlackTheme` 和 `compactBlackPanel`，统一小组件页近黑面板、inset 背景、hairline。
  - 推荐组件、刘海收起态配置、当前效果、组件 chip、已添加列表、添加预设卡片改为纯黑 Compact Pro 视觉。
  - 当前效果区继续按模型/服务分组，并保留删除按钮；列表区从 bordered list 改为黑色 plain list。
- `SettingsWindow`：
  - 主窗口、详情区和侧边栏改为纯黑/近黑实色。
  - 移除 Settings 主背景 `.regularMaterial` 和渐变。
  - 侧边栏选中态改为更克制的低透明白色块，保留左侧 accent 指示条。
- 已沉淀设计记录：
  - `docs/superpowers/specs/2026-06-20-pure-black-compact-pro-design.md`

### 验证结果

- `swift test --filter NotchSurfacePolicy`：通过，25 个测试通过。
- `swift test --filter NotchGeometryCalculator`：通过，53 个测试通过。
- `swift test`：通过，167 个测试通过。
- `xcodebuild -project token_hud.xcodeproj -scheme token_hud -destination 'platform=macOS' build`：通过。
- `git diff --check`：通过。

### 待手动验证

- 真实 app 中顶部 HUD 收起、展开、再次展开后是否仍贴合刘海且纯黑质感稳定。
- Settings 小组件页整体是否足够简洁精致，当前效果区是否比上一版更统一。
- 模型/组件变多、窗口缩窄时是否无文字溢出、按钮重叠或排版拥挤。

## 当前重点：Dynamic Island 一体化视觉系统（已被 Pure Black Compact Pro 方向取代，保留记录）

### 问题

用户在预览中选择了 B：Dynamic Island 一体化。当前真实 UI 的主要问题是视觉语言不统一：

- 顶部刘海浮窗仍偏“黑色矩形面板”，左右信息耳朵像额外贴上的胶囊。
- 设置页主体是蓝灰磨砂，当前效果预览又是纯黑大块，和顶部浮窗割裂。
- 推荐组件、当前效果、侧边栏、顶部 HUD 的圆角、描边、透明度和字重层级不一致。
- 分割线和卡片边界偏硬，整体不够精致。

### 本轮目标

- 按 B 方向建立统一的 Dynamic Island 一体化视觉：
  - 顶部刘海浮窗更像一个连续岛体。
  - 左右状态区融入 top cap，不再像独立小胶囊。
  - body 和 top cap 使用同一套深色半透明磨砂质感。
  - 设置页、小组件推荐区、当前效果区同步使用更圆润、半透明、低边框的岛状语言。
- 减少大面积纯黑和硬分割线。
- 保持现有信息密度、拖拽、hover、动态高度、分组切换和数据模型不变。

### 实施步骤

1. **沉淀共享视觉参数**
   - 在 SwiftUI 层增加轻量视觉 helper 或局部常量，统一：
     - 深色磨砂底色透明度。
     - 描边透明度。
     - 主/次/弱文字透明度。
     - 岛状圆角和卡片圆角。
   - 不新增外部依赖，不做全局主题大重构。

2. **重做 hosted 顶部岛体视觉**
   - 调整 `NotchHostedSurfaceView`：
     - top cap 和 body 更像连续岛体，减少纯黑矩形感。
     - 左右状态槽去掉“贴片”感，改成嵌入式状态区。
     - 弱化横向硬分割线，用更轻的 hairline 或间距表达行组。
     - 保留现有动态高度、顶部锚定和信息耳朵降级策略。

3. **统一 Settings 小组件页**
   - 调整小组件页面相关视图：
     - 推荐组件卡片、当前效果预览和外层面板使用同一套磨砂岛状样式。
     - 当前效果不再是纯黑大块，改为与 HUD 一致的半透明深色预览区。
     - 减少嵌套卡片边界，统一按钮和 header action 的圆角、背景和文字层级。
   - 保持 Settings 结构和功能不变。

4. **处理溢出和一致性**
   - 复核小组件页长文本、服务名、计数文案、按钮文案的截断/换行。
   - 保证窄窗口下不会横向撑破。
   - 避免卡片套卡片视觉过重。

5. **验证**
   - 自动验证：
     - `swift test --filter NotchSurfacePolicy`
     - `swift test --filter NotchGeometryCalculator`
     - `swift test`
     - `xcodebuild -project token_hud.xcodeproj -scheme token_hud -destination 'platform=macOS' build`
     - `git diff --check`
   - 手动验证：
     - 刘海收起、展开、再次展开视觉连续。
     - 展开态 top cap/body 像一个岛体，不再像黑色矩形。
     - Settings 小组件页推荐区和当前效果区风格统一。
     - 缩窄 Settings window 后无文字重叠或横向溢出。

### 验证

- 自动测试主要保证核心策略和 build 不回退。
- 视觉结果必须通过真实 app 手动验证，尤其是透明磨砂在 macOS 背景下的表现。

### 风险

- 如果 top cap 过圆或过浅，可能削弱和物理刘海的融合感。
- 如果 Settings 视觉一次性改太多，可能影响其它页面一致性；本轮优先聚焦小组件页和当前效果区。
- 当前工作树已有多轮未提交改动，本轮只叠加视觉统一改动，不回退已有几何、拖拽和高度策略修复。

### 本轮实现结果（2026-06-19）

- `NotchHostedSurfaceView`：
  - top cap 和 body 使用更接近的深色磨砂覆盖、高光和描边。
  - 展开态左右状态槽降低贴片感，信息更像嵌在 top cap 内部。
  - body 阴影和高光调整为更连续的岛体视觉。
- `WidgetListEditor`：
  - 新增局部 `islandPanel` 样式 helper，统一小组件页主要面板。
  - 推荐组件、刘海收起态配置、当前效果预览、已添加/添加区域改为更圆润的半透明磨砂样式。
  - 当前效果预览从纯黑块改为深色磨砂岛状预览区。
  - 推荐 chip、预设卡片和 preview item 统一 14pt 圆角和轻描边。
- `SettingsWindow`：
  - 轻调背景、分隔线、侧边栏选中态圆角和透明度，使 Settings 与小组件页视觉更一致。
- 已沉淀 work-log：
  - `docs/work-log/2026-06-19-dynamic-island-visual-system.md`

### 验证结果

- `swift test --filter NotchSurfacePolicy`：通过，25 个测试通过。
- `swift test`：通过，167 个测试通过。
- `xcodebuild -project token_hud.xcodeproj -scheme token_hud -destination 'platform=macOS' build`：通过。
- `git diff --check`：通过。

### 待手动验证

- 展开态 HUD 是否像连续岛体，而不是黑色矩形和小胶囊的拼接。
- Settings 小组件页推荐区、当前效果区、刘海收起态配置区风格是否统一。
- 缩窄 Settings window 后是否没有文本溢出或按钮拥挤。

## 当前重点：刘海展开态信息耳朵优化（已实现，待手动体验验证）

### 问题

用户反馈：浮窗从刘海放大后，刘海左右两端位置是纯黑状态，看起来很空、很丑。此前展开态为了突出正文内容，会让左右 `statusSlot` 随 `contentOpacity` 淡出，结果展开完成后顶部两端只剩黑色 top cap，没有信息层次。

本轮已通过视觉讨论确认选择方案 A：在展开态保留左右“信息耳朵”，用有用的状态信息和半透明磨砂质感填充两端，而不是放纯装饰。

### 本轮目标

- 展开态刘海左右两端不再是纯黑空区。
- 左右两端复用现有刘海收起态状态来源，保持信息连续：
  - 左侧优先显示主额度进度。
  - 右侧优先显示百分比、剩余量或到期状态文本。
- 状态槽在展开态仍可见，但比收起态更克制，避免抢正文内容。
- 视觉上使用半透明磨砂胶囊、轻描边和内高光，减少纯黑面积。
- 不改 hosted window frame、hover 区域、拖拽脱离、展开高度策略、Settings 数据结构。

### 实施步骤

1. **补充可测试的小策略**
   - 在 core 中增加展开态信息耳朵的可见度/降级策略，例如根据 `contentOpacity`、slot 宽度和是否有状态文本计算：
     - 展开态最低可见透明度。
     - 是否显示辅助文本。
     - 进度条最小宽度。
   - 用 Swift Testing 覆盖“展开态不完全淡出”和“窄宽度降级”的规则。

2. **优化 `NotchHostedSurfaceView` 顶部渲染**
   - 调整 `topCap` 背景，降低纯黑压迫感，保留刘海融合需要的暗色底。
   - 将 `statusSlot` 从只在收起态可见改为展开态也保持低调可见。
   - 给左右状态槽增加半透明磨砂底、轻描边和内高光。
   - 保持收起态视觉紧凑，不回退成整条菜单栏状态条。

3. **处理文本和空状态**
   - 右侧文本使用固定行数和合理 `minimumScaleFactor`，但不无限缩小。
   - 无有效状态时使用低透明占位或隐藏内部文本，避免留下突兀黑块。
   - 窄宽度优先保留核心数字/进度，不显示额外说明文字。

4. **验证**
   - `swift test --filter NotchSurfacePolicy`
   - 新增策略测试对应 filter。
   - `swift test`
   - `xcodebuild -project token_hud.xcodeproj -scheme token_hud -destination 'platform=macOS' build`
   - `git diff --check`

### 验证

- 自动测试锁住展开态信息耳朵不会完全淡出，以及窄宽度降级行为。
- 真机手动验证：
  - 收起 → 展开 → 收起 → 再展开，左右信息耳朵始终贴合刘海两侧。
  - 展开态顶部左右不再出现纯黑空区。
  - 模型/组件变多时，正文布局不被左右耳朵影响。
  - 无数据、长文本、窄屏时没有溢出或异常缩放。

### 风险

- 如果状态槽视觉太强，可能和展开正文争抢注意力，需要通过透明度和尺寸控制。
- 如果 `topCap` 颜色变浅过多，可能削弱和物理刘海的融合感。
- 当前工作树已有多轮未提交改动，本轮只修改与 hosted 顶部视觉相关的文件，不回退既有几何和窗口管理修复。

### 本轮实现结果（2026-06-19）

- 新增 `NotchInfoEarPresentationPolicy`：
  - 展开态 `contentOpacity == 1` 时，左右信息耳朵仍保持最低可见度。
  - 收起态保持满透明度，不改变原来的紧凑状态。
  - 窄 slot 自动隐藏右侧文本并使用低调占位。
  - 进度条宽度有最小值和最大值，避免溢出或过长。
- `NotchHostedSurfaceView` 顶部视觉调整：
  - 展开态 top cap 降低纯黑覆盖，增加轻微高光和更清晰的边线。
  - 左右 `statusSlot` 不再随正文淡入完全消失。
  - 左右状态槽增加半透明磨砂胶囊底、细描边和内高光。
  - 左侧继续显示额度进度条，右侧继续显示现有收起态配置出的状态文本。
- 本轮不改变 hosted window frame、hover 命中、拖拽脱离、Settings 配置和 state 数据模型。

### 验证结果

- TDD RED：`swift test --filter NotchSurfacePolicy/infoEars` 先因缺少 `NotchInfoEarPresentationPolicy` 失败，符合预期。
- `swift test --filter NotchSurfacePolicy`：通过，25 个测试通过。
- `swift test`：通过，167 个测试通过。
- `xcodebuild -project token_hud.xcodeproj -scheme token_hud -destination 'platform=macOS' build`：通过。

### 待手动验证

- 展开态顶部左右不再出现纯黑空区。
- 收起 → 展开 → 收起 → 再展开，左右信息耳朵仍贴合刘海两侧。
- 右侧状态文本较长或数据缺失时，没有明显溢出或异常缩放。

## 当前重点：第二次展开后刘海对齐漂移修复（已实现，待手动体验验证）

### 问题

用户反馈上一轮仍未修复：第一次浮窗缩小后，再重新放大，会出现“不在刘海两端”的视觉状态。

本轮重新分析后，问题更像是 **hosted 刘海 surface 的 frame / 交互状态在 collapse → expand 或 detached resize → snap → expand 之间被污染**，而不是单纯的内容顶部对齐：

- 上一轮只修了 `FloatingPanelView` 内容对齐；它影响 detached 自由浮窗内部内容，但不能保证 hosted 刘海 surface 第二次展开时仍贴合刘海两端。
- 历史 work-log `2026-06-01-notch-fusion-smooth.md` 里明确记录过：hosted surface 曾因 AppKit 原生拖动/窗口重排导致 frame 漂移，最终策略是 hosted 状态保持 canonical expanded frame。
- 当前代码在 `animateToExpanded()` 又把 `overlayWindow.isMovableByWindowBackground` 设为 `true`，这会让 hosted expanded window 重新具备被 AppKit 原生移动的能力。
- 如果 hosted window 在收起/再次展开期间被移动、被 detached 缩放尺寸影响，或实际 window size 与 `hostState.frames.expanded` 不一致，`NotchHostedSurfaceView` 的局部布局就可能按“期望尺寸”绘制到“实际脏尺寸”里，出现顶部/两端不贴合刘海的状态。

### 本轮目标

- 不管经历多少次 `expanded → collapsed → expanded`，hosted surface 都从 canonical `frames.expanded` 开始绘制。
- detached 自由浮窗被缩小/拉大后，再吸附回刘海并重新展开，不把 detached 的尺寸、位置或 scale 污染到 hosted surface。
- hosted expanded/collapsed 两种模式都不允许 AppKit 原生 background dragging 直接移动 overlay window。
- 保留“从 expanded 拖出变 detached”的能力，但这条路径必须显式切换到 detached window，不能让 hosted window 自己漂移。
- 不再继续调整内容字体大小、Settings 布局模式或 widget 数据模型。

### 实施步骤

1. **增加可测试策略**
   - 在 `NotchSurfacePolicy` 或新增小策略里定义 hosted window 的拖动/移动规则：
     - `.collapsed` 和 `.expanded`：不允许 `isMovableByWindowBackground`。
     - `.detached`：允许 `isMovableByWindowBackground`。
   - 用 Swift Testing 先写失败测试，锁住“hosted 不可被 AppKit 背景拖动”的规则。

2. **统一 hosted frame 重置**
   - 检查并调整以下入口，确保每次进入 hosted collapsed/expanded 前都刷新 geometry，并把 overlay window 强制设回 `frames.expanded`：
     - `snapToCollapsed()`
     - `animateToCollapsed()`
     - `animateToExpanded()`
     - `restoreState()`
     - `screenParametersChanged()`
     - `hostedLayoutInputsChanged()`
   - `reassertHostedFrame(...)` 不只依赖“看起来接近”就跳过；对状态切换入口优先强制 set frame，避免第二次展开沿用脏 frame。

3. **修正 expanded 拖出 detached 的方式**
   - 移除 hosted expanded 的 AppKit 原生 background dragging。
   - 如果需要保持拖出能力，在 expanded body 的 mouse down / drag 路径里显式切到 detached：
     - detached 初始 frame 使用当前 hosted body 的屏幕 rect。
     - 后续拖动由 detached window 或手动 drag monitor 接管。
   - 这一步只处理“拖出变自由浮窗”，不改变 hover 展开/收起动画。

4. **补充诊断**
   - 在 snap/collapse/expand 入口打印 requested `frames.expanded` 和 actual `overlay.frame`。
   - 如果 actual 与 canonical 不一致，立即记录并重置，方便真机验证第二次展开是否还会漂。

5. **验证**
   - 自动验证：
     - 新增 hosted movement policy 测试。
     - `swift test --filter NotchSurfacePolicy`
     - `swift test --filter NotchGeometryCalculator`
     - `swift test`
     - `xcodebuild -project token_hud.xcodeproj -scheme token_hud -destination 'platform=macOS' build`
     - `git diff --check`
   - 手动验证：
     - hover 展开 → 移开收起 → 再 hover 展开，重复多次，面板仍贴在刘海两端。
     - detached 自由浮窗缩小后吸附回刘海，再展开，尺寸不会污染 hosted surface。
     - 从 expanded body 拖出后仍能进入 detached，且拖出瞬间不出现透明大窗口漂移。

### 验证

- 自动测试覆盖 hosted window 不可被 AppKit 背景拖动这一关键规则。
- 真机手动验证仍是必要的，因为 `NSPanel` 实际 frame、SkyLight delegation、鼠标事件时序无法完全由 core tests 模拟。

### 本轮实现结果（2026-06-19）

- 新增 `NotchWindowMovementPolicy`：
  - hosted `.collapsed` / `.expanded` 均不允许 AppKit background dragging。
  - `.detached` 保持可 background dragging。
- `NotchHostPanelManager` 所有 window movement 状态统一走策略，不再在 expanded hosted 状态把 overlay window 设为可原生拖动。
- `transitionTo(.detached)` 显式把 source mode 传给 `switchToDetached(from:)`：
  - 避免 mode 先变成 `.detached` 后，`detachedTargetFrame()` 再判断 `hostState.isExpanded` 失效。
  - expanded body 拖出时不再回落到缩小后的旧 `savedDetachedFrame`。
- 新增 `NotchGeometryCalculator.hostedBodyDetachedFrame(...)`：
  - detached 初始 frame 从 canonical hosted body rect 计算。
  - 测试覆盖自定义 body height 下的 body screen rect。
- expanded body 拖出改为显式 drag monitor：
  - mouse down 只记录起点。
  - 拖动超过阈值才切到 detached。
  - detached window 按鼠标 delta 跟随，不让 hosted overlay 自己漂移。
- 状态切换时 `reassertHostedFrame(..., force: true)`，避免第二次展开沿用脏 frame。
- 已沉淀 work-log：
  - `docs/work-log/2026-06-19-notch-reexpand-frame-drift.md`

### 验证结果

- TDD RED：`swift test --filter NotchSurfacePolicy` 先因缺少 `NotchWindowMovementPolicy` 失败，符合预期。
- TDD RED：`swift test --filter hostedBodyDetachedFrameUsesCanonicalBodyRect` 先因缺少 `hostedBodyDetachedFrame(...)` 失败，符合预期。
- `swift test --filter NotchSurfacePolicy`：通过，21 个测试通过。
- `swift test --filter hostedBodyDetachedFrameUsesCanonicalBodyRect`：通过，1 个测试通过。
- `swift test --filter NotchGeometryCalculator`：通过，53 个测试通过。
- `xcodebuild -project token_hud.xcodeproj -scheme token_hud -destination 'platform=macOS' build`：通过。
- `git diff --check`：通过。

### 待手动验证

- hover 展开 → 移开收起 → 再 hover 展开，重复多次，面板仍贴在刘海两端。
- detached 自由浮窗缩小后吸附回刘海，再展开，尺寸不会污染 hosted surface。
- 从 expanded body 拖出后仍能进入 detached，且拖出瞬间不出现透明大窗口漂移。

### 风险

- 禁用 hosted background dragging 后，如果显式 detached drag 接管不完整，可能会短暂影响“从展开面板拖出”的手感。
- 如果实际根因是 SkyLight delegation 或系统级窗口重排，可能需要继续扩大诊断日志，而不是只改 SwiftUI 布局。
- 当前工作树里已有上一轮多文件未提交改动，本轮会只叠加必要修复，不回退已有修改。

## 当前重点：自由浮窗缩放后内容保持顶部布局（已实现，待手动体验验证）

### 问题

用户反馈上一轮仍未修复：浮窗在放大/缩小后仍可能从图一变成图二。

重新分析截图后，上一轮定位有误：

- 图中右下角有 resize grip，说明截图里的窗口是 **detached 自由浮窗**，渲染路径是 `FloatingPanelView`。
- 上一轮修复的是 hosted 刘海路径 `NotchHostedSurfaceView`，所以不会影响这张截图里的自由浮窗。
- `FloatingPanelView` 当前明确把内容居中：
  - `ZStack(alignment: .bottomTrailing)` 只负责让 resize grip 在右下角。
  - `overlayContent.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)` 会把内容放到面板中间。
  - `scaleEffect(scale, anchor: .center)` 会继续以中心点放大/缩小。
- 当用户把自由浮窗高度拉大后，背景跟着变高，内容仍按中心布局，因此顶部出现图二那种大块空黑区域。

### 本轮目标

- 自由浮窗无论被用户拖大、缩小或通过手势缩放，都保持图一那种视觉状态。
- 内容垂直方向固定从顶部开始排布，不再因为窗口高度变化而居中下沉。
- 保持 resize grip 在右下角。
- 保持已有紧凑/分组显示模式和手势缩放能力。
- 不改变刘海 hosted surface 的几何和展开高度策略。

### 实施步骤

1. 修改 `token_hud/Overlay/FloatingPanelView.swift`：
   - 将 `overlayContent` 的 frame 对齐从 `.center` 改为顶部对齐。
   - 将 `scaleEffect` anchor 从 `.center` 改成顶部锚点，避免缩放时内容从中心向上下扩散。
   - 横向优先保持现有居中观感，避免内容贴到左边。
2. 复核 `calculateAdaptiveScale(for:)`：
   - 如果高度变大仍导致字体随窗口高度明显变大，再把自由浮窗的 adaptive scale 从“按高度缩放”改成更稳定的策略。
   - 第一轮先只改锚点，避免一次性改变字体大小逻辑。
3. 验证：
   - `swift test --filter NotchExpandedLayoutPolicy`
   - `swift test --filter NotchGeometryCalculator`
   - `xcodebuild -project token_hud.xcodeproj -scheme token_hud -destination 'platform=macOS' build`
   - `git diff --check`

### 验证

- 自动验证确保相关 core 和 app target 不回退。
- 手动验证自由浮窗：
  - 拉高窗口后，内容仍停在顶部，不出现图二顶部空黑条。
  - 缩小窗口后，内容不会被中心缩放推偏。
  - resize grip 仍在右下角可用。

### 本轮实现结果（2026-06-18）

- 新增 `FloatingPanelContentLayoutPolicy`，用 core 测试锁定 detached 自由浮窗内容顶部锚定策略。
- `FloatingPanelView` 不再把内容 `.center` 垂直居中，而是按策略使用 `.top` 垂直对齐。
- `FloatingPanelView` 的 `scaleEffect` 不再使用 `.center` 锚点，而是从 `.top` 锚点缩放，避免手势缩放时内容从中线向上下扩散。
- 保持横向居中、resize grip 右下角、紧凑/分组显示模式和现有 adaptive scale 计算不变。

### 验证结果

- TDD RED：`swift test --filter FloatingPanelContentLayoutPolicy` 先因缺少策略类型失败，符合预期。
- `swift test --filter FloatingPanelContentLayoutPolicy`：通过，1 个测试通过。
- `swift test --filter PanelResizeCalculator`：通过，2 个测试通过。
- `swift test --filter NotchExpandedLayoutPolicy`：通过，4 个测试通过。
- `swift test --filter NotchGeometryCalculator`：通过，52 个测试通过。
- `swift test`：通过，160 个测试通过。
- `xcodebuild -project token_hud.xcodeproj -scheme token_hud -destination 'platform=macOS' build`：通过。
- `git diff --check`：通过。

### 风险

- 这是 SwiftUI 视图对齐问题，自动测试难以直接覆盖，需要真实窗口手动截图验证。
- 如果用户还希望“窗口高度也自动回到内容高度”，那是另一类行为：需要限制/重算 detached frame，而不只是内容锚点。

## 当前重点：刘海展开浮窗内容顶部锚定（已实现，待手动体验验证）

### 问题

用户反馈动态高度展开后出现两种视觉状态：

- 期望：像图一，内容贴近刘海下方，从顶部自然展开。
- 当前异常：像图二，浮窗高度变大后顶部出现大块空黑区域，内容被挤到中间偏下。

根因定位：

- `NotchHostedSurfaceView.bodyPanel(...)` 使用 `ZStack` 默认居中布局。
- 上一轮加入动态 `expandedBodyHeight` 后，body 高度可能大于内容实际高度。
- 当 body 变高时，内容仍按 ZStack 中心对齐，导致面板顶部留出空白黑区。

### 本轮目标

- 无论浮窗高度如何自适应变化，内容都保持图一那种顶部锚定状态。
- body 高度仍可增长，字体仍固定，不回退到缩放字体。
- 不改变 Settings 新增的“自适应高度 / 分组切换”选项。
- 不改变 state.json、widget 模型或刘海窗口 frame 策略。

### 实施步骤

1. 调整 `NotchHostedSurfaceView.bodyPanel(...)`：
   - 将内容容器从默认居中改为 `.topLeading` 锚定。
   - 滚动模式和非滚动模式都保持顶部开始排布。
   - 保留现有 padding、opacity 和轻微 scale 动画。
2. 检查 `SectionedOverlayView` 和 `GroupedOverlayView`：
   - 确保自身不会强制垂直居中。
   - 长内容继续使用滚动承载。
3. 验证：
   - `swift test --filter NotchGeometryCalculator`
   - `swift test --filter NotchExpandedLayoutPolicy`
   - `xcodebuild -project token_hud.xcodeproj -scheme token_hud -destination 'platform=macOS' build`
   - `git diff --check`

### 验证

- 自动验证确保 core 几何和 app 编译不回退。
- 手动验证需要在真实 app 里打开刘海浮窗，拖动/切换设置后确认内容始终贴近顶部。

### 本轮实现结果（2026-06-18）

- `NotchHostedSurfaceView.bodyPanel(...)` 中的展开内容容器改为 `.topLeading` 锚定。
- 非滚动内容会填满 body 并从左上角开始排布。
- 滚动内容保持顶部开始排布，不再因 body 高度变大而垂直居中。
- 保留原有 padding、opacity 和轻微 scale 动画。

### 验证结果

- `swift test --filter NotchGeometryCalculator`：通过，52 个测试通过。
- `swift test --filter NotchExpandedLayoutPolicy`：通过，4 个测试通过。
- `xcodebuild -project token_hud.xcodeproj -scheme token_hud -destination 'platform=macOS' build`：通过。
- `git diff --check`：通过。

### 待手动验证

- 默认自适应高度下，放大或高度增长后内容仍贴近图一顶部位置。
- 切到“分组切换”后，内容也从顶部开始排布。
- 高度达到上限并滚动时，滚动内容初始位置在顶部。

### 风险

- 这是 SwiftUI 视图对齐修复，缺少稳定的单元测试覆盖，需要依赖 build 和手动截图验证。
- 如果 body 高度极大，顶部锚定后底部会留空；这是预期，优先满足“内容从刘海下方展开”的视觉模型。

## 当前重点：刘海浮窗展开高度自适应与分组切换模式（已实现，待手动体验验证）

### 问题

用户希望优化浮窗从刘海展开的效果：

- 当前展开高度固定，模型/服务变多时，内容会通过 `adaptiveScale` 越缩越小。
- 字体随内容数量缩小后，视觉质量下降，也不利于快速扫读。
- 用户已确认要同时支持视觉方案 B 和 C：
  - **B：高度自适应 + 固定字体**，作为默认模式。
  - **C：分组切换 + 中等高度**，在 Settings 可选。

本轮已阅读：

- `PLAN.md`
- `docs/work-log/2026-06-04-notch-fusion-rebuild.md`
- `docs/work-log/2026-06-04-notch-compact-pills.md`
- `docs/work-log/2026-06-17-app-health-pass.md`
- `token_hud/Overlay/NotchHostedSurfaceView.swift`
- `token_hud/Overlay/GroupedOverlayView.swift`
- `token_hud/Overlay/CompactOverlayContent.swift`
- `token_hud/Overlay/NotchHostState.swift`
- `Sources/token_hudCore/NotchGeometryCalculator.swift`
- `Settings/SettingsWindow.swift`

根因定位：

- `NotchGeometryCalculator.expandedHeight` 当前固定为 `110`。
- `NotchHostedSurfaceView.adaptiveScale(for:)` 在 grouped 模式下用 `actualHeight / idealHeight` 得出缩放比例。
- 当服务/模型增多时，`idealHeight` 增大但窗口高度不变，scale 会下降，最终导致字体和组件一起变小。

### 本轮目标

- 默认改成 **高度自适应 + 固定字体**：
  - 展开 body 高度根据当前显示内容数量增长。
  - 字体尺寸保持稳定，不再因为模型/服务变多而继续缩小。
  - 高度有上限，超过上限后 body 内部滚动，避免遮挡过多屏幕。
- 增加 **分组切换 + 中等高度** 可选模式：
  - Settings 中可选择刘海展开布局模式。
  - 模式 C 保持中等高度，通过服务/分组切换减少同屏内容。
  - 默认值为 B。
- 保留现有 LiuHai hosted 架构：
  - 顶部 cap / notch 锚点不动。
  - `expansionProgress` 继续驱动展开动画。
  - 不回退到 window resize 动画交叉淡入方案。
- 不改变 state.json schema、不改变 widget 数据模型。

### 方案取舍

- **采用 B 作为默认**：
  - 优点：最符合“快速瞄一眼”和固定字体的诉求，配置模型多时可读性最好。
  - 缺点：展开后高度会变大，需要上限和滚动保护。
- **同时加入 C 作为设置项**：
  - 优点：用户可以选择更克制的浮窗高度，适合平台/模型很多的情况。
  - 缺点：增加轻量交互状态，需要处理当前分组不存在或 widget 变化后的回退。
- **不采用 A**：
  - A 继续依赖缩放/滚动，不能解决“字体越来越小”的核心问题。

### 实施步骤

1. **新增可测试的高度策略**
   - 在 `Sources/token_hudCore` 增加或扩展纯逻辑策略，输入：
     - overlay 展开布局模式：adaptive / sectioned。
     - 当前 widget 数量、服务数量、屏幕高度、菜单栏高度。
   - 输出：
     - expanded body 高度。
     - 是否需要内部滚动。
     - 固定内容 scale。
   - 测试覆盖：
     - 默认 adaptive 模式随服务数量增加而增高。
     - adaptive 模式高度不超过屏幕上限。
     - adaptive 模式内容 scale 不再低于固定字体阈值。
     - sectioned 模式保持中等高度。

2. **让 hosted surface 使用动态 expanded frame**
   - 调整 `NotchGeometryCalculator.notchFrames(...)` 或新增重载，让 expanded height 可以由内容策略传入。
   - `NotchHostPanelManager.computeFrames(...)` 根据 `WidgetStore` 当前 widgets 和 Settings 模式计算目标高度。
   - widget 配置变化或设置模式变化时，重新计算 hosted frame，并在展开态平滑 reassert 到新 expanded frame。
   - 保持 collapsed frame 和 hover top cap 行为不变。

3. **固定字体与内部滚动**
   - 修改 `NotchHostedSurfaceView.adaptiveScale(for:)`：
     - adaptive 默认不再把 grouped 内容压到很小，scale 下限提高到接近 `1.0`。
     - 内容超出可用 body 高度时，用内部纵向滚动或按模式 C 切换分组承载。
   - `GroupedOverlayView` 保持服务行字体稳定，长 label 截断，不因行数增加缩小。
   - `CompactOverlayContent` 保持横向滚动，不参与高度压缩。

4. **实现分组切换模式 C**
   - 新增 `notchExpandedLayoutMode` AppStorage，默认 `adaptive`。
   - sectioned 模式下，在展开 body 顶部显示轻量分组切换控件：
     - 当前服务/分组选中态。
     - 只渲染选中服务的 widgets。
     - 如果当前选中服务被删除，自动回退到第一个可用服务。
   - 控件高度计入 body 固定中等高度，不让字体缩小。

5. **Settings 增加选项**
   - 在 `SettingsWindow` 的浮动面板设置里增加“刘海展开布局”选择：
     - 自适应高度（默认）
     - 分组切换
   - 文案保持简洁，不写大段说明。
   - 继续保留现有“显示模式：紧凑/分组”，避免改变浮动自由面板行为。

6. **验证**
   - 自动验证：
     - 新增策略测试。
     - `swift test --filter NotchGeometryCalculator`
     - `swift test --filter Widget`
     - `swift test`
     - `xcodebuild -project token_hud.xcodeproj -scheme token_hud -destination 'platform=macOS' build`
   - 手动验证：
     - 2 个服务、5 个服务、10 个服务时展开高度逐步变高，字体不继续缩小。
     - 高度到上限后内部滚动可用。
     - Settings 切到分组切换后，浮窗保持中等高度，并能切换服务。
     - hover 展开/收起动画仍从刘海向下生长，不跳位。

### 验证

- 新策略有纯逻辑测试覆盖，避免后续再次把高度写死。
- build 通过，确认新增文件进入 Xcode target。
- 真实 macOS 手动验证动画和 hover，因为窗口层行为无法完全靠 core tests 覆盖。

### 本轮实现结果（2026-06-17）

- 新增 `NotchExpandedLayoutPolicy`：
  - `adaptive` 默认模式按服务数量增长 body 高度，content scale 固定为 `1`。
  - `sectioned` 模式保持中等高度，给分组切换模式使用。
  - 高度超过屏幕上限后启用内部滚动。
- `NotchGeometryCalculator` 支持传入自定义 `expandedBodyHeight`：
  - `notchFrames(...)`、`hostedSurfaceLayout(...)` 旧调用保持默认值。
  - 新测试覆盖 custom body height 的 expanded frame 和 hosted layout。
- `NotchHostPanelManager` 接入动态高度：
  - 根据当前 widgets、服务数量和 `notchExpandedLayoutMode` 计算 hosted expanded frame。
  - 监听 WidgetStore 和 UserDefaults 变化，设置或小组件变化时刷新 hosted frame。
  - hit mask、hover expanded surface、detach target 统一使用动态高度。
- `NotchHostedSurfaceView` 固定 hosted 内容 scale：
  - 默认 adaptive 不再因为服务/模型变多压缩字体。
  - 超出高度上限后内部纵向滚动。
  - sectioned 模式渲染 `SectionedOverlayView`。
- Settings 增加“刘海展开布局”：
  - 默认“自适应高度”。
  - 可切换为“分组切换”。
- 已沉淀 work-log：
  - `docs/work-log/2026-06-17-notch-adaptive-expanded-layout.md`

### 验证结果

- `swift test --filter NotchExpandedLayoutPolicy`：通过，4 个测试通过。
- `swift test --filter NotchGeometryCalculator`：通过，52 个测试通过。
- `swift test`：通过，159 个测试通过。
- `xcodebuild -project token_hud.xcodeproj -scheme token_hud -destination 'platform=macOS' build`：通过。
- `git diff --check`：通过。

### 待手动验证

- 2、5、10 个服务时，默认 adaptive 展开高度随内容增加，字体不继续变小。
- 切到 Settings 的“分组切换”后，刘海展开保持中等高度，并能切换服务。
- hover 展开/收起仍从刘海向下生长，不跳位。
- 高度达到上限时，body 内部滚动可用。

### 风险

- hosted window 当前假设 frame 等于 expanded frame；动态高度后必须保证 `reassertHostedFrame` 和 hover body hitbox 同步使用新 frame。
- Settings 的 `@AppStorage` 改动会即时影响 overlay，需要避免设置切换时出现突然跳位。
- 分组切换模式新增交互，但 HUD 目标仍是快速扫读，控件必须轻量，不能把浮窗做成复杂面板。
- 当前 `Xcode 运行时 LLDB attach failed 修复` 计划仍待确认；如果本轮需要 Xcode 真机调试，建议先执行该配置修复，否则命令行 build 可以继续验证。

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
