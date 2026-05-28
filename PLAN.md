# 短期计划

这个文件跟踪当前项目正在进行的实现工作。保持内容小而可执行；可长期保留的决策沉淀到 `docs/`。

## 当前重点：Notch Overlay 菜单栏融合修复（已实现，待真机验证）

### 当前问题

用户最新真机截图显示：双窗口方案仍然没有达成目标。当前效果只是一个黑色矩形悬在菜单栏下方：

- 黑色区域没有进入顶部菜单栏。
- 刘海左右两侧没有被填充。
- 视觉上不是“刘海弹开”，而是普通 overlay 被放在菜单栏下面。

这说明问题不能继续当作简单 y 坐标偏移处理。

### 本轮实现状态（2026-05-29）

已按开源调研后的路线完成第一版实现：

- `NotchGeometryCalculator.notchFrames` 改为让 hosted surface 顶边锚定 `screen.frame.maxY`，不再上推到 `screen.maxY + safeAreaTop`。
- hosted overlay window 改为单个 `NotchSurfaceWindow`，style mask 包含 `.borderless`、`.nonactivatingPanel`、`.utilityWindow`、`.hudWindow`。
- 新增 `NotchSurfaceStrategy`：
  - `skyLightSpace`：优先策略，window level 为 `.mainMenu + 3`。
  - `publicPanel`：SkyLight 不可用时 fallback，window level 为 `.screenSaver`。
- 新增 `SkyLightNotchSpace`，通过 `dlopen` 动态加载 SkyLight 私有符号并创建 absolute level `2_147_483_647` 的 notch Space。
- hosted overlay 显示前会尝试 delegate 到 SkyLight notch Space，并在日志输出 strategy、SkyLight availability、space id、delegate return code、requested/actual frame。
- 屏幕选择新增 display id 记忆，优先使用带 notch 的屏幕。

验证结果：

- `swift test` 通过，98 个测试通过。
- `xcodebuild -project ../token_hud.xcodeproj -scheme token_hud -destination 'platform=macOS' build` 通过。

待真机验证：

- 吸附后 topBridge 是否进入菜单栏/刘海区域。
- 诊断日志中的 `notchSurfaceStrategy` 是否为 `skyLightSpace`。
- `overlayDelegatedToSkyLight` 是否为 `true`。
- 如果仍不可见，下一步根据日志判断是 SkyLight delegate 失败、frame 被系统裁剪，还是 SwiftUI surface 绘制问题。

### 开源项目调研结论

长期调研记录见 `docs/notch-open-source-research.md`。

本轮对比了 Boring Notch、Atoll、SuperIsland、DynamicNotch 的源码。结论是：我之前提出的“三个普通窗口：左右 bridge + body”方案依据不足，应该废弃。

关键发现：

1. **真正能强融合的项目没有只靠普通 `NSPanel`**
   - Boring Notch 使用 `BoringNotchSkyLightWindow`，窗口 level 是 `.mainMenu + 3`，style mask 包含 `.borderless`、`.nonactivatingPanel`、`.utilityWindow`、`.hudWindow`，并设置 `.fullScreenAuxiliary`、`.stationary`、`.canJoinAllSpaces`、`.ignoresCycle`。
   - 更关键的是，它实现了 `CGSSpace`，通过 `CGSSpaceCreate` / `CGSSpaceSetAbsoluteLevel` / `CGSAddWindowsToSpaces` 创建 absolute level 为 `2147483647` 的私有 Space，并把 notch window 加进去。
   - Atoll 继承了同类 `CGSSpace` 方案，并把窗口加入 `NotchSpaceManager.shared.notchSpace.windows`。
   - DynamicNotch 也走同类路线：`OverlayWindowLevel.interactiveNotch = .mainMenu + 3`，并通过 `SkyLightOperator` 创建 `.notchSurface = 2_147_483_647` 的私有 Space，把窗口 delegate 到这个 Space。

2. **公开 API 项目更像“刘海下方/附近的近似 Dynamic Island”**
   - SuperIsland 使用透明 `NSPanel`、`.nonactivatingPanel`、`.statusBar` level。
   - 它的架构是“单个最大尺寸 panel + 固定 SwiftUI hosting view + 窗口作为裁剪 viewport”，而不是多个 bridge 窗口。
   - 这个路线更安全，但不保证能覆盖系统菜单栏层；它和我们当前失败的公开 AppKit 路线更接近。

