# Dynamic Island Visual System

## Context

用户在 A/B/C/D 视觉方案预览中选择 B：Dynamic Island 一体化。目标是让顶部刘海 HUD、Settings 小组件页、推荐组件和当前效果预览使用更统一的岛状磨砂语言。

## Decisions

- 顶部 hosted HUD 继续保持单一 surface 架构，不改变 frame、hover、拖拽脱离或动态高度策略。
- 左右信息耳朵不再强化为独立贴片；展开态降低胶囊底和描边存在感，让状态内容融进 top cap。
- top cap 与 body 使用更接近的深色磨砂覆盖和高光，减少“黑色矩形 + 独立胶囊”的拼接感。
- Settings 小组件页新增局部 `islandPanel` 样式 helper，只服务该页面，不做全局主题重构。
- 推荐组件、刘海收起态配置、当前效果预览、已添加/添加区域统一更大的圆角、更轻的描边和半透明材质。
- 当前效果预览从纯黑块改为深色半透明磨砂预览区。

## Modified Areas

- `token_hud/Overlay/NotchHostedSurfaceView.swift`
  - 调整 top cap / body 颜色、高光、描边和信息耳朵嵌入感。
- `token_hud/Settings/WidgetListEditor.swift`
  - 统一小组件页面板、推荐 chip、当前效果预览、预设卡片和列表背景。
- `token_hud/Settings/SettingsWindow.swift`
  - 轻调 Settings 背景、分隔线和侧边栏选中态圆角，使其更贴近岛状语言。

## Verification

- `swift test`：167 tests passed.
- `xcodebuild -project token_hud.xcodeproj -scheme token_hud -destination 'platform=macOS' build`：BUILD SUCCEEDED.
- `git diff --check`：通过。

## Manual Checks Still Needed

- 真机查看展开态 HUD 是否像连续岛体，而不是黑色矩形。
- 小组件页当前效果区是否与推荐区、刘海收起态配置区风格一致。
- 缩窄 Settings window 后，推荐 chip、当前效果 header、按钮文案是否无溢出。
