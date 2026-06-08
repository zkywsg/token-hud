# 2026-06-07 Widget Recommendations And Notch Collapsed Sources

## 背景

用户希望 Settings 能明确显示哪些平台已配置，并把已配置平台对应的小组件放到更前面或默认加入当前小组件。同时，刘海 hosted 收起态原先只能自动取当前小组件列表中第一个可计算百分比的组件，无法单独调整左侧进度条和右侧百分比。

## 关键决策

- 已配置平台推荐逻辑放到 `Sources/token_hudCore/WidgetConfiguration.swift`，避免 Settings 和 Notch view 各自写一套判断。
- OpenAI、Gemini、Anthropic 普通 API key 只代表调用验证，不默认生成用量组件，避免“已配置但无数据”的困惑。
- Codex、Claude、DeepSeek、MiniMax、MiMo 这类有明确本地或用量路径的平台会生成推荐组件。
- Settings 中“补齐推荐”把缺失推荐插到当前小组件列表最前面，但不会覆盖用户已有排序。
- 刘海收起态只开放左右 slot 来源选择，不做颜色、宽度、字体等细粒度设置，避免把 Settings 复杂度拉高。
- 收起态来源写入 `UserDefaults`：
  - `notchCollapsedLeadingSource`
  - `notchCollapsedTrailingSource`
  - raw value 支持 `auto`、`widget:<uuid>`、`metric:<service>:<metric>:<quotaIndex>`。

## 修改范围

- `Sources/token_hudCore/WidgetConfiguration.swift`
  - 新增 `WidgetDescriptor`、`WidgetRecommendationEngine`、`NotchCollapsedStatusConfiguration`、`NotchCollapsedStatusEngine`。
- `Tests/token_hudCoreTests/WidgetRecommendationTests.swift`
  - 覆盖已配置平台推荐和补齐去重。
- `Tests/token_hudCoreTests/NotchCollapsedStatusTests.swift`
  - 覆盖左右 slot 独立计算和缺失来源回退。
- `token_hud/Settings/WidgetListEditor.swift`
  - 新增“已配置推荐”和“刘海收起态”设置区域。
- `token_hud/Settings/PlatformListView.swift`
  - 平台侧边栏显示已配置数量，并把已配置平台排序到前面。
- `token_hud/Overlay/NotchHostedSurfaceView.swift`
  - 收起态改为读取左右 slot 配置。
- `token_hud/Widgets/*`
  - 微调 bar/text/status/aggregate 的字号、状态色和数字显示。

## 验证

- `swift test --filter Widget` 通过。
- `swift test --filter NotchCollapsedStatusTests` 通过。
- `swift test` 通过，142 个测试。
- `xcodebuild -project token_hud.xcodeproj -scheme token_hud -destination 'platform=macOS' build` 通过。

## 注意事项

- 本机 `xcodegen generate` 写入现有 `token_hud.xcodeproj` 时返回 “item with the same name already exists”，本轮手动把新增 Swift 文件加入 pbxproj。后续如果 `xcodegen` 恢复正常，可重新生成并检查 pbxproj 是否只保留等价文件引用。
- 真机仍需验证 Settings 小组件页的实际滚动高度和刘海 compact 小格中文字是否拥挤。