3. **成功项目普遍是单窗口 notch surface，不是左右 bridge 多窗口**
   - Boring Notch / Atoll / DynamicNotch 都是 top-centered single window / canvas。
   - 视觉扩展靠窗口内 SwiftUI 状态和裁剪/动画处理，不靠多个窗口拼接菜单栏左右区域。
   - 多窗口 bridge 容易产生 seam、同步问题，而且如果窗口层级仍然被系统菜单栏压住，拆成三个窗口也不会解决根因。

4. **屏幕选择和几何检测是基础设施，不是视觉细节**
   - 开源项目普遍用 `safeAreaInsets.top`、`auxiliaryTopLeftArea/rightArea`、稳定 display id、用户选择屏幕、鼠标所在屏幕、多屏同步等逻辑。
   - 不能只默认 `NSScreen.main`。

### 修订后的根因判断

当前实现有两个关键限制：

1. **单个 overlay window 被系统放回菜单栏下方**
   - `NotchGeometryCalculator` 请求的 frame 已经包含 menu bar bridge。
   - 但真机可见结果说明 WindowServer 可能仍把普通 app window 的可见区域压到 `visibleFrame` 下方，或当前 window 配置没有获得菜单栏区域显示条件。

2. **`topBridge` 只画在 overlay window 内部**
   - 如果 overlay window 本身进不了菜单栏区域，`topBridge` 就永远不可能覆盖刘海左右两侧。
   - 但开源项目的做法不是拆多个普通窗口，而是把主 overlay window 加入更高层的 SkyLight/CGS Space。

所以当前问题的根因大概率是：**公开 AppKit window level 不足以稳定覆盖菜单栏/刘海区域；要达到 Boring Notch / Atoll 级别的融合，需要引入 SkyLight/CGS 私有 Space，或明确接受公开 API fallback 的视觉上限。**

### 本轮目标

这轮不再修饰现有黑矩形，也不做三窗口 bridge。目标改为做一个可验证的 **Notch Surface Strategy**：

1. 保留 detached floating window。
2. hosted 状态回到 **单个 top-centered notch surface window**。
3. 该 window 首先尝试 SkyLight/CGS 私有 Space：
   - `.mainMenu + 3` window level；
   - borderless/nonactivating/utility/hud；
   - `.canJoinAllSpaces`、`.stationary`、`.fullScreenAuxiliary`、`.ignoresCycle`；
   - 通过私有 Space absolute level `2_147_483_647` 获得菜单栏上方显示能力。
4. 如果私有 API 不可用，自动 fallback 到公开 `.statusBar` / `.screenSaver` panel，并明确标记为近似模式，不再承诺完全菜单栏融合。
5. 继续保留诊断日志，对比 `requestedFrame` / `actualFrame` / Space 可用性。

### 实施步骤

1. **新增 NotchSurfaceStrategy**
   - 新增策略枚举：
     - `skyLightSpace`：使用私有 CGS/SkyLight Space。
     - `publicPanel`：只使用公开 AppKit window level。
   - 默认先启用 `skyLightSpace`，如果私有符号加载失败则降级到 `publicPanel`。
   - 在日志里打印当前策略。

2. **新增 SkyLight/CGS Space wrapper**
   - 以 DynamicNotch 的做法为参考，动态 `dlopen` `/System/Library/PrivateFrameworks/SkyLight.framework/Versions/A/SkyLight`。
   - 尝试加载：
     - `SLSMainConnectionID`
     - `SLSSpaceCreate`
     - `SLSSpaceSetAbsoluteLevel`
     - `SLSShowSpaces`
     - `SLSSpaceAddWindowsAndRemoveFromSpaces`
   - 创建 absolute level `2_147_483_647` 的 notch surface。
   - 提供 `delegateWindow(_:)`，把 hosted window 加入 notch surface。
   - 如果任一步失败，不崩溃，只记录不可用并走 `publicPanel`。

3. **重构 hosted window**
   - 删除三窗口 bridge 计划。
   - 保留单个 `overlayWindow`，但改成 `NotchSurfaceWindow` 或同等语义：
     - `NSPanel`
     - `.borderless`
     - `.nonactivatingPanel`
     - `.utilityWindow`
     - `.hudWindow`
     - level `.mainMenu + 3`
     - `isOpaque = false`
     - `backgroundColor = .clear`
     - `hasShadow = false`
     - `isFloatingPanel = true`
     - `canBecomeKey = false`
     - `canBecomeMain = false`
   - hosted 状态时把该 window 加入 SkyLight/CGS notch surface。

