# 2026-05-29 SkyLight Notch Surface

## 背景

用户确认继续按开源调研后的路线解决 notch / 菜单栏融合问题。此前方案把 hosted overlay 推到 `screen.maxY + safeAreaTop`，导致真正的 topBridge 很可能被推到屏幕上方，用户看到的仍是菜单栏下方的黑块。

## 关键操作

- 更新 `NotchGeometryCalculator.notchFrames`，让 collapsed / expanded hosted frame 的 `maxY` 锚定 `screen.frame.maxY`。
- 更新几何测试，覆盖 notched display 和 auxiliary top edge 超出 screen frame 时不再 overshoot。
- 新增 `NotchSurfaceStrategy`，区分 `skyLightSpace` 和 `publicPanel`。
- 新增 `SkyLightNotchSpace`：
  - 使用 `dlopen` 动态加载 SkyLight。
  - 尝试加载 `SLSMainConnectionID`、`SLSSpaceCreate`、`SLSSpaceSetAbsoluteLevel`、`SLSShowSpaces`、`SLSSpaceAddWindowsAndRemoveFromSpaces`。
  - 创建 absolute level `2_147_483_647` 的 notch Space。
  - hosted overlay 显示前尝试将 window delegate 到该 Space。
- 新增 `NotchSurfaceWindow`，hosted surface 不能成为 key/main window。
- `NotchHostPanelManager` 改为：
  - hosted overlay 使用 `.borderless`、`.nonactivatingPanel`、`.utilityWindow`、`.hudWindow`。
  - SkyLight 可用时使用 `.mainMenu + 3` level。
  - SkyLight 不可用时 fallback 到 `.screenSaver` public panel。
  - 诊断日志输出 strategy、SkyLight availability、space id、delegate return code、requested frame、actual frame。
  - 通过 display id 记忆目标屏幕，并优先选择带 notch 的屏幕。
- 将新 Swift 文件加入 `token_hud.xcodeproj` source build phase。

## 验证结果

- `swift test` 通过，98 个测试通过。
- `xcodebuild -project ../token_hud.xcodeproj -scheme token_hud -destination 'platform=macOS' build` 通过。

## 后续注意事项

- 需要用户真机运行后查看日志：
  - `notchSurfaceStrategy` 应优先为 `skyLightSpace`。
  - `overlayDelegatedToSkyLight` 应为 `true`。
  - `actualFrame.maxY` 应等于目标 `screen.frame.maxY`。
- 如果 SkyLight 可用但仍不能覆盖菜单栏，优先排查 Space delegation 是否真实生效，而不是继续调整 y 坐标。
- SkyLight / CGS 属于私有 API，不适合 App Store 分发；公开分发时应保留 `publicPanel` fallback。

