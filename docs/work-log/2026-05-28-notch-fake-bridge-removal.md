# Notch Fake Bridge Removal

## 背景

真机截图显示，拖拽到刘海区域后只剩左右黑块和一条很薄的黑色底边，业务内容完全不可见。排查后确认这不是简单坐标问题，而是当前架构混合了两套方案：

- 旧 `NSPanel` 仍在 `NotchFusionView` 里画 full-width menu bar bridge。
- 吸附后状态进入 collapsed，`expansionProgress = 0`，业务内容 opacity 也变为 0。
- 新的 `MenuBarBridgeProbe` 是独立 spike，没有承接拖拽吸附状态。

## 关键决策

主 `NSPanel` 不再负责菜单栏左右 bridge。它只负责刘海下方 body：

- collapsed：极薄 body，位于屏幕工作区顶部下方。
- expanded：完整内容 body，位于屏幕工作区顶部下方。
- 菜单栏融合效果后续只能由 menu bar layer 验证和承接，不能继续用普通 panel 假装覆盖菜单栏。

## 关键操作

- 更新 `NotchGeometryCalculator.notchFrames`：
  - collapsed / expanded frame 不再加 `menuBarHeight`。
  - frame top 不再超过 `screenFrame.maxY`。
  - hosted frame 不再全屏宽度，而是以刘海中心为锚点计算 body 宽度。
- 更新 `NotchGeometryCalculator.notchFusionLayout`：
  - 返回空的 `leftBridge` / `rightBridge`。
  - body 从本地坐标 `y = 0` 开始展开。
  - 内容 opacity 直接跟随 expansion progress。
- 更新 `NotchFusionView`：
  - 移除主 panel bridge 绘制。
  - 使用当前 hosting view 的本地尺寸计算 body layout。
- 更新 `NotchHostPanelManager`：
  - 拖拽释放吸附成功后进入 expanded，避免直接停在不可见内容的 collapsed 黑条。
  - expanded 动画结束后安装全局 mouse monitor，后续仍可根据鼠标离开收回。
- 更新 `NotchGeometryCalculatorTests`：
  - 覆盖 hosted panel 不跨菜单栏。
  - 覆盖 hosted panel 不再全屏画 bridge。
  - 覆盖 body 在刘海下方展开。

## 验证结果

- `swift test --filter NotchGeometryCalculator` 通过，34 个 Notch 几何测试通过。
- `swift test` 通过，97 个测试通过。
- `xcodebuild -project ../token_hud.xcodeproj -scheme token_hud -destination 'platform=macOS' build` 通过。

## 后续注意

这轮解决的是“假 bridge + 空黑条”的错误状态，不代表已经实现完整菜单栏融合。下一步仍需要真机确认：

- 拖到刘海附近后是否能看到 expanded 内容反馈。
- 左右黑块是否已消失。
- `MenuBarBridgeProbe` 是否能在真实菜单栏内提供可用的融合基础。