4. **重做 window frame 与 SwiftUI surface**
   - 参考 Boring Notch / DynamicNotch：window 始终 top-centered：
     - `x = screen.frame.midX - width / 2`
     - `y = screen.frame.maxY - height`
   - 不使用 `visibleFrame` 作为 hosted 位置依据。
   - SwiftUI surface 内部绘制：
     - 顶部菜单栏/刘海融合区域；
     - 刘海下方 body；
     - expanded 内容。
   - 可参考 SuperIsland 的“最大 hosting view + window 作为裁剪 viewport”模式，避免窗口尺寸变化导致 SwiftUI layout 跳动。

5. **屏幕选择与多屏基础**
   - 使用稳定 display id 保存偏好屏幕。
   - 优先选择带 notch 的内建屏。
   - 没有 notch 时 fallback 到顶部居中 public panel。
   - 监听 `NSApplication.didChangeScreenParametersNotification` 后重建/重定位 window。

6. **加强诊断**
   - hosted 状态输出：
     - `requestedFrame`
     - `actualFrame`
     - `screen.frame`
     - `screen.visibleFrame`
     - `safeAreaInsets`
     - `auxiliaryTopLeftArea/rightArea`
     - window `level.rawValue`
     - SkyLight/CGS strategy availability
     - window 是否已 delegate 到 notch surface

7. **验证**
   - 运行 `swift test`。
   - 运行 `xcodebuild -project ../token_hud.xcodeproj -scheme token_hud -destination 'platform=macOS' build`。
   - 真机验证截图：
     - 若 SkyLight strategy 可用且窗口进入菜单栏，继续调视觉。
     - 若 SkyLight strategy 不可用，确认 fallback 效果并记录限制。
     - 若 SkyLight strategy 可用但仍不能显示，读取诊断日志定位是 frame、Space delegation 还是渲染层问题。

### 验收标准

- 吸附后不能再是菜单栏下方的一整块悬浮黑矩形。
- hosted surface 顶部必须贴到 `screen.frame.maxY`，并在刘海/菜单栏区域产生可见融合层。
- body 必须从刘海下方展开，而不是从屏幕中间悬浮。
- hosted 状态不可 resize。
- detached 状态仍可拖动、resize，并能再次吸附。
- 如果私有 API 不可用，app 必须稳定 fallback，不崩溃。

### 风险

- SkyLight/CGS 是私有 API，可能影响 App Store 分发、系统兼容性和未来 macOS 版本稳定性。
- GPL 项目的源码只能作为架构参考，不能直接复制代码进本仓库，必须自行实现最小 wrapper。
- 私有 Space level 过高可能遮挡系统 UI；hosted collapsed 必须尽量收敛命中区域和视觉宽度。
- 如果项目目标是公开分发且要求 App Store 合规，则只能使用 SuperIsland 类公开 API fallback，不能承诺 100% 菜单栏融合。

---

## 历史记录：双窗口 Notch Overlay 重构

### 最新结论

用户指出 iPromise、Boring Notch、Atoll/SuperIsland 等 app 能做出类似 notch / Dynamic Island 效果。这个判断是对的：问题不是 macOS 上绝对做不到，而是当前 `token_hud` 的路线不对。

当前失败原因：

- 我们把同一个 `NSPanel` 同时当作 detached 浮窗、docked collapsed、expanded notch overlay 来用。
- 为了避免进入菜单栏失败，又把 hosted frame 收回到工作区内，结果只剩悬空黑条。
- `NSStatusItem` 不能作为主方案，因为菜单栏 item 位置不可控。

新路线改为 **双窗口架构**：

1. **Detached Floating Window**
   - 普通可拖拽、可 resize 的浮窗。
   - 用户拖下来后使用它。

2. **Dedicated Notch Overlay Window**
   - 独立 borderless/nonactivating panel。
   - 永远锚定在主屏幕 notch 顶部区域。
   - frame 使用 `NSScreen.frame` / `auxiliaryTopLeftArea` / `auxiliaryTopRightArea` 计算，不再依赖 `visibleFrame`。
   - 负责 collapsed / expanded dynamic island 的视觉和 hover。

