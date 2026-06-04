# 2026-06-04 Notch Compact Pills

## 背景

用户反馈 hosted collapsed 状态仍然太长、不连贯：刘海两侧像一整条黑色状态条，而不是刘海左右各一个小状态块。新的目标是：收起时只保留左右两个小格，鼠标摸到任意小格后再向下延展成完整小窗。

## 关键决策

- 不回退到 window resize 动画。hosted window 仍保持 expanded frame，透明区域继续穿透。
- 只改变 SwiftUI surface 内部绘制和 hover 命中区：
  - collapsed 左右耳朵固定为 44pt 小格。
  - 展开时 ears/body 从 notch center 向外插值扩展。
  - hover 命中区从整条顶部菜单栏收缩为左右两个小格附近。
- expanded 状态下 body 也算 hover 停留区域，避免鼠标在面板内时被误判为离开并立刻收回。

## 修改范围

- `Sources/token_hudCore/NotchGeometryCalculator.swift`
  - 新增 `collapsedStatusPillWidth` 和 `collapsedHoverPadding`。
  - `hostedSurfaceLayout` 改为 collapsed 小格 + expanded 插值扩展。
  - 新增 `notchHoverRegions(screenFrame:geometry:)`，返回左右 compact hover 区。
- `Tests/token_hudCoreTests/NotchGeometryCalculatorTests.swift`
  - 新增 compact pill 宽度、pill 与 notch gap 相邻、compact hover region 覆盖测试。
  - 更新旧的 hosted surface ears 固定测试，使其符合“collapsed 小格、expanded 扩展”的新模型。
- `token_hud/Overlay/NotchHostPanelManager.swift`
  - hover 判断改用 `notchHoverRegions`。
  - expanded 时额外将 body screen rect 作为停留区域。
- `token_hud/Overlay/NotchHostedSurfaceView.swift`
  - 收紧小格视觉：短进度条、小字号百分比、7pt 底部外侧圆角。

## 验证结果

- `swift test --filter NotchGeometryCalculator` 通过，47 个测试通过。
- `swift test` 通过，110 个测试通过。
- `xcodebuild -project ../token_hud.xcodeproj -scheme token_hud -destination 'platform=macOS' build` 通过。

## 后续注意

- 真机重点验证 hover 是否容易触发。若 44pt 小格太难摸到，可以只增加 hover padding，不一定增加可见宽度。
- 右侧 `100%` 在 44pt 内可能仍偏紧；如真机显示拥挤，优先把右侧小格调到 52pt，左侧保持 44pt。
- 如果用户仍感觉顶部视觉不够自然，下一步应微调小格圆角和黑色 opacity，而不是扩大成整条。
