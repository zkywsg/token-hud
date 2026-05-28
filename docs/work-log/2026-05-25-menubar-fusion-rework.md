# 刘海导航栏真正融合 — 窗口置入导航栏区域

## 背景

之前的 docked 实现使用 60pt 高的窗口，把上半部分推到屏幕顶部之外（`maxY > screenFrame.maxY`），然后通过 `dockedTopInset` padding 把内容向下推到可见区域。这导致内容始终显示在导航栏**下方**，而非导航栏**内部**，无法实现真正的刘海融合。

## 关键操作

### PanelDockingCalculator.swift
- 移除 `dockedHeight`（60pt）和 `dockedMinVisibleHeight`（20pt）常量。
- 新增 `dockedMinHeight`（24pt），作为无刘海屏幕的最小高度。
- `notchFusedFrame()` 重写：
  - 窗口高度 = `max(safeAreaInsetTop, dockedMinHeight)`，即导航栏高度（约 32pt）。
  - `maxY = screenFrame.maxY`：窗口不再突出屏幕外。
  - `minY = screenFrame.maxY - height`：窗口底边对齐导航栏底边。
  - 因为 NSPanel level 已经是 `.screenSaver`，窗口直接渲染在导航栏上方。

### PanelDockState.swift
- `dockedTopInset` → `menuBarHeight`：不再记录"需要推下多少"，而是记录"导航栏有多高"。

### FloatingPanelManager.swift
- `evaluateDocking()` 和 `restoreState()` 中，`dockState.menuBarHeight = screen.safeAreaInsets.top`，替代原来的 visibleHeight/topInset 计算。

### FloatingPanelView.swift
- docked 态 padding：`.top` 和 `.bottom` 各 2pt，`.horizontal` 8pt（原来 `.top` 是 `dockedTopInset + 2`）。
- docked 背景改为 `Rectangle().fill(Color.black.opacity(0.35))`，无圆角无阴影。

### PanelDockingCalculatorTests.swift
- `safeAreaTop` 从 25 改为 32（匹配真实 MacBook 刘海高度）。
- 所有断言更新：
  - `target.maxY == screen.maxY`（不再突出屏幕外）
  - `target.height == safeAreaTop`（不再是 60pt）
  - `target.minY == screen.maxY - safeAreaTop`
- 移除 `expectedTopIntrusion` 辅助函数。
- `fusedFrameFallbackSmallSafeAreaUsesMinHeight`：断言 `height == dockedMinHeight`（24pt）。

## 关键决策

- 窗口高度等于导航栏高度（而非固定 60pt）是实现"内容在导航栏内"的关键前提。窗口 level 高于 menu bar 确保绘制在导航栏上方。
- docked 态背景使用半透明黑色（0.35），让导航栏的模糊效果仍然透出，视觉上更像导航栏的一部分。
- 移除 `dockedTopInset` 因为窗口本身就在导航栏区域内，不需要"避让"。

## 验证结果

- `swift test`：84 个测试全部通过。
- 代码编译无警告。

## 后续注意事项

- 需要手动在真机上验证 docked 态的视觉效果，确认内容确实出现在导航栏/刘海区域内。
- 如果 `opacity(0.35)` 在不同壁纸下对比度不够，可能需要调整为 `0.5` 或添加 `.ultraThinMaterial` 模糊效果。
- 外接屏（无刘海）fallback 使用 24pt 最小高度；后续可考虑在无刘海屏幕上禁用 menu bar 融合态。
- docked 态内容在 ~32pt 高度内需要合理排布，如果 widget 内容过多可能显示不下，后续可能需要为 docked 态设计专门的紧凑布局。