拖拽吸附时，不再把同一个窗口硬塞到刘海区域，而是：

1. detached window 拖到 snap zone。
2. 保存 detached frame。
3. 隐藏 detached window。
4. 显示 notch overlay window，并播放 expanded 反馈。
5. 用户从 notch overlay 往下拖时，隐藏 overlay，恢复 detached window。

### 本轮实现结果

已完成最小双窗口 Notch Overlay 重构：

- `NotchHostPanelManager` 现在同时维护 detached floating window 和 dedicated notch overlay window。
- detached 状态继续使用 `FloatingPanelView`，保留拖拽和 resize。
- hosted collapsed / expanded 状态由独立 overlay `NSPanel` 承载，吸附时隐藏 detached window，脱离时隐藏 overlay 并恢复 detached frame。
- overlay frame 重新按 `NSScreen.frame`、notch auxiliary areas 和 menu bar 高度计算，允许视觉区域延伸到菜单栏/刘海高度，而不是被压回 `visibleFrame` 下方。
- `NotchFusionView` 新增 top bridge 绘制区域，body 位于菜单栏高度下方，展开内容延迟淡入。
- `MenuBarBridgeProbe` 保持默认关闭，不再把 `NSStatusItem` 作为主路线。

验证结果：

- `swift test` 通过，98 个测试通过。
- `xcodebuild -project ../token_hud.xcodeproj -scheme token_hud -destination 'platform=macOS' build` 通过。

待真机验证：

- 吸附后 overlay 是否真正顶到刘海/菜单栏视觉高度。
- 刘海左右两侧是否出现 top bridge 效果。
- 从 hosted 状态往下拖是否能稳定恢复 detached floating window。
- 如果仍被系统菜单栏遮挡，下一步应对照 Boring Notch / Atoll 的窗口 level、screen 选择和 fullscreen handling，而不是回到单窗口方案。

### 参考依据

- Boring Notch README 明确描述了 launch 后 notch 成为交互区域，并通过 hover 展开内容。
- Atoll README 明确描述了 hover near the notch to expand，并提供独立 notch command surface。
- 这些项目的产品形态都更接近“独立 notch overlay surface”，而不是把普通浮窗拖上去后继续复用。

### 本轮目标

先完成最小双窗口切换，不追求最终视觉：

- 保留现有 detached `FloatingPanelView` 作为普通浮窗。
- 新增独立 `NotchOverlayPanelManager` 或拆分现有 `NotchHostPanelManager`。
- notch overlay window 启动时隐藏，只在 hosted 状态显示。
- overlay window 的 collapsed frame 顶到 `screen.frame.maxY` 附近，允许覆盖菜单栏视觉高度。
- detached -> hosted 时切换窗口，而不是移动同一窗口。
- hosted -> detached 时恢复原 detached frame。

### 实施步骤

1. **抽出 notch overlay frame 计算**
   - 在 `NotchGeometryCalculator` 中新增专门的 overlay frames：
     - collapsed overlay frame
     - expanded overlay frame
     - snap zone
   - overlay frame 的 `maxY` 应基于 `geometry.topEdgeY` 或 `screen.frame.maxY`，不再强制压到工作区下方。
   - 保留 detached frame 逻辑不变。

2. **新增/拆分 overlay window manager**
   - 创建 dedicated overlay `NSPanel`。
   - style 使用 borderless/nonactivating。
   - level 先使用 `.screenSaver` 或当前已有 level。
   - collectionBehavior 保持 `.canJoinAllSpaces` / `.fullScreenAuxiliary` / `.stationary`。
   - overlay content 使用现有 `NotchFusionView` 或新 `NotchOverlayView`。

3. **保留 detached floating window**
   - detached window 使用 `FloatingPanelView`。
   - 仅 detached 时可 resize。
   - 不再让 detached window 进入 hosted frame。

4. **实现窗口切换状态机**
   - snap 成功：
     - 保存 detached frame。
     - detached window `orderOut`。
     - overlay window `orderFrontRegardless`。
     - overlay 进入 expanded feedback。
   - detach：
     - overlay window `orderOut`。
     - detached window 恢复保存 frame 并 `orderFrontRegardless`。

