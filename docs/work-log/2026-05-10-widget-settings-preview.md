# Widget Settings Preview

## 背景

本次优化 Settings 的小组件页面，让用户在配置小组件时可以直接看到当前配置渲染后的 HUD 效果。用户确认采用“预览优先”方向：上方展示完整当前效果，下方保留管理和添加能力。

## 关键操作

- 重组 `token_hud/Settings/WidgetListEditor.swift`。
- 新增顶部 `WidgetPreviewPanel`，复用 `WidgetRenderer` 和 `StateWatcher.effectiveState` 渲染当前 `WidgetStore.widgets`。
- 将下方区域拆成：
  - `ActiveWidgetsPanel`：查看已添加组件、删除、拖拽排序、空状态 drop zone。
  - `AddWidgetsPanel`：紧凑 preset grid，支持点击添加和拖拽添加。
- 保留自定义组件 sheet、恢复默认、现有 `WidgetConfig`/`WidgetStore` 持久化逻辑。

## 关键决策

- 不改 widget 数据模型和 overlay 渲染行为，只在 Settings 页面复用现有渲染器。
- 预览区使用深色背景承载 `WidgetRenderer`，避免 overlay 组件的白色文字在浅色设置页中不可读。
- 预设卡片支持点击添加，降低只依赖拖拽的操作成本；拖拽仍可用于把预设放到预览区或已添加列表。

## 验证结果

- `swift test` 通过：63 个 Swift Testing 测试通过。
- `xcodebuild -project token_hud.xcodeproj -scheme token_hud -destination 'platform=macOS' build` 通过。

## 后续注意事项

- 后续如果增加新的 widget style 或 metric，需同步更新设置页里的图标映射。
- 当前设置页预览按一行横向滚动显示全部组件；如果未来 widget 数量显著增加，可以再考虑加入分组预览或紧凑/分组模式切换。
