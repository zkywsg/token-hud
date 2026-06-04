# 2026-05-31 Notch Drag Settle

## 背景

用户反馈拖拽刘海展开态 `NotchFusionView` 后，面板每次会停在不同位置，视觉上像是定位随机跑偏。

## 根因

expanded hosted overlay 允许 `isMovableByWindowBackground = true`，用户拖动时系统会直接移动 overlay window。旧逻辑只在 `windowDidMove` 中检测是否超过 detach 阈值；如果没有超过阈值，就不会切回 detached，也不会回弹到刘海的 canonical frame。这样 overlay 会保留临时偏移位置，后续 hover 展开/收起动画又从这个偏移 frame 开始。

## 关键改动

- 新增 `NotchHostedDragResolution` 和 `NotchGeometryCalculator.hostedDragResolution(panelFrame:collapsedFrame:)`。
- hosted 拖拽改为 mouse-up 统一结算：
  - 小幅偏移：回弹到当前模式的 canonical frame。
  - 向下或横向超过阈值：切回 detached。
- `windowDidMove` 在 hosted 拖拽中不再立即切换状态，避免拖动过程中状态和 frame 互相抢控制权。
- 从 detached 吸附到 notch 时，overlay 显示前先设置到 `frames.collapsed`。
- hover 展开前，如果 collapsed frame 有残留偏移，先校正到 canonical collapsed frame。
- screen 参数变化时，hosted overlay 按当前 collapsed/expanded 模式回到对应 canonical frame。

## 验证结果

- `swift test --filter NotchGeometryCalculator` 通过，39 个测试通过。
- `swift test` 通过，102 个测试通过。
- `xcodebuild -project ../token_hud.xcodeproj -scheme token_hud -destination 'platform=macOS' build` 通过。

## 后续注意

- 真机重点验证连续多次 hover 展开时 expanded 是否始终居中对齐刘海。
- 小幅拖动 expanded 后应回弹，不再停在偏移位置。
- 明显向下拖动应切回 detached；如果手感不合适，再单独调整 detach 阈值。