5. **真机验证**
   - overlay 是否能贴到刘海/菜单栏视觉高度。
   - 左右两侧是否能出现效果。
   - 是否仍被系统菜单栏遮挡或裁剪。
   - 如果仍无法覆盖，继续对照 Boring Notch/Atoll 源码检查 window level、screen selection 和 positioning。

### 验收标准

- 拖到刘海附近后，不再出现工作区里的悬空黑条。
- hosted 状态由独立 overlay window 承载。
- detached 状态仍可拖拽和 resize。
- 吸附/脱离是窗口切换，不是同一个 window 的 frame 魔改。
- 如果 overlay 仍无法进入菜单栏视觉高度，能通过诊断日志明确看到实际 frame 与系统裁剪结果。

### 风险

- 即使双窗口，系统仍可能限制普通 app window 在菜单栏区域的显示。
- 需要真机调试 `NSScreen.frame` / `safeAreaInsets` / auxiliary areas 的坐标差异。
- Boring Notch/Atoll 可能有额外处理，例如更复杂的屏幕选择、fullscreen detection、lock screen 行为，这些不在第一轮范围内。

---

## 历史记录：Hybrid Dynamic Notch 第一版

### 方案结论

当前截图已经证明：继续用普通 `NSPanel` / floating window 向上顶，无法达到“进入顶部菜单栏并与刘海完全融为一体”的效果。这个方向应停止。

可行方案改为 **Hybrid Dynamic Notch**：

1. **不再试图让普通窗口进入系统菜单栏。**
2. **吸附态只做极简 docked 状态**：小浮窗收缩到刘海正下方，尽量贴近刘海，形成“从刘海挂下来”的感觉。
3. **hover / click 时展开**：从刘海下方展开为完整 HUD 内容。
4. **拖下来时脱离**：恢复普通 floating panel。
5. **菜单栏层只作为增强，不作为主依赖**：`NSStatusItem` 如果能放到合理位置，就用它做菜单栏内黑色/图标融合；如果不能，就立刻放弃菜单栏层覆盖，不再把它作为必须条件。

这不是“100% 系统刘海融合”，但它是基于公开 macOS API 最稳的可落地方案。

### 本轮实现结果

已完成 Hybrid Dynamic Notch 第一版：

- docked collapsed 从 8pt 黑线调整为 22pt 刘海下方胶囊。
- hosted panel 仍然只位于屏幕工作区内，不再尝试进入菜单栏。
- 内容 opacity 延迟到展开中后段才出现，避免从极小胶囊里硬挤出文字。
- 胶囊底部圆角随高度自适应，collapsed 时更像贴在刘海下方的挂载状态。
- 吸附成功后先播放 expanded 反馈，再在鼠标不在刘海区域时延迟约 1 秒收回 collapsed。
- `MenuBarBridgeProbe` 默认关闭，不再启动时显示黑色菜单栏测试条。
- 新增/更新几何测试覆盖 collapsed 高度、无 panel bridge、延迟内容淡入。

验证结果：

- `swift test` 通过，98 个测试通过。
- `xcodebuild -project ../token_hud.xcodeproj -scheme token_hud -destination 'platform=macOS' build` 通过。

待真机确认：

- 拖上去吸附后应先展开显示内容，而不是只剩黑线。
- 收回后应是短胶囊，不是悬空长条。
- 顶部菜单栏内不应再出现 probe 黑条。

### 为什么这是可行路线

- `NSPanel` 可以稳定实现刘海下方 body、拖拽、吸附、展开、脱离。
- `NSStatusItem` 可以稳定出现在菜单栏中，但无法保证精确覆盖刘海左右两侧，也无法任意占用菜单栏大面积区域。
- 所以最终产品体验应围绕“刘海下方 Dynamic Island-like HUD”设计，而不是继续追求普通 app window 覆盖系统菜单栏。

### 目标视觉

1. **Detached**
   - 普通可拖拽浮窗。
   - 显示完整业务内容。
   - 可调整大小。

2. **Docking Preview**
   - 用户拖近刘海时，浮窗变窄、变矮、圆角收敛。
   - 出现吸附预览，例如顶部对齐刘海、轻微 scale / opacity / shadow 变化。
   - 不进入菜单栏，不画左右假 bridge。

