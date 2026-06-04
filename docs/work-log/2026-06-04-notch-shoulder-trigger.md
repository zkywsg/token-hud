# 2026-06-04 Notch Shoulder Trigger

## 背景

用户指出 collapsed 左右小格靠近刘海的一侧是直角，没有考虑真实刘海底部左右圆角，导致小格和刘海之间出现蓝色镂空缝隙。同时，hover 触发展开的范围没有明确标识，用户不知道该摸哪里。

## 关键决策

- 不把整条菜单栏都设为触发区，避免重新引入误触。
- 保留左右小格，但补充 notch shoulder cap，用黑色圆角过渡块遮住刘海圆角外侧的缝隙。
- 给每个小格增加低透明短 handle，作为明确的可触发视觉标识。
- 交互 hitbox 比可见小格更大：可见小格仍为 44pt，hover hitbox 扩到 72pt。

## 修改范围

- `Sources/token_hudCore/NotchGeometryCalculator.swift`
  - `NotchHostedSurfaceLayout` 增加 `leftShoulder` / `rightShoulder`。
  - 新增 `notchShoulderWidth = 12`、`notchShoulderDrop = 10`、`collapsedTriggerHitPadding = 14`。
  - `hostedSurfaceLayout` 计算左右 shoulder rect，贴住 notch gap 两侧并向下覆盖 10pt。
  - `notchHoverRegions` 使用 14pt padding，扩大 hover hitbox。
- `Tests/token_hudCoreTests/NotchGeometryCalculatorTests.swift`
  - 新增 shoulder cap 位置和尺寸测试。
  - 新增 hover hitbox 宽度大于可见 pill 的测试。
- `token_hud/Overlay/NotchHostedSurfaceView.swift`
  - 新增 `NotchShoulderCapShape`。
  - 绘制左右 shoulder cap。
  - 在左右小格底部增加短 handle。
- `token_hud/Overlay/NotchHostPanelManager.swift`
  - hosted hit mask 纳入 left/right shoulder。

## 验证结果

- `swift test --filter NotchGeometryCalculator` 通过，49 个测试通过。
- `swift test` 通过，112 个测试通过。
- `xcodebuild -project ../token_hud.xcodeproj -scheme token_hud -destination 'platform=macOS' build` 通过。

## 后续注意

- 真机重点看 shoulder cap 是否足够遮住刘海圆角缝隙；如果仍露缝，优先微调 `notchShoulderWidth` / `notchShoulderDrop`。
- handle 的透明度如果太明显，会破坏刘海融合感；如果太弱，触发标识不清楚，需要真机取中间值。
- hover hitbox 现在为 72pt 宽，若仍难触发，可以继续加 padding；若误触变多，则减小 padding。
