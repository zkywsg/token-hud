# Pure Black Compact Pro

## Context

用户从纯黑 A/B/C/D 视觉预览中选择 C：Compact Pro。此前 Dynamic Island 磨砂方案仍然显得不够统一，且用户明确希望主 UI 方向改为纯黑实色背板，不使用透明或磨砂作为主要质感。

## Decisions

- 本轮不做完整主题系统，只建立纯黑基础版。
- 主面板背景使用纯黑或接近纯黑实色，不再用 `.thinMaterial`、`.regularMaterial`、`.ultraThinMaterial` 作为顶部 HUD、Settings 小组件页或浮窗的主要背景。
- 精致感主要由字重、间距、8-10pt 紧凑圆角、hairline 描边和少量状态色构成。
- 顶部 hosted HUD 保持现有窗口 frame、hover、拖拽脱离、动态高度和吸附逻辑不变。
- Settings 小组件页保留现有信息结构和操作能力：推荐组件、当前效果分组、删除、拖拽排序、添加预设。

## Modified Areas

- `token_hud/Overlay/NotchHostedSurfaceView.swift`
  - 顶部 cap 和 expanded body 改为纯黑实色。
  - 移除主要背景材质和渐变高光。
  - 信息耳朵改为纯黑体系下的低调轻描边状态槽。
- `token_hud/Overlay/FloatingPanelView.swift`
  - detached 浮窗外壳改为纯黑实色。
- `token_hud/Settings/WidgetListEditor.swift`
  - 新增局部 `CompactBlackTheme` / `compactBlackPanel`。
  - 推荐组件、当前效果、组件 chip、已添加列表和添加预设卡片统一为纯黑 Compact Pro 样式。
- `token_hud/Settings/SettingsWindow.swift`
  - Settings 背景、详情区、侧边栏从磨砂/渐变改为纯黑或近黑实色。

## Verification

- `swift test --filter NotchSurfacePolicy`：25 tests passed.
- `swift test --filter NotchGeometryCalculator`：53 tests passed.
- `swift test`：167 tests passed.
- `xcodebuild -project token_hud.xcodeproj -scheme token_hud -destination 'platform=macOS' build`：BUILD SUCCEEDED.
- `git diff --check`：通过。

## Manual Checks Still Needed

- 真机查看顶部 HUD 收起、展开、再次展开后的刘海贴合和纯黑质感。
- Settings 小组件页当前效果区在组件多、模型多、窗口缩窄时是否无溢出。
- 独立浮窗从刘海拖出后是否与纯黑方向保持一致。
