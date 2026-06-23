# 刘海展开高度自适应与分组切换

## 背景

刘海 hosted 展开态原先使用固定 `expandedHeight = 110`。当 grouped 内容里的服务/模型数量变多时，`NotchHostedSurfaceView` 会通过 `adaptiveScale` 把整块内容压缩，导致字体越来越小。

本轮目标是保留顶部刘海锚点和 `expansionProgress` 动画模型，同时让展开 body 能按内容增高，并提供一个中等高度的分组切换模式。

## 实现

- 新增 `NotchExpandedLayoutPolicy`：
  - `adaptive`：默认模式，按服务数量计算 body 高度，字体 scale 固定为 `1`。
  - `sectioned`：中等高度模式，使用服务切换减少同屏内容。
  - 高度有屏幕比例上限，超过后启用内部滚动。
- `NotchGeometryCalculator.notchFrames(...)` 和 `hostedSurfaceLayout(...)` 新增 `expandedBodyHeight` 默认参数：
  - 旧调用保持兼容。
  - app 侧可以传入动态 body 高度。
- `NotchHostPanelManager`：
  - 根据 `WidgetStore` 当前 widgets 和 `notchExpandedLayoutMode` 计算动态高度。
  - 监听 `UserDefaults.didChangeNotification` 和 `WidgetStore.widgetsDidChangeNotification`，在设置或小组件变化时刷新 hosted frame。
  - hit mask、expanded surface hover、detach target 均使用同一份动态高度。
- `NotchHostedSurfaceView`：
  - 使用 `hostState.expandedContentScale`，不再按行数压缩字体。
  - adaptive 超出上限时使用内部纵向滚动。
  - sectioned 模式渲染 `SectionedOverlayView`。
- Settings：
  - 新增“刘海展开布局”分段选择。
  - 默认值为“自适应高度”，可切换到“分组切换”。

## 验证

- `swift test --filter NotchExpandedLayoutPolicy`：通过。
- `swift test --filter NotchGeometryCalculator`：通过，52 个测试通过。
- `swift test`：通过，159 个测试通过。
- `xcodebuild -project token_hud.xcodeproj -scheme token_hud -destination 'platform=macOS' build`：通过。
- `git diff --check`：通过。

## 注意

- `xcodebuild` 仍会生成 `token_hud.debug.dylib`，因为前一项 “Xcode 运行时 LLDB attach failed 修复” 计划尚未执行；这不影响本轮 build 验证，但如果需要从 Xcode 直接 Run 调试，仍建议先执行该配置修复。
- `token_hud.xcodeproj/project.pbxproj` 是显式文件列表，本轮已手动加入 `NotchExpandedLayoutPolicy.swift` 和 `SectionedOverlayView.swift`。
