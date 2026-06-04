# 2026-06-01 Notch Fusion Smooth

## 背景

用户反馈刘海融合面板存在三个问题：

1. collapsed/expanded 切换时浮窗有重影。
2. 从 expanded 拖走时出现奇怪漂浮（detach 后窗口跳到默认 300×60 位置）。
3. 动画整体不够流畅。

期望：hover 时从耳朵向左右及下方平滑展开；移开时整体高度回到刘海，仅左右耳朵显示状态小动画；拖回吸附时仅左右耳朵显示极简状态。

## 根因

1. **重影**：`NotchHostRootView` 用 `switch hostState.mode` 在三种完全不同的子视图（`NotchCollapsedStatusView` / `NotchFusionView` / `FloatingPanelView`）之间切换；SwiftUI 默认 transition 是 opacity，切换瞬间两层叠加。叠加上 NSAnimationContext window 动画与 SwiftUI 隐式动画双轨并行，看起来是第二层"幻影"。
2. **漂浮**：expanded overlay window 是 ~560×142 的透明矩形；超过阈值 detach 时，`switchToDetached()` 把 `detachedWindow` 重置成 `300×60` 放在 collapsed 下方，视觉上是"跳到别处的小条"。
3. **不流畅**：collapsed↔expanded 是离散的 mode 切换，没有用 `expansionProgress` 做连续插值；NSAnimationContext 和 SwiftUI 动画时序对不上。

## 关键决策

- hosted 状态下 overlay window 的 frame **永远等于 expanded frame**，不再在 collapsed/expanded 之间切换 setFrame。
- collapsed 与 expanded 合并为同一个视图 `NotchHostedSurfaceView`，由 `hostState.expansionProgress` 0→1 在 SwiftUI 内部连续插值耳朵和 body。
- `NotchHostRootView` 简化为两个分支：hosted → `NotchHostedSurfaceView`，detached → `FloatingPanelView`，再不发生跨视图替换。
- 动画完全由 SwiftUI `withAnimation(.spring(response: 0.32, dampingFraction: 0.82))` 驱动 `expansionProgress`，移除 NSAnimationContext window 动画。
- 透明区域穿透：`NotchTrackingContainerView.hitTest(_:)` 只在 ears ∪ body 范围内接受点击，其余穿透到下层（menu bar / desktop / apps）。
- 从 expanded 拖出 detach 时，detached 窗口出现在 expanded body 在屏幕上的实际位置（含用户拖动位移）与尺寸；不再用 `300×60` 默认值。

## 修改范围

- `Sources/token_hudCore/NotchGeometryCalculator.swift`
  - 新增 `NotchHostedSurfaceLayout` 数据结构。
  - 新增 `hostedSurfaceLayout(screenFrame:geometry:expansionProgress:)` 纯函数。
- `Tests/token_hudCoreTests/NotchGeometryCalculatorTests.swift`
  - 新增 5 个 hostedSurfaceLayout 测试：耳朵 rect 不随 progress 变、body 高度单调递增、bodyOpacity 在 fadeStart 前为 0、surfaceSize 等于 expanded frame、耳朵+gap 覆盖菜单栏行。
- `token_hud/Overlay/NotchHostedSurfaceView.swift`（新建）
  - 统一 hosted 视图，按 progress 渲染耳朵 + body。
  - `NotchCollapsedStatusComputer` / `NotchCollapsedStatusValue` 共享 widget fraction 与百分比文本计算。
- `token_hud/Overlay/NotchHostRootView.swift`
  - 简化为 hosted/detached 二选一；动画绑定到 `expansionProgress`。
- `token_hud/Overlay/NotchHostPanelManager.swift`
  - `toggle` / `restoreState` / `snapToCollapsed` / `screenParametersChanged` 全部 setFrame 到 `frames.expanded`。
  - `animateToCollapsed` / `animateToExpanded` 改为 `withAnimation` 驱动 progress，移除 NSAnimationContext window 动画。
  - `switchToDetached` 改为通过 `detachedTargetFrame()` 计算：用 overlay 当前 frame + body 局部 rect → 屏幕坐标，detached 出现在 body 同位置同尺寸。
  - 新增 `hostedHitMask(in:)`：返回当前 ears ∪ body 命中区。
  - `NotchTrackingContainerView.hitTest(_:)` 调用 `hostedHitMask` 让透明区穿透。

## 验证结果

- `swift test --filter NotchGeometryCalculator` 通过（44 个测试）。
- `swift test` 通过（107 个测试）。
- `xcodegen generate` 后 `xcodebuild -project token_hud.xcodeproj -scheme token_hud -destination 'platform=macOS' build` 成功。

> 注意：新增 Swift 文件后必须重新跑 `xcodegen generate`，否则 xcodeproj 不会包含新文件。

## 二次追加修复（2026-06-02，启动卡死无法拖动）

用户截图显示 app 启动后立刻出现一块大尺寸面板贴在刘海下方，无法拖动。根因 + 修复：