3. **Docked Collapsed**
   - 只保留刘海下方一小条胶囊或细窄状态条。
   - 不显示完整业务内容。
   - 不允许 resize。
   - 看起来像“藏在刘海下面”，而不是一条悬空黑线。

4. **Docked Expanded**
   - 鼠标靠近刘海或点击 collapsed 条时展开。
   - body 从刘海下方自然向下长出来。
   - 显示完整业务内容。
   - 鼠标移开后收回 collapsed。

5. **Menu Bar Enhancement（可选）**
   - 如果 `NSStatusItem` 能在菜单栏中形成合理视觉位置，只作为点缀层。
   - 不承载主要内容。
   - 不阻塞主体验。

### 下一轮实施计划

1. **重命名和收敛状态模型**
   - 保留 `detached` / `collapsed` / `expanded`。
   - 明确 `collapsed` 是 docked collapsed，不是“内容不可见的错误态”。
   - 新增 `isDockingPreview` 或等价状态，用于拖近刘海但尚未释放时的视觉反馈。

2. **重做 hosted collapsed 视觉**
   - 当前黑色细条太像 bug。
   - 改成一个贴近刘海下方的小胶囊，宽度接近刘海宽度加少量 padding。
   - 高度建议 18-24pt，而不是 8pt。
   - 顶部圆角应较小或为 0，底部圆角更明显，形成“挂在刘海下方”的形态。

3. **重做 snap 后反馈**
   - 拖拽释放吸附成功后，先播放 expanded 动画。
   - 保持 expanded 约 0.8-1.2 秒，或直到鼠标离开。
   - 然后收回 docked collapsed。

4. **重做展开动画**
   - collapsed -> expanded：
     - 宽度从刘海胶囊宽度扩展到 HUD 宽度。
     - 高度从 20pt 扩展到内容高度。
     - 内容 opacity 在高度足够后再出现，避免挤压。
   - expanded -> collapsed：
     - 内容先淡出。
     - body 再向上收缩。

5. **保留 MenuBarBridgeProbe 为诊断开关**
   - 默认关闭或只在 debug 下打开。
   - 不再默认显示黑色状态项，避免干扰用户判断。
   - 后续单独验证 `NSStatusItem` 是否能作为增强层。

6. **清理误导逻辑**
   - 移除或废弃 `hostTopY(for:)` 上推菜单栏的使用路径。
   - 移除“panel bridge in menu bar”的命名和测试。
   - 文档明确：主 panel 不进入菜单栏。

### 验收标准

- 拖上去吸附后，不再出现悬空黑线。
- collapsed 状态像一个贴在刘海下方的短胶囊。
- hover / click 后能展开并显示内容。
- 拖下来后恢复完整浮窗和 resize 能力。
- 菜单栏内不出现突兀黑块。
- 即使 `NSStatusItem` 完全不可用，主体验仍然成立。

### 不做的事情

- 不再尝试把 `NSPanel` 顶进菜单栏。
- 不再用 full-width 黑色 bridge 假装覆盖刘海两侧。
- 不把业务内容塞进 `NSStatusItem`。
- 不使用 private API 作为默认路线。

---

## 历史记录：Notch Fusion 失败复盘与上一轮修正

### 结论

原来的主 `NSPanel` 路线已确认不可行：它可以负责刘海下方 body，但不能可靠进入 macOS 顶部导航栏/菜单栏层。继续调整 `y`、`maxY`、window level 或 SwiftUI padding 都是在错误层级里修表象。

新的实现方向是把吸附态拆成两个真正独立的层：

1. **Menu Bar Layer**：负责刘海左右两侧导航栏融合。
2. **Body Layer**：继续使用现有 hosted/floating panel，负责刘海下方展开内容和拖拽脱离。

### 技术依据

- Apple 的 `NSStatusBar` / `NSStatusItem` 是公开的菜单栏承载 API，可显示文本、图标、菜单、action，或自定义 view。
- Apple 的 `NSScreen.auxiliaryTopLeftArea` / `auxiliaryTopRightArea` 仍然用于确定刘海左右可用区域，但不再直接驱动主 panel 进入菜单栏。
- `NSWindow.Level.screenSaver` 只能改变窗口层级，不能保证普通 app window 可以占用系统菜单栏内部区域。

### 当前截图结论

用户真机截图显示：拖拽到刘海附近后，只能看到左右两块黑色 bridge 和一条很薄的黑色底边，业务内容完全不可见。

