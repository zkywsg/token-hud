# Notch / Dynamic Island 实现参考档案

日期：2026-06-04

## 用途

这份文档沉淀 macOS 刘海屏小组件、Dynamic Island 类 App 的开源实现思路。以后继续优化 `token-hud` 的刘海融合、收缩、展开、悬停触发和拖拽脱离时，先读这份文档，再决定是否需要重新搜索。

重点不是复制别人的源码，而是固定几条已经被多个成熟项目验证过的技术路线：

- 顶部刘海区域必须以 `screen.frame` 和 `auxiliaryTopLeftArea` / `auxiliaryTopRightArea` 为基础建模。
- 收缩态应该是一个单体 notch surface 中的左右 slot，而不是左右两个独立窗口。
- 展开态应该从同一个 surface 向下延展，不能靠拼多个黑块制造视觉假象。
- 真正进入菜单栏层级通常需要 SkyLight / CGS 私有 API；公开 AppKit window level 只能做近似效果。

## 结论先行

1. **单一 surface 是主流做法**

   Boring Notch、Atoll、DynamicNotch、OpenNook、SuperIsland 的核心视觉都不是多个黑色矩形拼接，而是单个 top-centered surface。收缩态和展开态只是同一 surface 的尺寸、shape、内容透明度和 hit area 变化。

2. **左右状态条要放在同一个 compact layout 里**

   正确模型是：

   - 中间保留物理刘海宽度作为 `notchGap`。
   - 左侧 slot 放进度条、服务名、剩余时间等摘要。
   - 右侧 slot 放百分比、状态文本、错误标记等摘要。
   - slot 和 notch gap 属于同一个 shape，不应该拆成两个独立 panel。

3. **菜单栏融合不是 y 坐标问题**

   如果 window 已经请求到 `screen.frame.maxY` 附近，但刘海两侧菜单栏区域仍不可见，继续微调 y 值通常没有意义。根因更可能是 window level、Space 归属或系统菜单栏遮挡。Boring Notch、Atoll、DynamicNotch 都使用或预留了 SkyLight / CGS 方案。

4. **公开 API 可以做稳定 fallback，但不能承诺完全融合**

   SuperIsland、OpenNook 的公开路线更安全：透明 `NSPanel`、高 window level、全 Space 行为、单个 SwiftUI surface、精确 notch geometry。它能让视觉接近刘海，但在某些菜单栏/全屏/系统 UI 场景下不一定能真正压过系统层。

5. **窗口尺寸和 SwiftUI 内容尺寸要分离**

   SuperIsland 和 DynamicNotch 都有“固定大画布 + window 作为裁剪 viewport”的思想。这样收缩/展开时 SwiftUI 内容不会因为 window resize 重新布局导致横向漂移。收缩完成后再延迟缩小实际 window frame。

6. **hover 触发必须有明确 hit mask**

   成熟实现会避免“整个透明大窗口都吃事件”。常见策略是：

   - compact 时只让顶部小胶囊/左右 slot 区域触发。
   - expanded 时让 `topCap ∪ body` 区域触发。
   - 对透明区域使用 pass-through 或用 `contentShape` 让 hit test 跟视觉 shape 对齐。

## 项目清单

