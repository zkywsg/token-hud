# 2026-06-19 Notch Re-expand Frame Drift

## 背景

用户反馈“第一次浮窗缩小之后，再重新放大，会产生不在刘海两端的效果”。上一轮只修了 detached `FloatingPanelView` 的内容顶部锚定，但没有解决第二次展开后 hosted 刘海 surface 对齐漂移。

## 根因

问题不只是 SwiftUI 内容对齐，而是 hosted window 的 frame / 拖动状态可能被污染：

- hosted expanded 状态又启用了 `isMovableByWindowBackground = true`，允许 AppKit 原生移动 overlay window。
- 历史实现曾明确要求 hosted surface 始终钉在 canonical `frames.expanded`，否则收起/展开时会按错误 window frame 绘制。
- `transitionTo(.detached)` 会先把 `hostState.mode` 改成 `.detached`，再调用 `switchToDetached()`；旧的 `detachedTargetFrame()` 里用 `hostState.isExpanded` 判断来源，因此实际会失效，容易回落到旧 `savedDetachedFrame`。
- 如果用户先把 detached 自由浮窗缩小，再从 hosted 拖出或重新吸附，旧 saved frame 可能污染下一次 detached/hosted 过渡。

## 关键改动

- 新增 `NotchWindowMovementPolicy`：
  - `.collapsed` / `.expanded` hosted 模式不可通过 AppKit background dragging 移动。
  - `.detached` 模式仍允许 background dragging。
- `NotchHostPanelManager` 所有窗口移动状态入口统一走该策略。
- `transitionTo(.detached)` 将 source mode 显式传给 `switchToDetached(from:)`，不再在 mode 已切换后判断 `hostState.isExpanded`。
- 新增 `NotchGeometryCalculator.hostedBodyDetachedFrame(...)`，用 canonical hosted body rect 计算拖出后的 detached 初始 frame。
- expanded body 拖出改为显式 drag monitor：
  - mouse down 只记录起点。
  - 拖动超过阈值才切到 detached。
  - detached window 之后按鼠标 delta 跟随，不让 hosted overlay 自己漂移。
- 状态切换时 `reassertHostedFrame(..., force: true)`，避免第二次展开沿用脏 frame。

## 验证

- `swift test --filter NotchSurfacePolicy`：通过。
- `swift test --filter hostedBodyDetachedFrameUsesCanonicalBodyRect`：通过。
- `swift test --filter NotchGeometryCalculator`：通过，53 个测试通过。
- `xcodebuild -project token_hud.xcodeproj -scheme token_hud -destination 'platform=macOS' build`：通过。

## 后续注意

- 真机重点验证：hover 展开/收起反复多次后，top cap 和 body 仍应贴在刘海两端。
- 真机重点验证：detached 缩小后吸附回刘海，再展开时不应继承 detached 的宽高。
- 如果仍有漂移，下一步应看 `[NotchDiagnostics]` 中 requested `frames.expanded` 与 actual overlay frame 是否被 SkyLight 或系统级窗口管理改写。
