# 刘海融合方案：耳朵+身体分离式

## 背景

用户反馈面板吸附到刘海后"显示得很丑，并没有真正跟刘海融为一体"。经过讨论，选择了方案一（耳朵+身体分离式）：将面板拆成三个独立 NSPanel（左耳、右耳、身体），由同一个 manager 协调，形成 Dynamic Island 扩展效果。

参考了 BoringNotch（9.3k stars）和 DynamicNotchKit（414 stars）的实现模式。

## 关键操作

- 新增 `token_hud/Overlay/NotchEarPanelManager.swift`：
  - 管理左耳和右耳两个 NSPanel
  - 面板配置：`.screenSaver` level、`.borderless`、透明背景、忽略鼠标事件
  - `setup(leftFrame:rightFrame:)` 创建面板
  - `show()`/`hide()` 带 0.2s 淡入淡出动画
  - `updateFrames()` 更新位置
  - 内嵌 `EarView`：纯黑 Rectangle

- 修改 `Sources/token_hudCore/NotchGeometryCalculator.swift`：
  - `NotchFrames` 新增 `leftEar` 和 `rightEar` 属性
  - `collapsedBodyHeight = 6`：身体 collapsed 时为 6pt 黑条
  - `notchFrames()` 计算耳朵 frame（覆盖菜单栏两侧区域）和身体 frame（紧贴刘海下边缘）
  - 耳朵 frame：左侧 `[screen.minX, notchGapMinX)` × menuBarHeight，右侧 `[notchGapMaxX, screen.maxX)` × menuBarHeight

- 修改 `token_hud/Overlay/NotchHostPanelManager.swift`：
  - 新增 `earManager` 属性
  - `setup()`：创建耳朵面板，hosted 状态时显示
  - `teardown()`：销毁耳朵面板
  - `animateToCollapsed()`：显示耳朵
  - `animateToExpanded()`：确保耳朵可见
  - `switchToDetached()`：隐藏耳朵
  - `screenParametersChanged()`：更新耳朵位置

- 修改 `token_hud/Overlay/NotchCollapsedView.swift`：
  - 改为纯黑 Rectangle（6pt 黑条），不再使用 NotchCollapsedChrome

- 修改 `token_hud/Overlay/NotchExpandedView.swift`：
  - 移除顶部 chrome（NotchCollapsedChrome），直接显示内容
  - 整个面板使用 UnevenRoundedRectangle（底部 12pt 圆角，顶部无圆角）

- 修改测试 `Tests/token_hudCoreTests/NotchGeometryCalculatorTests.swift`：
  - `collapsedHeightMatchesSafeArea` → `collapsedHeightIsThinStrip`：验证 6pt
  - `collapsedMaxYEqualsScreenMaxY` → `collapsedTopConnectsWithNotchBottom`：验证身体顶部与刘海底部对齐
  - `expandedMaxYEqualsScreenMaxY` → `expandedTopConnectsWithNotchBottom`
  - 新增 `leftEarCoversLeftMenuBarArea`、`rightEarCoversRightMenuBarArea`
  - 新增 `earsConnectWithBody`：验证耳朵底部与身体顶部对齐
  - 新增 `noNotchDisplayHasZeroEars`
  - 103 个测试全部通过

## 关键决策

- 耳朵和身体使用独立 NSPanel，而非单个全宽面板。优点是各自定位精确，缺点是需要协调动画。
- 身体 collapsed 高度设为 6pt（非菜单栏高度），视觉上是刘海向下延伸的黑条。
- 耳朵使用纯黑色（`Color.black`），与刘海物理黑色区域同色。
- 耳朵初始隐藏（alpha=0），吸附时淡入，拖离时淡出。
- `NotchCollapsedChrome` 已成为死代码（不再被任何视图引用），待确认是否删除。

## 验证结果

- `swift test` 通过：103 个测试全部通过。
- `swift build` 通过。

## 后续注意事项

- 需要在真机上验证耳朵+身体的融合视觉效果。
- 如果纯黑耳朵与菜单栏有明显分界线，可考虑添加渐变效果（从刘海向外淡化）。
- collapsed 6pt 高度可能需要根据真机效果微调（4-8pt 范围）。
- 耳朵可能遮挡菜单栏系统图标，需要用户测试确认是否可接受。
- 清理 `NotchCollapsedChrome.swift`（死代码）。
- 清理 `collapsedSidePadding`、`collapsedMinWidth`、`collapsedMaxWidth`、`collapsedMinHeight`、`collapsedMaxHeight` 等不再使用的常量。