结合当前代码，根因不是单纯坐标偏移：

- 截图中的黑色 bridge 来自 `NotchFusionView` 的 `leftBridge` / `rightBridge` / `bodyPanel`，也就是主 `NSPanel` 层；它仍然没有真正进入系统菜单栏层。
- 吸附完成会走 `snapToCollapsed()` -> `animateToCollapsed()`，并把 `hostState.expansionProgress` 设为 `0`。
- `NotchFusionView.bodyPanel` 中业务内容 `.opacity(hostState.expansionProgress)`，因此 collapsed 后内容必然完全不可见。
- `MenuBarBridgeProbe` 只是独立 `NSStatusItem` spike，不会跟拖拽吸附状态联动，也不会把当前 floating panel 的内容带到菜单栏里。

因此，当前效果是架构混合态：视觉上还在使用旧 `NSPanel` bridge，逻辑上又把内容折叠为 0，新的 menu bar layer 没有真正承接吸附态。

### 本轮修正结果

已完成第一阶段修正：

- `NotchGeometryCalculator.notchFrames` 不再让 hosted panel 跨进菜单栏区域。
- hosted collapsed frame 现在只覆盖刘海下方的极薄 body。
- hosted expanded frame 现在只覆盖刘海下方的内容区域。
- `NotchFusionView` 不再绘制主 `NSPanel` 的左右 menu bar bridge，避免截图中的突兀黑块。
- 拖拽释放并吸附成功后，不再直接停在空 collapsed 状态，而是进入 expanded，让用户先看到内容反馈。
- `NotchGeometryCalculatorTests` 已更新，覆盖“不跨菜单栏、不全屏 bridge、body 从刘海下方展开”的新规则。

验证结果：

- `swift test` 通过，97 个测试通过。
- `xcodebuild -project ../token_hud.xcodeproj -scheme token_hud -destination 'platform=macOS' build` 通过。

待真机确认：

- 拖到刘海附近后，应显示刘海下方 expanded 内容，而不是只剩黑条。
- 左右两侧不应再出现由主 panel 画出的突兀黑块。
- 这还不是最终“完全融入菜单栏”的效果；真正菜单栏融合仍依赖后续 menu bar layer 能力验证。

### 修正目标状态

下一轮不再让主 `NSPanel` 画菜单栏 bridge。吸附态必须拆清楚：

1. **Collapsed / docked 状态**
   - 菜单栏层只负责极简黑色融合外观。
   - 下方 body 可以完全隐藏，或只保留极薄连接区。
   - 业务内容不应该在 collapsed 中显示，这是“收进刘海”的状态。

2. **Hover / expanded 状态**
   - 鼠标靠近刘海时，先从菜单栏层向下展开。
   - 业务内容只在 expanded body 中显示。
   - 展开 body 必须从刘海下方自然长出来，而不是拖拽上去后只剩黑条。

3. **Detached 状态**
   - 用户把窗口拉下来后，恢复普通可拖拽、可显示业务内容的浮窗。
   - detached 浮窗不再尝试和菜单栏融合。

### 下一轮执行计划

1. **先停用旧 NSPanel 菜单栏 bridge**
   - 在 hosted/collapsed 状态下，不再绘制 full-width `leftBridge` / `rightBridge`。
   - 主 panel 只负责刘海下方 body，不再假装覆盖菜单栏左右区域。
   - 这样可以避免当前截图里左右两块突兀黑块和空内容条。

2. **让 snap 后立即进入可见 expanded 反馈**
   - 拖拽释放并吸附成功时，不直接停在 `collapsed`。
   - 先进入 `expanded` 或短暂 `expanded feedback` 状态，让用户看到内容确实回到刘海区域。
   - 延迟后再根据鼠标是否离开刘海区域收回 collapsed。

3. **把 MenuBarBridgeProbe 升级为真实状态层**
   - 让 menu bar layer 接收 `NotchHostState.mode` / `expansionProgress`。
   - collapsed 时显示菜单栏内的极简融合块。
   - expanded 时配合下方 body 做伸缩动画。
   - 如果 `NSStatusItem` 无法靠近刘海，只保留为技术限制记录，不再把它当作完整融合方案。

