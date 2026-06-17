# App Health Pass: Animation, Overflow, Repeated Actions

## Context

用户要求对整个 app 做一次深度体检，重点关注动画不连贯、页面溢出，以及启动或重复操作时可能出现的 bug。

## Findings

- `NotchHostPanelManager.toggle()` 隐藏窗口时只移除了 mouse move monitors，没有统一清理 pending collapse timer、mouseDown/mouseUp monitor 和 drag state。隐藏前排队的 collapse work item 有机会在窗口隐藏后继续触发状态转换。
- `switchToDetached()` 需要取消 collapse 和 mouseDown，但不能清理 mouseUp 或重置 `isDragging`。否则会破坏之前用于避免写入 transient detached frame 的保护。
- `NotchHostRootView` 还对 `expansionProgress` 叠加了一层隐式 animation，而 manager 已经用 `withAnimation` 显式驱动同一个值，容易让展开/收起节奏显得不干净。
- `PlatformListView` 的刷新按钮没有 per-platform in-flight guard，连续点击可能启动多个刷新任务；`resetMessage` 的多个延迟清理也可能互相覆盖。
- `StateWatcher` 缺文件重试缺少 generation token；stop/start 或路径切换后，旧的 retry closure 仍可能进入新一轮生命周期。
- `StateWatcher.stop()` 取消 dispatch source 后又立即 close fd，而 source cancel handler 也 close 同一个 fd，存在重复 close 风险。
- Settings window 和部分页面布局仍有固定尺寸/固定宽度，长文本、状态 pill 和 header action 在窄窗口下有溢出风险。
- `KeyRecorder` 缺少 `onDisappear` 清理 local monitor，关闭设置页时可能留下录制监听。

## Decisions

- 新增 `NotchPanelLifecyclePolicy` 作为 core 纯逻辑策略，明确不同生命周期事件需要清理哪些 timer/monitor/drag state。
- `NotchHostPanelManager` 使用统一 cleanup 入口处理 hide、teardown 和 switch-to-detached。
- hosted 展开/收起只保留 manager 中的显式 spring，移除 root view 的重复隐式 animation，并集中 spring 参数。
- `PlatformListView` 增加 per-platform `refreshingPlatformIDs`，同平台刷新进行中会忽略后续点击。
- `resetMessage` 使用 `NotchTransitionGate` token，旧延迟清理不能清掉新消息。
- `StateWatcher` 使用 `NotchTransitionGate` invalidation 保护缺文件重试；dispatch source cancel 后不再立即重复 close fd。
- Settings window 改为 900x620 默认大小和 760x560 最小大小；SwiftUI root 改为 min/ideal/max 自适应 frame。
- 平台页 status pills、InfoRow、小组件页 header 和推荐 chip 增强换行/截断策略。
- `KeyRecorder` 在 disappear 和清除快捷键时停止录制并移除 monitor。

## Verification

- `swift test --filter NotchSurfacePolicy`：19 tests passed。
- `swift test --filter NotchGeometryCalculator`：50 tests passed。
- `swift test --filter Widget`：37 tests passed。
- `swift test`：153 tests passed。
- `xcodebuild -project token_hud.xcodeproj -scheme token_hud -destination 'platform=macOS' build`：BUILD SUCCEEDED。

## Manual Checks Still Needed

- 快速打开/隐藏浮窗，确认隐藏后不会被旧 collapse timer 拉回前台。
- 快速 hover 刘海、移出、再 hover，确认展开/收起没有跳动或重影。
- expanded body 拖动到 detached，再吸附回刘海，确认 drag state 不残留。
- 在平台页连续点击刷新/授权刷新，确认按钮和提示稳定。
- 缩窄 Settings window，检查平台页和小组件页是否仍有文字重叠或横向撑破。
