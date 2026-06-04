# Notch Policy Cleanup

日期：2026-06-04

## 背景

按 `docs/notch-dynamic-island-implementation-reference.md` 复查当前 hosted notch 实现后，发现主视觉路线已回到单一 surface，但仍有三个实现风险：

- SkyLight / CGS 返回码没有被严格判断，日志可能误报 delegate 成功。
- hosted public fallback 使用 `.screenSaver`，比成熟公开路线更激进。
- 旧 `NotchFusionView` / collapsed / expanded / ear 视图仍在工程中，容易让后续实现回到旧模型。

## 处理结果

- 新增 `Sources/token_hudCore/NotchSurfacePolicy.swift`：
  - `SkyLightReturnCodePolicy`
  - `NotchSurfaceLevelPolicy`
  - `NotchTransitionPolicy`
  - `NotchTransitionGate`
- `SkyLightNotchSpace` 现在记录 `setAbsoluteLevelReturnCode`、`showSpacesReturnCode` 和 `lastDelegateReturnCode`，只有返回码成功时才认为 Space setup / delegate 成功。
- `NotchSurfaceStrategy.publicPanel` 从 `.screenSaver` 降到 `.statusBar`，作为明确的公开 API fallback。
- `NotchHostPanelManager` 在 SkyLight delegate 失败时降级到 public fallback，并用 generation token 防止旧 collapse timer 覆盖新的 hover 状态。
- 删除旧 hosted 路线文件：
  - `NotchFusionView.swift`
  - `NotchCollapsedView.swift`
  - `NotchExpandedView.swift`
  - `NotchEarView.swift`

## 注意

`xcodegen generate` 本轮在已有 `token_hud.xcodeproj` 上报 “item with the same name already exists”，因此没有强行删除工程目录，而是手动最小更新 `project.pbxproj`。后续如果 `project.yml` 变化，仍应优先尝试重新生成工程。

## 验证

- `swift test --filter NotchSurfacePolicyTests`：11 个测试通过。
- `swift test --filter NotchGeometryCalculator`：45 个测试通过。
- `swift test`：119 个测试通过。
- `xcodebuild -project ../token_hud.xcodeproj -scheme token_hud -destination 'platform=macOS' build`：通过。