4. **重新定义视觉验收标准**
   - 拖上去吸附后：不能出现“只有黑条、没有内容反馈”的状态。
   - hover 刘海时：内容必须可见，并从刘海区域向下展开。
   - 离开后：可收回为极简黑色融合态。
   - 拖下来后：必须回到完整 detached 浮窗。

### 本轮已完成结果

已完成最小可验证 spike：

- 新增 `Overlay/MenuBarBridgeProbe.swift`。
- 在 `AppDelegate` 启动时创建 probe，退出时释放 probe。
- 通过 `NSStatusBar.system.statusItem(withLength:)` 创建 120pt 黑色测试条。
- 仅在主屏幕存在 `auxiliaryTopLeftArea` 和 `auxiliaryTopRightArea` 时启用，避免非刘海设备误显示。
- 已把新文件接入 Xcode 工程。

### Menu Bar Spike 待验证目标

先真机验证这个最小 spike，不直接迁移完整刘海效果：

- 黑色测试条是否真的出现在顶部导航栏内部，而不是屏幕工作区里。
- 它是否能被放在刘海附近，而不是只能被系统挤到右侧状态项区域。
- 它是否遮挡、挤压或扰乱已有系统菜单栏图标。

### 已完成步骤

1. **新增 Menu Bar Layer Probe**
   - 新建 `Overlay/MenuBarBridgeProbe.swift`。
   - 使用 `NSStatusBar.system.statusItem(withLength:)` 创建 status item。
   - 给 `statusItem.button` 或自定义 view 设置黑色背景/测试形状。
   - 提供 `setup()` / `teardown()`，由 `NotchHostPanelManager` 或 `AppDelegate` 控制。

2. **接入但保持低风险**
   - 默认只在有刘海时启用。
   - 初始只显示一个测试条，不接入业务 widget。
   - 当前接入点在 `AppDelegate`，可快速移除或替换成正式 menu bar layer manager。

### 待验证分支

1. **如果测试条能出现在菜单栏内**
   - 下一轮把左右 bridge 拆成两个/多个 status item，逐步模拟刘海两侧黑色融合。
   - Body Layer 保持现有 `NotchFusionView` 的下方 body。

2. **如果测试条不能满足视觉要求**
   - 记录公开 API 限制。
   - 停止追求“整段导航栏完全覆盖”，改做近似方案：菜单栏内 status item + 刘海下方 dynamic island body。

3. **后续清理旧错误方向**
   - 保留诊断日志到验证完成。
   - 后续确认 menu bar layer 可行后，移除 `hostTopY` 强行上推逻辑，避免主 panel 继续尝试进入菜单栏。

### 后续实施步骤

1. **真机运行并截图**
   - 启动 app。
   - 观察顶部菜单栏是否出现 120pt 黑色测试条。
   - 截图记录测试条真实位置。

2. **根据截图选择路线**
   - 如果测试条能出现在菜单栏内：
     - 下一轮把左右 bridge 拆成两个/多个 status item，逐步模拟刘海两侧黑色融合。
     - Body Layer 保持现有 `NotchFusionView` 的下方 body。
   - 如果测试条不能满足视觉要求：
     - 记录公开 API 限制。
     - 停止追求“整段导航栏完全覆盖”，改做近似方案：菜单栏内 status item + 刘海下方 dynamic island body。

3. **清理旧错误方向**
   - 保留诊断日志到验证完成。
   - 后续确认 menu bar layer 可行后，移除 `hostTopY` 强行上推逻辑，避免主 panel 继续尝试进入菜单栏。

### 验证方式

1. `swift test`：已通过，97 个测试通过。
2. `xcodebuild -project ../token_hud.xcodeproj -scheme token_hud -destination 'platform=macOS' build`：已通过。
3. 真机手动验证：待执行。
   - 顶部菜单栏是否出现黑色测试条。
   - 测试条是否在菜单栏内部，而不是菜单栏下方。
   - 是否遮挡或挤压已有系统菜单栏图标。
   - App 启动/关闭后 status item 是否正确创建和释放。

### 风险

- `NSStatusItem` 只能占用菜单栏 item 区域，不能任意覆盖整段菜单栏。
- 菜单栏空间由系统和用户已有状态项共同管理，测试条可能被挤到右侧，而不是精确贴近刘海。
- 若要精确覆盖刘海两侧大面积区域，公开 API 可能不支持；届时需要降低视觉目标，或明确研究 private API/非 App Store 方案。
