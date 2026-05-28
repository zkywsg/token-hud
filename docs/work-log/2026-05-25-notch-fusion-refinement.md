# Notch Fusion Refinement

## 背景

上一轮刘海融合态已经实现基础 docked/free 视觉切换，但审查发现首次吸附目标没有使用真实刘海 auxiliary areas，且吸附态只在 SwiftUI 层隐藏 resize grip，没有在 AppKit 窗口层面锁定 resize 能力。本次返工目标是让吸附态更接近“顶到状态栏并与刘海融为一体”的产品要求。

## 关键操作

- 扩展 `PanelDockingCalculator.dockState`：
  - 新增 `auxiliaryTopLeftArea` / `auxiliaryTopRightArea` 参数，默认值为 `.null`。
  - 触发吸附时用真实 auxiliary areas 计算 `notchFusedFrame`，避免首次吸附退回 200pt fallback 宽度。
- 修改 `FloatingPanelManager.evaluateDocking()`：
  - 从当前 `NSScreen` 读取 `auxiliaryTopLeftArea` 和 `auxiliaryTopRightArea`。
  - 将真实 auxiliary areas 传入 `dockState`，让拖拽释放后的吸附 frame 覆盖刘海 gap。
- 增加窗口层面的 docked/free style 切换：
  - free 状态使用 `.borderless + .resizable + .nonactivatingPanel`。
  - docked 状态使用 `.borderless + .nonactivatingPanel`，移除 `.resizable`。
  - 分离后通过 `applyFreeStyle()` 恢复 resize 能力。
- 更新测试：
  - 新增 `dockStateWithAuxAreasProducesFusedWidth`，验证 `dockState` 在传入 real auxiliary areas 后返回 gap + side padding 的 fused target frame。

## 关键决策

- `notchFusedFrame` 继续保持 top-flush：`target.maxY == screenFrame.maxY`。
- docked 高度继续固定为 60pt，dock 视觉比例不再跟随用户自由浮窗缩放。
- `dockedSidePadding` 暂定 40pt；如果真实机器上仍有左右空隙，应优先根据实测刘海边界调这个值，或改成更激进的覆盖策略。
- `windowDidResize` 保留 docked 状态的防御性 undock 逻辑，但正常路径下 docked style 已阻止 resize。

## 验证结果

- `swift test` 通过：82 个测试通过。
- `xcodebuild -project ../token_hud.xcodeproj -scheme token_hud -destination 'platform=macOS' build` 通过。
- 工程引用检查：
  - `PanelDockingCalculator.swift` 已在 Xcode project sources 中。
  - `PanelDockState.swift` 已在 Xcode project sources 中。
  - 未发现 `server.pid` 或 `widget-settings-layout` 等临时文件进入 pbxproj。

## 后续注意事项

- 仍需要在带刘海 MacBook 真机上肉眼确认 40pt side padding 是否足够覆盖刘海左右边界。
- 如果仍觉得不像“融为一体”，下一步应从视觉参数继续收紧：
  - 增大 `dockedSidePadding`。
  - 降低 bottom corner radius。
  - 提高黑色背景不透明度。
  - 根据状态栏/刘海实际高度重新评估 `dockedHeight`。
- 多屏无刘海场景仍使用 fallback 居中 200pt 宽度，不应误认为真实刘海融合态。
