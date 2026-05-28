# Hybrid Dynamic Notch V1

## 背景

上一轮真机截图显示，普通 `NSPanel` 不能实现进入菜单栏并与刘海完全融合。项目路线已调整为 Hybrid Dynamic Notch：主体验放在刘海下方，由 `NSPanel` 稳定负责 docked collapsed、expanded 和 detached 状态；菜单栏层只作为可选增强。

## 关键操作

- 将 `NotchGeometryCalculator.collapsedBodyHeight` 从 8pt 调整为 22pt，让 docked collapsed 不再像悬空黑线。
- 在 `NotchGeometryCalculator.notchFusionLayout` 中增加内容延迟淡入：
  - `contentFadeStartProgress = 0.55`
  - 展开早期内容 opacity 保持 0，避免文字从过小胶囊中挤出。
- 更新 `NotchFusionView`：
  - 使用 layout 计算出的 `contentOpacity`。
  - collapsed 胶囊底部圆角按高度自适应。
  - expanded 阶段才逐渐显示内容和阴影。
- 更新 `NotchHostPanelManager`：
  - 吸附成功后先进入 expanded 反馈。
  - expanded 反馈结束后，如果鼠标不在刘海区域，约 1 秒后收回 collapsed。
- 更新 `MenuBarBridgeProbe`：
  - 默认关闭，避免启动时显示误导性的黑色菜单栏测试条。
- 更新 `NotchGeometryCalculatorTests`：
  - 覆盖 22pt collapsed 胶囊高度。
  - 覆盖内容延迟淡入规则。

## 验证结果

- `swift test --filter NotchGeometryCalculator` 通过，35 个 Notch 几何测试通过。
- `swift test` 通过，98 个测试通过。
- `xcodebuild -project ../token_hud.xcodeproj -scheme token_hud -destination 'platform=macOS' build` 通过。

## 后续注意

- 真机需要确认 collapsed 胶囊是否足够贴近刘海，是否仍显得悬空。
- 如果 22pt 胶囊仍太薄或太突兀，下一轮优先微调高度、宽度、底部圆角和 expanded 动画时长。
- 不应重新启用主 panel 的菜单栏 bridge；那条路线已确认会产生错误视觉。