| 项目 | 类型 | 许可/风险 | 关键路线 | 可借鉴点 | 不可照搬 |
| --- | --- | --- | --- | --- | --- |
| [Boring Notch](https://github.com/TheBoredTeam/boring.notch) | 成熟开源 App | GPL-3.0；部分 SkyLight/CGS wrapper 有额外来源说明 | `NSPanel` + 高 window level + SkyLight/CGS Space + SwiftUI notch surface | 使用 `screen.frame`、safe area、auxiliary areas 计算闭合尺寸；hover open/close；spring 动画；私有 Space 解决菜单栏层级 | GPL 源码不能直接搬进本仓库；私有 API 不适合 App Store 路线 |
| [Atoll](https://github.com/Ebullioscopic/Atoll) | Dynamic Island App | GPL-3.0；大量私有 API | CGS Space + 单个 `NotchShape` + ViewModel 状态机 | `NotchShape` 用单个 path 表达顶部/底部圆角；hover activation rect 与闭合刘海尺寸绑定；open 前先扩 window | 不能复制 GPL 源码；API 风险同上 |
| [SuperIsland](https://github.com/shobhit99/SuperIsland) | Dynamic Island App | 开源，偏公开 AppKit 路线 | `.statusBar` 级 `NSPanel` + 固定 hosting canvas + window clipping | `IslandPanel` 透明非激活；窗口只裁剪，不驱动布局；compact leading/trailing slot；延迟 shrink window 避免布局跳动 | 不解决所有菜单栏覆盖问题；需要接受公开 API 的上限 |
| [DynamicNotch](https://github.com/jackson-storm/DynamicNotch) | Dynamic Island / system surface App | 开源；使用 SkyLightOperator | 大 canvas + `.mainMenu + 3` panel + SkyLight delegation + 分层动画状态 | 把 geometry、active content、transition animation 分离；有 staged close、hover/click/press 策略；有几何和过渡测试 | SkyLight 部分不能当作公开 API 保证 |
| [OpenNook](https://github.com/glendonC/opennook) | Notch framework | 项目 Apache-2.0；`NookSurface` MIT；派生自 DynamicNotchKit | `NookPanel` + `NookView` + `NookShape` + compact/expanded state | 非常适合参考：leading/trailing slots 围绕物理 notch gap；`contentShape` 对齐 hit test；transition generation 取消旧动画 | 仍需根据 token-hud 数据模型重写，不要整包引入 |
| [DynamicNotchKit](https://github.com/MrKai77/DynamicNotchKit) | Notch UI kit | 开源框架 | 面向 macOS notch 的适配组件 | 可作为 OpenNook 的技术来源和 notch UI 抽象参考 | 需要检查 API/维护状态和许可证边界 |
| [VibeHub](https://github.com/mtunique/VibeHub) | 监控 Claude/OpenCode CLI 的 notch overlay | 开源 App | Dynamic Island overlay + hover delay + pass-through event 策略 | 与 token-hud 领域接近；closed/passive 时 `ignoresMouseEvents`，hover/click 后再变交互；防止 screen-change 重建触发启动动画 | 不是专门解决菜单栏私有层级的项目 |
| [NotchNook](https://lo.cafe/notchnook) | 商业 App | 闭源 | notch popout / tray 类产品 | 产品形态验证：从刘海区域展开、收起、放置内容是成熟交互 | 无源码，只能观察交互 |
| [Alcove](https://tryalcove.com/) | 商业 App | 闭源 | Mac Dynamic Island | 产品交互参考：状态、媒体、通知类内容从刘海展开 | 无源码 |
| [MediaMate](https://wouter01.github.io/MediaMate/) | 商业 App | 闭源 | macOS HUD replacement / notch integration | 系统 HUD 替换、顶部浮层动效可参考 | 无源码 |

## 技术模式拆解

### 1. Window 层级策略

成熟项目通常分两层考虑：

- **公开层**：`NSPanel` / `NSWindow` 使用 `.borderless`、`.nonactivatingPanel`、透明背景、无 shadow、`.canJoinAllSpaces`、`.stationary`、`.fullScreenAuxiliary`、`.ignoresCycle`，window level 使用 `.statusBar` 或 `.mainMenu + n`。
- **私有层**：通过 SkyLight / CGS 创建 absolute level 极高的 Space，把 notch window 加入该 Space，绕过普通菜单栏遮挡。

对 token-hud 的含义：

- `publicPanel` 只能作为兼容模式。
- 如果目标是“内容进入菜单栏左右两侧”，应优先排查 `skyLightSpace` 是否成功，而不是继续调 y。
- 诊断日志必须输出：strategy、requested frame、actual frame、screen frame、notch rect、window level、Space delegation 是否成功。

### 2. Notch geometry

多个项目都使用同一组系统信息：

- `screen.frame`：物理屏幕坐标，包含菜单栏区域。
- `screen.visibleFrame`：可用工作区，不适合用来贴刘海顶边。
- `safeAreaInsets.top`：刘海/菜单栏高度的关键来源。
- `auxiliaryTopLeftArea` / `auxiliaryTopRightArea`：刘海左右菜单栏区域。

稳定计算模型：

- notch 宽度 = `screen.frame.width - auxiliaryTopLeftArea.width - auxiliaryTopRightArea.width`。
- notch 高度优先用 `safeAreaInsets.top`，缺失时降级到菜单栏高度或配置默认值。
- notch 的 x 位置从左侧 auxiliary area 结束处开始。
- 顶边锚定使用 `screen.frame.maxY`，不要用 `visibleFrame.maxY`。

对 token-hud 的含义：

- `NotchGeometryCalculator` 必须继续以 `screen.frame` 为主。
- 任何“向上顶进菜单栏”的问题，先确认是不是用了 `visibleFrame` 或窗口被系统层遮挡。
- 多屏场景必须使用稳定 display id，而不是默认取主屏。

### 3. 单体 shape，而不是拼黑块

Atoll、DynamicNotch、OpenNook 都使用单个 notch shape 表达：

- compact 顶部小胶囊。
- expanded 下拉 body。
- 顶部和底部不同圆角。
- 刘海下方左右角的圆弧过渡。
- compact 到 expanded 的 animatable corner radius。

错误模式：

- 左右两个黑块 + 中间一个黑块 + 下方 body。
- 直角肩膀去贴弧形刘海。
- 用多个 panel 拼接菜单栏与下拉框。

对 token-hud 的含义：

- `NotchHostedSurfaceView` 应该输出一个连续 shape。
- compact left/right slot、top cap、expanded body 都应该处在同一层视觉表面。
- 刘海下方左右角必须参与同一个 path / mask，不能靠相邻矩形覆盖。

### 4. Compact leading/trailing slots

OpenNook 和 SuperIsland 都验证了这个模型：

- 一个 compact surface。
- 中间留出物理刘海宽度。
- left slot 和 right slot 分别放状态。
- 即使左右内容宽度不同，也要用 offset 修正视觉重心，让物理 notch gap 保持居中。

适配 token-hud：

- 左侧只保留一小格进度条或服务短名。
- 右侧只保留百分比或状态标记。
- compact 高度必须接近菜单栏高度，不要垂到屏幕内容区。
- 展开时 body 从 top cap 下方自然延展，不要先出现很长的黑条。

### 5. Hover / click / drag 触发

成熟实现不会让用户猜“到底摸哪里”：

- Boring Notch 用鼠标坐标判断是否进入 notch closed rect。
- Atoll 用基于 closed notch size 的隐藏 hover activation rect。
- OpenNook 用 `contentShape` 让 hit test 与 visible shape 一致。
- VibeHub 在 closed/passive 状态 pass-through，只有 hover/click 进入交互态后才接管鼠标事件。

对 token-hud 的含义：

- compact 的可触发区域应是 top cap 的整块区域，或明确可见的 left/right pill。
- expanded 的可触发区域应是 top cap + body。
- 透明 window 不应整块阻塞菜单栏。
- 拖拽脱离时必须从 hosted state 明确切到 detached state；拖回吸附时重新走 compact/expanded transition，不要混用拖拽中的临时 frame。

### 6. 动画和状态机

成熟项目普遍拆分：

- window frame 动画。
- shape/path 动画。
- 内容 opacity / scale / offset 动画。
- hover/click/press/drag 状态。
- open/compact/expanded/closing 的过渡状态。

重要细节：

- expand 时先保证 window 足够大，再让内容和 shape 展开。
- compact 时先让内容收起，再延迟缩小 window frame，避免 SwiftUI relayout 抖动。
- hover in/out 要用 generation 或 cancellable task 取消旧动画，防止快速移动鼠标时状态乱跳。
- content 不应和 shell 同时完全出现；最好让 shell 先展开，内容再 fade in。

对 token-hud 的含义：

- 不要只绑定一个 `isExpanded`。
- 至少区分：`collapsed`、`expanding`、`expanded`、`collapsing`、`detached`。
- 每次 transition 应记录 generation，新的 hover/drag/click 事件进来时取消旧任务。

### 7. 拖拽脱离与再次吸附

用户目标是：可以把窗口从刘海拉走，成为普通 floating panel；也可以拖回刘海，再吸附回 compact notch。

参考项目很少完整覆盖这个交互，但可从已有模式推导：

- hosted 模式：使用 notch geometry 和顶部 window level。
- detached 模式：使用普通 floating panel，位置由用户拖拽决定。
- 吸附判定：拖拽结束时，panel center 距离 notch rect / top cap rect 小于阈值。
- 吸附动画：先把 detached panel 的视觉 surface 变为 hosted shell 的 expanded 或 compact 中间态，再切回 hosted window。
- 脱离动画：从 expanded body 拉下时，先冻结当前 surface snapshot/布局，再交给 detached panel，不要同时移动 hosted window。

对 token-hud 的含义：

- hosted 和 detached 的 window 管理要分离。
- 不要让 NotchFusionView 每次拖拽都用当前 mouse delta 累积 screen origin，否则会出现每次拖到不同位置的问题。
- 吸附/脱离应只使用一次 canonical geometry：目标屏幕 notch rect + 当前 transition phase。

### 8. 多屏、全屏和系统 UI

需要单独处理：

- 有刘海和无刘海显示器。
- 外接屏幕切换。
- 当前 active screen 变化。
- 全屏 Space。
- 锁屏或系统层级 UI。

参考：

- OpenNook 会监听屏幕变化并重建可见 window。
- DynamicNotch 有 screen selection 和 transition metrics 测试。
- VibeHub 防止 screen-change 重建触发启动动画。

对 token-hud 的含义：

- 不要在 screen change 时播放完整展开动画。
- screen geometry 变化后应重建 hosted panel 或重新计算 frame。
- 无刘海屏 fallback 应显示普通 top floating pill，不要假装有 notch gap。

### 9. 测试和诊断

值得保留的测试方向：

- notch rect 计算：有刘海、无刘海、左右 auxiliary area 不对称。
- compact slot 宽度：左右不同内容时 notch gap 仍居中。
- transition metrics：展开、收起、拖拽脱离时的 surface size / corner radius / content opacity。
- screen selection：多屏、外接屏、active display 切换。
- hit mask：compact 与 expanded 状态的可触发区域。

诊断日志建议记录：

- 当前 display id。
- `screen.frame` / `visibleFrame` / `safeAreaInsets.top`。
- `auxiliaryTopLeftArea` / `auxiliaryTopRightArea`。
- notch rect、top cap rect、body rect。
- strategy：`skyLightSpace` 或 `publicPanel`。
- requested frame 和 actual frame。
- Space delegation 成功/失败和 fallback 原因。

## 对 token-hud 的落地规则

后续每次改刘海 HUD，都按这组规则检查：

1. **先看 surface 是否单体**

   如果实现又回到多个黑块、多个 panel 或左右肩膀独立窗口，优先停止。当前沉淀结论不支持这种路线。

2. **先看 top anchor**

   顶边必须基于 `screen.frame.maxY`。如果使用 `visibleFrame`，菜单栏区域天然会空一条。

3. **先看策略日志**

   如果用户说“还是没有进入导航栏”，先看 `skyLightSpace` 是否启用、是否 delegated 成功、actual frame 是否被系统裁剪。不要第一反应调 y。

4. **compact 只保留小格**

   收缩态应该只在刘海左右两边显示小状态：左进度/短名，右百分比/状态。中间 notch gap 不显示内容，也不要下垂到屏幕内容区。

5. **展开从 top cap 向下长出来**

   动画顺序是 shell 先从刘海区域下拉，body 再出现，内容最后淡入。收起时内容先淡出，body 收回，最后只剩左右小格。

6. **圆角和缺口一起做**

   刘海下方左右角必须由 shape/mask 处理，不能用直角矩形贴过去。

7. **hover 区域要可解释**

   要么 compact surface 全区域都可 hover，要么给出明确视觉标识。不要让用户猜隐藏触发点。

8. **拖拽状态不要污染 hosted geometry**

   拖拽使用 detached geometry；吸附后重新用 notch geometry。不能把拖拽 delta 写回 hosted origin。

## 改动前检查清单

- 是否读过本文和 `docs/notch-open-source-research.md`？
- 是否保持单个 hosted surface？
- notch gap 是否来自 auxiliary areas，而不是写死？
- top edge 是否基于 `screen.frame.maxY`？
- compact left/right slot 是否在同一个 surface 内？
- hover hit mask 是否和可见 shape 对齐？
- transition 是否能取消旧动画？
- 收起时是否延迟缩小 window frame，避免布局漂移？
- 是否明确区分 `skyLightSpace` 和 `publicPanel`？
- 私有 API 是否有 fallback 和诊断日志？
- 是否避免复制 GPL/MPL 项目源码？

## 参考源码定位

这些路径是阅读源码时最有价值的入口，后续需要重新确认实现细节时优先看：

- Boring Notch
  - `boringNotch/sizing/matters.swift`
  - `boringNotch/models/BoringViewModel.swift`
  - `boringNotch/private/CGSSpace.swift`
  - `boringNotch/managers/NotchSpaceManager.swift`
  - `boringNotch/components/Notch/BoringNotchSkyLightWindow.swift`
  - `boringNotch/animations/drop.swift`
- Atoll
  - `DynamicIsland/private/CGSSpace.swift`
  - `DynamicIsland/components/Notch/NotchShape.swift`
  - `DynamicIsland/models/DynamicIslandViewModel.swift`
  - `DynamicIsland/sizing/matters.swift`
- SuperIsland
  - `SuperIsland/Window/IslandWindowController.swift`
  - `SuperIsland/Window/IslandWindow.swift`
  - `SuperIsland/Window/ScreenDetector.swift`
  - `SuperIsland/Views/CompactView.swift`
- DynamicNotch
  - `DynamicNotch/Application/AppDelegate/AppDelegate+Window.swift`
  - `DynamicNotch/Application/OverlayPanelWindow.swift`
  - `DynamicNotch/Features/Notch/Components/NotchShape.swift`
  - `DynamicNotch/Features/Notch/NotchViewModel.swift`
  - `DynamicNotch/Features/Notch/NotchEngine.swift`
  - `DynamicNotch/Features/Notch/NotchAnimations.swift`
- OpenNook
  - `Sources/NookSurface/Internal/NookPanel.swift`
  - `Sources/NookSurface/Nook.swift`
  - `Sources/NookSurface/Internal/NookView.swift`
  - `Sources/NookSurface/Internal/NSScreen+Extensions.swift`
  - `Sources/NookSurface/NookTransitionConfiguration.swift`
  - `Sources/NookSurface/Internal/NookShape.swift`
- VibeHub
  - `VibeHub/Core/Ext+NSScreen.swift`
  - `VibeHub/Core/NotchViewModel.swift`
  - `VibeHub/UI/Window/NotchWindow.swift`
  - `VibeHub/UI/Window/NotchWindowController.swift`
  - `VibeHub/UI/Components/NotchShape.swift`

## 许可和风险

- GPL-3.0 项目只能用于理解设计，不能直接复制源码进 token-hud。
- MPL/派生来源文件需要保留对应许可证义务，最好也不要复制，只抽象成自己的实现。
- SkyLight / CGS 是私有 API，存在系统兼容性、审核和稳定性风险。
- 公开 AppKit fallback 必须明确标注能力上限：它可能无法真正覆盖菜单栏左右两侧。
- 商业闭源 App 只能作为交互参考，不作为实现证据。