- **mid-drag detach 时把 transient frame 写盘了**：上一轮把 detach 时的 detached 目标 frame 设成 expanded body 同位置同尺寸（~560×110），然后 `switchToDetached → saveState` 立即持久化。下次启动就在这个位置加载，看起来像"卡住的大块"。修复：
  - `saveState` 在 `isDragging == true` 时直接返回，不写盘。等用户 mouseUp 后再 save。
  - `detachedTargetFrame()` 只在 mid-drag 时返回 body-sized rect；其他场景（非拖动 detach、restoreState）仍用 `savedDetachedFrame` 或默认 300×60。
  - `restoreState` 时校验 `savedDetachedFrame`：如果它的 top-center 落在 `frames.snapZone` 内（说明是 hosted 残留），就丢弃并 `removeObject` 清掉污染的 UserDefaults。
- **"无法拖动"的 mouseDown → instant detach + manualDrag 路径不稳**：local monitor 在 nonactivating panel + app 未 active 时拿不到事件，用户感受就是"卡死"。改用更直接的方案：
  - `expanded` 时 `isMovableByWindowBackground = true`，AppKit 原生支持拖动。
  - 新增 `windowDidMove` 实时检测：`isDragging == true` 且 hosted overlay 偏离 canonical frame 中心 ≥ `dragDetachDistance (8px)` 时，立刻 `transitionTo(.detached)`。这意味着用户拖动几乎一开始就切到 detached，"透明大块漂浮"窗口只存在 1-2 frame 时间。
  - detached 接管后，因为它自己 `isMovableByWindowBackground = true`，鼠标继续控制 detached 窗口拖动（AppKit 同一次 mouseDown 仍属于该 panel，window number 已切换，但拖动手感不受影响）。
  - mouseUp 时如果还在 hosted（即拖动幅度不到 8px），调用 `reassertHostedFrame` 把任何小幅偏移收回 canonical。
- 移除 manualDragMonitor / manualDragAnchor / startManualDrag / handleManualDrag / beginHostedDetachDrag / isPointInsideExpandedBody。

## 追加修复（同日，frame 漂移截图反馈）

用户截图显示 hosted overlay 跑到了屏幕中部（包括 collapsed 状态下耳朵漂离刘海），并且 expanded 拖动后没矫正回 canonical。根因和修复：

- **`windowDidMove` 在 hosted 状态下漏处理**：旧版本只在 `isDragging` 时安装 mouseUp monitor，其它路径不矫正 frame。任何外部因素（Spaces 切换、SkyLight 委托、styleMask reflow）改了 frame 就再也回不来。改为：hosted 任何时候发生 windowDidMove 都立即调用 `reassertHostedFrame` 强制贴回 `frames.expanded`，并用 `isResettingHostedFrame` 防止递归。
- **`.hudWindow` style 隐性 reposition**：HUD 风格 NSPanel 有系统级 frame 重排倾向。从 `hostedStyleMask` 移除 `.hudWindow`，只保留 `[.borderless, .nonactivatingPanel]`。
- **hosted 全程禁用拖动**：`isMovableByWindowBackground = false` 在 collapsed 和 expanded 都强制 false，彻底消除"hosted overlay 被拖到偏移位置"的可能。
- **新的 detach 触发**：mouseDown 落在 expanded body 内 → 监听器立即 `transitionTo(.detached)`，让 detached 窗口出现在 body 同位置同尺寸，再用 `manualDragMonitor`（leftMouseDragged + leftMouseUp）手动 `setFrameOrigin` 跟随鼠标，直到松手。松手后照常 `evaluateSnap()`。这样消除了"透明大窗口跟随鼠标"的视觉异常。
- **`animateToCollapsed/Expanded`** 改为先 `reassertHostedFrame` 再做 SwiftUI 动画，去掉之前的 `isClose` 短路，确保任何状态切换都从 canonical frame 起步。
- **`settleHostedDrag` 已删除**：hosted 不再可拖，路径不再需要；mouse-up monitor 只服务 detached 的 snap 判定。

## 后续注意

- 真机重点验证：
  - hover 刘海 → 耳朵平滑长出 body；移开 → body 收回，耳朵保留进度条 + 百分比；过程无重影。
  - 在 expanded body 上按住拖动 → detached 窗口直接出现在 body 同位置同尺寸，跟随鼠标继续拖；不再跳到默认 300×60。
  - hosted 状态下的透明区域不会拦截 menu bar 应用点击（macOS 14+ 真机重点验证）。
- 旧的 `NotchCollapsedStatusView`（位于 `NotchCollapsedView.swift`）和 `NotchFusionView` 已不再被 `NotchHostRootView` 引用，但保留以备后续 fallback；若后续不再需要可整体删除。
- 弹性参数 `.spring(response: 0.32, dampingFraction: 0.82)` 是首版；如手感偏硬或偏软可单独调。
- detach 时 detached 窗口尺寸从默认 300×60 改为约 560×110（expanded body 尺寸）。这是一次显式行为变化，符合"无跳变"目标，但用户初次 detach 后看到的尺寸比以前大。
- SkyLight / CGS 私有 Space 路线未在本轮触动；overlay window 始终保持 expanded frame 后，对 Space 委托没有新增需求。
