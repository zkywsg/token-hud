# Notch Overlay 开源调研与技术路线

日期：2026-05-29

## 背景

当前 `token-hud` 的 notch 融合效果仍停留在菜单栏下方，无法覆盖刘海左右两侧的菜单栏区域。用户目标是：吸附后浮窗看起来像从 MacBook 刘海区域弹开，并且内容能够进入顶部菜单栏区域，而不是只在屏幕可用工作区内显示。

这份文档记录本轮对开源 notch / Dynamic Island 类项目的调研结论，用于支撑后续 `PLAN.md` 中的实现路线。

> 2026-06-04 补充：更完整的开源项目清单、源码入口、动画/hover/compact slot 技术细节已沉淀到 `docs/notch-dynamic-island-implementation-reference.md`。后续继续改刘海融合效果时，优先阅读那份参考档案，再决定是否需要重新联网搜索。

## 调研项目

- Boring Notch: `https://github.com/TheBoredTeam/boring.notch`
- Atoll: `https://github.com/Ebullioscopic/Atoll`
- SuperIsland: `https://github.com/shobhit99/SuperIsland`
- DynamicNotch: `https://github.com/jackson-storm/DynamicNotch`
- OpenNook: `https://github.com/glendonC/opennook`
- DynamicNotchKit: `https://github.com/MrKai77/DynamicNotchKit`
- VibeHub: `https://github.com/mtunique/VibeHub`

## 关键结论

### 1. 真正强融合的项目依赖 SkyLight / CGS 私有 Space

Boring Notch、Atoll、DynamicNotch 都不是只靠普通 `NSPanel` 的 y 坐标调整来进入菜单栏区域。

共同做法：

- 使用 borderless / nonactivating 的 `NSPanel` 或 `NSWindow`。
- 窗口 level 通常在 `.mainMenu + 3` 附近。
- 设置 `.canJoinAllSpaces`、`.stationary`、`.fullScreenAuxiliary`、`.ignoresCycle` 等 collection behavior。
- 通过私有 SkyLight / CGS API 创建一个 absolute level 极高的 Space，常见值是 `2_147_483_647`。
- 把 notch window 加入这个私有 Space，让它获得高于普通菜单栏窗口层级的显示能力。

这说明“进入菜单栏/刘海区域”不是普通 SwiftUI layout 问题，而是 WindowServer 层级和 Space 归属问题。

### 2. 公开 API 路线只能作为近似效果

SuperIsland 更接近公开 API 路线：

- 使用透明 `NSPanel`。
- 使用 `.statusBar` 级别。
- 通过单个较大的 hosting surface 承载 SwiftUI 内容。

这条路线更安全，但它本质上仍受公开 AppKit window level 限制。对于“必须在菜单栏区域、刘海左右两侧显示内容”的目标，不能承诺 100% 达成。

### 3. 多窗口 bridge 方案依据不足

此前计划里的“左 bridge + 右 bridge + body”多窗口方案应该废弃。

原因：

- 开源项目普遍不是这么做的。
- 如果普通 window 本身被系统菜单栏遮挡，拆成多个普通 window 也不会解决根因。
- 多窗口拼接容易产生 seam、动画不同步、点击区域错位和多屏定位问题。

更合理的架构是单个 top-centered notch surface，由窗口层级解决菜单栏覆盖能力，由 SwiftUI 在同一 surface 内完成展开、收缩和内容布局。

### 4. 几何计算仍然重要，但不是核心瓶颈

需要继续保留并加强：

- 使用 `screen.frame` 而不是 `visibleFrame` 计算 hosted top edge。
- 读取 `safeAreaInsets.top`、`auxiliaryTopLeftArea`、`auxiliaryTopRightArea` 判断 notch 和菜单栏区域。
- 使用稳定 display id 选择目标屏幕。
- 监听屏幕参数变化后重建或重定位 overlay。

但如果没有 SkyLight / CGS 层级能力，几何计算再准确也只能把 window 请求到菜单栏区域，不能保证实际可见。

## 推荐路线

后续实现应采用 `NotchSurfaceStrategy`：

1. `skyLightSpace`
   - 默认优先尝试。
   - 通过 `dlopen` 动态加载 SkyLight 私有符号。
   - 创建 absolute level `2_147_483_647` 的 notch surface。
   - 把单个 top-centered hosted window 加入该 Space。

2. `publicPanel`
   - 私有 API 不可用或用户选择兼容模式时降级。
   - 使用公开 AppKit window level。
   - 明确标记为近似效果，不承诺完全菜单栏融合。

## 风险

- SkyLight / CGS 是私有 API，可能影响 App Store 分发、系统兼容性和未来 macOS 版本稳定性。
- GPL 项目的源码只能用于理解架构，不能直接复制进本仓库。
- 过高 window / Space level 可能遮挡系统 UI，hosted collapsed 状态需要控制视觉尺寸和事件区域。

## 对当前计划的影响

`PLAN.md` 已改为：

- 废弃三窗口 bridge。
- 新增 SkyLight / CGS wrapper。
- 使用单个 top-centered `NotchSurfaceWindow`。
- 增加 public fallback。
- 加强诊断日志，明确记录当前 strategy、requested frame、actual frame 和 Space delegation 状态。
