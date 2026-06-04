# 2026-06-04 Notch Fusion Rebuild

## 背景

用户多次截图指出，旧的刘海融合方案在 collapsed 状态下会出现两个孤立的黑色竖块，左侧进度和右侧百分比像被拆成了两个独立面板。继续在这个形态上追加 `leftShoulder` / `rightShoulder` 只能局部遮缝，不能解决整体轮廓不连续的问题。

本轮结合 `docs/notch-open-source-research.md` 中的开源调研后，确认需要放弃 “左右独立小格 + shoulder cap” 路线，改为单一连续 surface：刘海上方/两侧是同一个 top cap，内容区域从 top cap 下方向下展开。

## 决策

- collapsed 状态只画一个连续 `topCap`。
- 左侧进度条和右侧百分比是 `topCap` 内的 `leftStatusSlot` / `rightStatusSlot`，不再是独立黑块。
- 中间真实刘海区域由 `notchGap` 表示，但不单独绘制内容，让硬件刘海自然吞掉中间区域。
- expanded 状态从 `topCap` 下方向下长出 `body`。
- body 黑色底板先随高度出现，业务内容通过 `contentOpacity` 延迟淡入。
- collapsed hover / hitbox 以 `topCap` 为准；expanded hitbox 以 `topCap.union(body)` 为准。

## 几何契约

`NotchHostedSurfaceLayout` 当前字段：

- `topCap`：菜单栏行里的连续黑色 cap，collapsed 和 expanded 都以它为锚点。
- `notchGap`：真实刘海 gap 在 hosted surface local space 中的位置，用于对齐和测试。
- `leftStatusSlot`：左侧极简状态槽，collapsed 时贴住 `notchGap.minX`。
- `rightStatusSlot`：右侧极简状态槽，collapsed 时贴住 `notchGap.maxX`。
- `body`：下拉内容区，collapsed 时高度为 0，expanded 时向下增长。
- `contentOpacity`：body 内容淡入进度，晚于 body 高度变化。
- `surfaceSize`：hosted overlay 使用 expanded frame 的固定 viewport 尺寸。

## 交互契约

- collapsed：
  - 可见层只有一个 `topCap`。
  - 命中层只接收 `topCap`。
  - hover region 是 `topCap` 外扩 `collapsedHoverPadding` 后的连续区域，不覆盖整条菜单栏。
- expanded：
  - 可见层为 `topCap + body`。
  - 命中层接收 `topCap.union(body)`，其余透明区域穿透。
- 拖拽脱离仍以 expanded body 的屏幕 rect 作为 detached 初始 frame，避免拖拽时跳位。

## 验证

- `swift test --filter NotchGeometryCalculator` 通过，48 个 geometry 相关测试通过。
- `swift test` 通过，111 个测试通过。
- `xcodebuild -project ../token_hud.xcodeproj -scheme token_hud -destination 'platform=macOS' build` 通过。

## 后续风险

- 公开 `NSPanel` 仍可能无法在所有系统状态下 100% 覆盖菜单栏层级；如果用户继续要求真正进入菜单栏/锁屏层级，需要继续走 SkyLight / CGS Space 策略。
- 不同 MacBook notch 宽度和菜单栏图标密度不同，`compactStatusSlotWidth` 仍需要通过真机截图验证。
- 本轮只吸收开源项目的架构原则，没有复制 GPL 项目源码。
