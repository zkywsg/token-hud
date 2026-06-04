# 短期计划

这个文件跟踪当前项目正在进行的实现工作。保持内容小而可执行；可长期保留的决策沉淀到 `docs/`。

## 当前重点：修复 Xcode 运行 attach by pid 失败（已实现，待手动 Run 验证）

### 问题

用户在 Xcode 运行 app 时遇到：

```text
error: attach by pid '40216' failed -- attach failed (attached to process, but could not pause execution; attach failed)
```

本轮排查结果：

- `xcodebuild -project ../token_hud.xcodeproj -scheme token_hud -destination 'platform=macOS' build` 能通过，说明不是编译错误。
- 当前 `project.yml` / `project.pbxproj` 配置为：
  - `CODE_SIGNING_ALLOWED = NO`
  - `CODE_SIGNING_REQUIRED = NO`
  - `CODE_SIGN_STYLE = Manual`
- 默认构建出的 Debug app bundle 不是有效签名产物：
  - `codesign --verify --verbose=4 .../token_hud.app` 报错：
    - `code has no resources but signature indicates they must be present`
  - 该状态下 Xcode/LLDB attach 到 app pid 可能失败。
- 用命令行临时覆盖签名参数验证：
  - `CODE_SIGNING_ALLOWED=YES CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=-`
  - 构建成功，并执行了 `CodeSign ... Sign to Run Locally`。
  - 新产物 `codesign --verify --verbose=4` 通过。
  - entitlements 包含 `com.apple.security.get-task-allow = true`。

因此当前根因判断是：为了跳过签名而禁用 code signing，导致 Debug app bundle 签名无效，Xcode 可以构建但 LLDB 无法稳定 attach。

### 本轮目标

- 让本地 Debug 构建默认使用 ad-hoc signing（`Sign to Run Locally`）。
- 保持不依赖 Apple Developer Team，不引入正式证书要求。
- 确保 Xcode 直接 Run 时产物带 `get-task-allow = true`，LLDB 可以 attach。
- 保持命令行 `xcodebuild` 验证仍可通过。

### 实施步骤

1. **修改 XcodeGen 配置**
   - 在 `project.yml` 中把 target signing 配置改为：
     - `CODE_SIGNING_ALLOWED: "YES"`
     - `CODE_SIGNING_REQUIRED: "YES"`
     - `CODE_SIGN_STYLE: Manual`
     - `CODE_SIGN_IDENTITY: "-"`
     - `DEVELOPMENT_TEAM: ""`
   - 保留现有 `CODE_SIGN_ENTITLEMENTS: token_hud/token_hud.entitlements`。

2. **同步 Xcode 工程**
   - 优先运行 `xcodegen generate` 重新生成 `token_hud.xcodeproj`。
   - 如果本地 `xcodegen generate` 因既有工程复制冲突失败，则对 `project.pbxproj` 做等价最小修改，保持和 `project.yml` 一致。

3. **验证签名和构建**
   - 运行：
     - `xcodebuild -project ../token_hud.xcodeproj -scheme token_hud -destination 'platform=macOS' build`
     - `codesign --verify --verbose=4 <Debug token_hud.app>`
     - `codesign -d --entitlements :- <Debug token_hud.app>`
   - 确认：
     - app bundle valid on disk。
     - entitlements 包含 `com.apple.security.get-task-allow = true`。

4. **给出运行建议**
   - 如果 Xcode 仍旧 attach 失败，建议清理旧 DerivedData 或重新打开 project，因为旧无效签名产物可能仍被 Xcode 缓存。

### 本轮实现结果（2026-06-04）

- `project.yml` 已把 target signing 改成本地 ad-hoc signing：
  - `CODE_SIGNING_ALLOWED: "YES"`
  - `CODE_SIGNING_REQUIRED: "YES"`
  - `CODE_SIGN_IDENTITY: "-"`
  - `CODE_SIGN_STYLE: Manual`
  - `DEVELOPMENT_TEAM: ""`
- `token_hud.xcodeproj/project.pbxproj` 已做等价最小同步：
  - Debug / Release target build settings 均改为 `CODE_SIGNING_ALLOWED = YES`、`CODE_SIGNING_REQUIRED = YES`、`CODE_SIGN_IDENTITY = "-"`。
- 已尝试运行 `xcodegen generate`，但仍遇到既有工程复制冲突：
  - `XcodeGen couldn’t be copied to token_hud because an item with the same name already exists`
  - 因此本轮没有依赖 xcodegen 输出，而是手动保持 `project.yml` 与 `project.pbxproj` 一致。
- 默认 `xcodebuild` 不再需要命令行 signing override，构建过程会执行：
  - `Signing Identity: "Sign to Run Locally"`
  - `CodeSign ... token_hud.app`
- 产物 entitlements 已包含：
  - `com.apple.security.get-task-allow = true`
  - `com.apple.security.app-sandbox = false`

### 验证

- `xcodebuild -project ../token_hud.xcodeproj -scheme token_hud -destination 'platform=macOS' build`：通过，并执行 `Sign to Run Locally`。
- `codesign --verify --verbose=4 /Users/lauzanhing/Library/Developer/Xcode/DerivedData/token_hud-hilycrftzevwvucmmyckksjjimrz/Build/Products/Debug/token_hud.app`：通过，`valid on disk`。
- `codesign -d --entitlements :- /Users/lauzanhing/Library/Developer/Xcode/DerivedData/token_hud-hilycrftzevwvucmmyckksjjimrz/Build/Products/Debug/token_hud.app`：通过，包含 `get-task-allow = true`。
- `swift test`：121 个测试通过。
- 手动验证：
  - Xcode 直接 Run 不再出现 `attach by pid ... failed`。

### 风险

- ad-hoc signing 只适合本地开发运行，不是发布签名。
- 如果 Xcode 仍从旧 DerivedData 启动旧 app，需要清理 DerivedData 后再验证。
- 如果用户机器的 Xcode scheme 覆盖了 signing 设置，仍可能需要检查 scheme 的 Run 配置。

---

## 当前重点：修复 hosted compact 悬停不展开（已实现，待真机验证）

### 问题

当前样式已回到“单一 hosted surface + compact top cap/status slot”的方向，但用户反馈鼠标悬停后无法展开。结合 `docs/notch-dynamic-island-implementation-reference.md` 与 `docs/notch-open-source-research.md` 复查，触发机制存在明显冲突：

- 代码已有 `NotchTrackingContainerView.hitTest` 和 `hostedHitMask(in:)`，目标是只让 `topCap` / `body` 这些可见区域接收事件，透明区域穿透到菜单栏或桌面。
- 但 hosted 收起态多处把 `overlayWindow?.ignoresMouseEvents` 设为 `true`：
  - `animateToCollapsed`
  - `snapToCollapsed`
  - `screenParametersChanged`
  - `restoreState`
- 一旦 window 整体忽略鼠标，`hitTest`、tracking area、SwiftUI hover、本地 mouse monitor 都不会生效，只能依赖 `NSEvent.addGlobalMonitorForEvents(.mouseMoved)`。
- global monitor 对系统菜单栏、当前 app 自身 window、Space/私有层级里的事件并不稳定；成熟实现通常会把“透明区域穿透”和“可见触发区接收事件”拆开，而不是让整个 window ignore mouse。

因此本轮判断根因是：收起态事件策略错了，不是 hover region 的视觉尺寸或位置单独没调好。

### 本轮目标

- hosted compact 收起态仍保持菜单栏/透明区域不被大面积遮挡。
- compact 可见 top cap/status slot 区域能够稳定触发 hover expand。
- expanded 状态鼠标离开 top cap/body 后仍能按当前策略延迟收回。
- 触发路径对菜单栏区域、SkyLight hosted surface、public fallback 都尽量一致。
- 用纯逻辑测试锁住“hosted window 不应整体忽略鼠标”的策略，避免后续又改回旧路线。

### 实施步骤

1. **补失败测试**
   - 在 `NotchSurfacePolicyTests` 增加 mouse event policy 测试：
     - `.collapsed` hosted window 不应设置 `ignoresMouseEvents = true`。
     - `.expanded` hosted window 不应设置 `ignoresMouseEvents = true`。
     - `.detached` window 不应设置 `ignoresMouseEvents = true`。
   - 这个测试锁定核心原则：由 `hitTest` / hit mask 控制穿透，不由整窗 ignore mouse 控制穿透。

2. **新增 Notch mouse event policy**
   - 在 `NotchSurfacePolicy.swift` 增加 `NotchMouseEventPolicy`。
   - `NotchHostPanelManager` 所有 hosted/detached 状态切换统一调用该 policy，不再分散写 `hostState.isCollapsed` 或硬编码 `true/false`。

3. **改 hover monitor 策略**
   - 保留 global mouse monitor，用于鼠标在其他 app / 桌面区域移动时判断进入或离开刘海区域。
   - 增加 local mouse moved monitor，用于鼠标进入本 app hosted window 可见 top cap/body 后稳定触发。
   - `makeWindow` 对 hosted surface 设置 `acceptsMouseMovedEvents = true`。
   - local/global 两条路径最终进入同一个 `handleMouseMove`，避免状态机分叉。

4. **让 hit mask 真正接管穿透**
   - 收起态 overlay window 保持 `ignoresMouseEvents = false`。
   - `NotchTrackingContainerView.hitTest` 继续只允许 `hostedHitMask` 内部命中：
     - collapsed：`topCap`
     - expanded：`topCap.union(body)`
   - 这样 compact 可见区域能接收 hover，透明区域仍可穿透。

5. **补触发诊断**
   - hover expand/collapse 决策点打印轻量日志：
     - event source：global / local
     - 当前 mode
     - mouse 是否在 notch region
   - 日志只在状态动作发生时输出，避免鼠标移动刷屏。

### 本轮实现结果（2026-06-04）

- 新增 `NotchMouseEventPolicy`：
  - `.collapsed` / `.expanded` / `.detached` 都不再要求整窗 `ignoresMouseEvents = true`。
  - 核心原则改为：window 保持接收鼠标，透明区域穿透交给 `hostedHitMask(in:)` 和 `NotchTrackingContainerView.hitTest`。
- `NotchHostPanelManager` 已移除 hosted 收起态整窗忽略鼠标的写法：
  - `animateToCollapsed`
  - `snapToCollapsed`
  - `screenParametersChanged`
  - `restoreState`
- hosted / detached 状态切换统一通过 `NotchMouseEventPolicy.shouldIgnoreWindowMouseEvents(mode:)` 设置 window 事件策略。
- hosted surface window 设置 `acceptsMouseMovedEvents = true`。
- hover 触发从单一路径改为双路监听：
  - global mouse monitor：继续覆盖鼠标在其他 app / 桌面区域移动的情况。
  - local mouse monitor：覆盖鼠标进入本 app hosted top cap/body 后的事件，避免只依赖 global monitor。
- local/global mouse move 统一进入同一个 `handleMouseMove`：
  - collapsed + inside：展开。
  - expanded + outside：只在没有 pending timer 时安排收起，避免反复重建 timer。
  - expanded + inside：只在存在 pending timer 时取消，避免鼠标移动刷日志。
- hover 状态动作发生时输出轻量诊断：
  - `source`
  - `action`
  - `mode`
  - `mouseInsideNotchRegion`

### 验证

- `swift test --filter NotchSurfacePolicyTests`：13 个测试通过。
- `swift test`：121 个测试通过。
- `xcodebuild -project ../token_hud.xcodeproj -scheme token_hud -destination 'platform=macOS' build`：通过。
- 真机验证：
  - app 启动后 hosted compact 收起态只显示刘海两侧状态。
  - 鼠标移动到 compact top cap/status slot 上能稳定展开。
  - 鼠标离开展开 body 后能稳定收回。
  - 透明区域不吞掉菜单栏点击。
  - detached 后再次吸附回刘海，hover 仍可展开。

### 风险

- hosted window 由 `ignoresMouseEvents = true` 改为 `false` 后，如果 hit mask 计算错误，可能短暂吞掉比预期更大的菜单栏区域；需要用真机点击菜单栏验证。
- local/global monitor 同时存在，可能重复触发同一状态动作；需要通过 `NotchTransitionPolicy` 和当前 mode guard 保持幂等。
- SkyLight 私有 Space 下事件分发可能和 public fallback 不完全一致；如果 local monitor 仍不触发，需要进一步在 `NotchTrackingContainerView` 增加 tracking area / `mouseEntered` 兜底。

---

## 当前重点：按 Notch 参考文档纠偏 hosted 实现（已实现，待真机验证）

### 问题

根据 `docs/notch-dynamic-island-implementation-reference.md` 和 `docs/notch-open-source-research.md` 对当前实现复查后，主方向已经从“多个黑块/shoulder cap 拼接”回到“单一 hosted surface + compact 左右 slot”，但仍有几处实现路径不够稳：

- `SkyLightNotchSpace` 对私有 API 调用结果判定不严：
  - `SLSSpaceSetAbsoluteLevel` / `SLSShowSpaces` 的返回值被忽略。
  - `SLSSpaceAddWindowsAndRemoveFromSpaces` 无论返回码是什么都返回成功。
  - 这会导致日志显示 `skyLightSpace` 已启用，但实际 window 可能没有成功进入目标 Space，是“仍然无法进入菜单栏区域”的高风险点。
- `publicPanel` fallback 使用 `.screenSaver` window level，和参考文档里的公开路线不一致：
  - 成熟开源项目更常用 `.statusBar` 或 `.mainMenu + n`。
  - `.screenSaver` 可能过度遮挡系统 UI，也可能影响拖拽、菜单栏事件和系统交互。
- hosted 展开/收起状态机仍然过粗：
  - 当前主要只有 `collapsed` / `expanded` / `detached`。
  - `isAnimating` 基本没有真正约束 SwiftUI 动画。
  - 快速 hover in/out 或拖拽中断时，仍可能出现动画抢占、状态抖动或 hit mask 与视觉不同步。
- 旧 `NotchFusionLayout` / `NotchFusionView` 路线仍保留：
  - 当前 root view 已使用 `NotchHostedSurfaceView`，旧 Fusion 路线看起来不再是主路径。
  - 但旧 layout、旧 view、旧测试还在，会误导后续继续沿错误模型开发。

### 本轮目标

- 让 SkyLight / CGS 路线的成功或失败可被可靠判断，避免“日志显示成功但实际未进入菜单栏”的假阳性。
- 把公开 fallback 调整成更接近成熟项目的 window level 策略，并明确它只提供近似效果。
- 补上 hosted transition generation / phase 管理，让 hover、收起、展开、拖拽脱离之间不会互相抢状态。
- 清理或明确标记旧 Fusion 路线，避免后续开发再次回到旧模型。

### 实施步骤

1. **修正 SkyLight 成功判定**
   - `SkyLightNotchSpace` 记录并暴露：
     - `spaceSetAbsoluteLevel` 返回码。
     - `showSpaces` 返回码。
     - `delegateWindow` 返回码。
   - 只有关键调用返回成功时，`delegateWindow(_:)` 才返回 `true`。
   - 如果任一步失败，诊断日志明确输出失败阶段和返回码。
   - `NotchHostPanelManager.prepareOverlayForDisplay` 根据真实 delegate 结果决定是否继续标记 `overlayDelegatedToSkyLight`。

2. **调整 public fallback window level**
   - 将 `NotchSurfaceStrategy.publicPanel.windowLevel` 从 `.screenSaver` 调整到更保守的 `.statusBar` 或 `.mainMenu + 3`。
   - 保留 `skyLightSpace` 使用 `.mainMenu + 3` + private Space 的策略。
   - 在诊断日志中明确标注：
     - 当前是 `skyLightSpace` 还是 `publicPanel`。
     - public fallback 不承诺 100% 覆盖菜单栏左右两侧。

3. **补 hosted transition phase / generation**
   - 在 `NotchHostState` 或 `NotchHostPanelManager` 中增加 transition generation。
   - 每次 hover expand、collapse timer、drag detach、snap back 都递增 generation。
   - 延迟任务和动画 completion 只允许当前 generation 生效。
   - 必要时引入轻量 phase：`collapsed`、`expanding`、`expanded`、`collapsing`、`detached`，或保持 public mode 不变、内部增加 transition phase。

4. **清理旧 Fusion 路线**
   - 搜索并确认 `NotchFusionView` 是否仍被 app target 使用。
   - 如果未使用：
     - 删除 `NotchFusionView`。
     - 删除 `NotchFusionLayout` 和 `notchFusionLayout`。
     - 删除旧 Fusion layout 测试。
   - 如果仍需要保留兼容代码，则显式标记为 legacy，并确保不会被 hosted 新路线引用。

5. **补充测试**
   - SkyLight wrapper 的返回码逻辑拆成可测试的小结构或状态判断函数。
   - 增加 `NotchSurfaceStrategy` level 测试或静态断言，避免 fallback 再回到 `.screenSaver`。
   - 增加 transition generation 测试：
     - 旧 collapse timer 不应覆盖新的 expanded 状态。
     - 快速 hover out/in 后，最后一次事件决定最终状态。
   - 删除旧 Fusion 测试后，确保 hosted surface 测试覆盖 compact slot、top cap、body、hover region。

### 本轮实现结果（2026-06-04）

- 新增 `NotchSurfacePolicy` 纯逻辑：
  - `SkyLightReturnCodePolicy` 统一判断 SkyLight / CGS 返回码，当前仅把 `0` 视为成功。
  - `NotchSurfaceLevelPolicy` 明确 `skyLightSpace` 使用 `.mainMenu + 3`，`publicPanel` 使用 `.statusBar`，不再使用 `.screenSaver` 作为 hosted fallback。
  - `NotchTransitionPolicy` 和 `NotchTransitionGate` 为 hover/collapse 的 generation 防抖提供可测试基础。
- `SkyLightNotchSpace` 已记录并输出：
  - `setAbsoluteLevelReturnCode`
  - `showSpacesReturnCode`
  - `lastDelegateReturnCode`
  - 如果 Space setup 或 delegate 返回码失败，不再误报成功。
- `NotchHostPanelManager` 已接入真实 delegate 结果：
  - SkyLight delegate 失败时，立即降级为 `publicPanel`。
  - hover 在 expanded 状态重新进入 top cap/body 时，会取消 pending collapse，避免旧 timer 把当前展开态收回。
  - collapse timer 使用 generation token，过期任务不会再生效。
- 已删除旧 hosted 路线文件和工程引用：
  - `NotchFusionView.swift`
  - `NotchCollapsedView.swift`
  - `NotchExpandedView.swift`
  - `NotchEarView.swift`
  - 对应旧 `NotchFusionLayout` / `notchFusionLayout` 和旧 Fusion tests 已删除。
- `xcodegen generate` 本轮因现有 `token_hud.xcodeproj` 复制冲突失败；已手动对 `project.pbxproj` 做等价最小更新：
  - 新增 `NotchSurfacePolicy.swift`。
  - 移除已删除 legacy Swift 文件引用。

### 验证

- `swift test --filter NotchSurfacePolicyTests`：11 个测试通过。
- `swift test --filter NotchGeometryCalculator`：45 个测试通过。
- `swift test`：119 个测试通过。
- `xcodebuild -project ../token_hud.xcodeproj -scheme token_hud -destination 'platform=macOS' build`：通过。
- 真机验证：
  - 日志能明确显示 SkyLight 每一步是否成功。
  - 如果 SkyLight 失败，界面降级到 public fallback，并且日志不再误报成功。
  - 快速 hover in/out 不出现展开/收起状态错乱。
  - 拖拽脱离和再次吸附后，hosted top cap 仍回到 canonical geometry。
  - app 内不再存在可被误用的旧 Fusion 主路径。

### 风险

- SkyLight / CGS 是私有 API，不同 macOS 版本返回码语义可能有差异；需要先记录真实返回值，再决定是否兼容多种“成功码”。
- 降低 public fallback level 后，如果 SkyLight 不可用，菜单栏融合能力可能变弱；但这比 `.screenSaver` 误伤系统 UI 更可控。
- transition phase 改动会影响 hover、drag、snap 多条路径，需要保持范围集中并用测试锁住。
- 删除旧 Fusion 路线前要确认没有 storyboard/project target 或预览仍引用它。

---

## 当前重点：重做刘海融合 compact 形态（开源路线纠偏，已实现，待真机验证）

### 问题

用户在 2026-06-04 的截图中指出，当前 “左右小格 + shoulder cap” 适配完全不对：

- 刘海两边出现两个孤立的黑色竖块，视觉上不像从刘海自然延展。
- 左侧进度和右侧百分比被拆成两个独立面板，中间缺少连续轮廓。
- 当前方案是在错误形态上继续补边，不能再沿用。

本轮系统性排查后判断，根因不是参数没调好，而是形态建模错了：我们把刘海融合拆成了多个局部黑块，再用 `leftShoulder` / `rightShoulder` 去补缝。这会天然产生断裂、竖边和定位不稳定，和用户要的“刘海弹开”相反。

### 开源调研结论

已重新查看 Boring Notch、Atoll、SuperIsland 的公开仓库和源码，关键做法如下：

- Boring Notch / Atoll：
  - 使用单个居中的 notch surface，而不是多个左右窗口或多个孤立黑块。
  - 通过 `auxiliaryTopLeftArea` / `auxiliaryTopRightArea` 计算真实刘海宽度。
  - 用一个 `NotchShape` 统一裁剪外壳，顶部和底部圆角是同一个 shape 的参数。
  - 强融合/锁屏等场景使用 SkyLight / CGS Space 提升窗口层级。
- SuperIsland：
  - 使用透明 `NSPanel`，`statusBar` level，窗口根据 notch rect 居中贴顶。
  - hosting view 保持最大尺寸，window 作为 clipping viewport，展开前先放大 viewport，收起动画结束后再缩回 compact，避免 SwiftUI relayout 跑偏。
  - compact 状态在 notched Mac 上支持 `minimalLeading` / `minimalTrailing` 两侧内容，但它们在同一个 compact surface 内渲染，中间让硬件刘海自然隐藏，而不是画两个独立竖块。

因此，本项目应废弃当前 “左右独立小格 + shoulder cap” 路线，改成“单一连续 top cap + 下拉 body”的路线。

### 本轮目标

- 删除/停用当前错误形态：
  - 移除 `NotchHostedSurfaceLayout.leftShoulder` / `rightShoulder`。
  - 移除 `NotchShoulderCapShape`。
  - 不再绘制两个脱离主轮廓的黑色竖块。
- 重建 compact 刘海形态：
  - collapsed 时只保留一个连续的 top cap，宽度 = 真实刘海宽度 + 左右状态槽扩展。
  - top cap 顶边贴住 `screen.frame.maxY`，以菜单栏真实区域为定位基准。
  - 左侧进度条和右侧百分比作为 top cap 内部的 leading/trailing status slot，不作为独立面板。
  - 中间刘海区域保持纯黑/空内容，由硬件刘海自然吞掉，避免在中间画条。
  - 外侧底角使用同一个连续 shape 的圆角，不再用额外黑块补缝。
- 重建展开动画：
  - hover top cap 时，body 从刘海下方向下延展。
  - compact top cap 始终是展开动画的锚点；body 高度和宽度向下/向外插值。
  - 内容在 body 高度足够后淡入，避免一开始文字压在菜单栏区域。
- 重建 hitbox：
  - collapsed 命中区覆盖整个 top cap，不覆盖整条菜单栏。
  - expanded 命中区覆盖 top cap + body。
  - 不再只依赖很小的左右小格作为触发区。
- 保持定位稳定：
  - hosted 仍以目标 screen 的 notch rect / frame 顶部定位。
  - 拖拽/吸附期间不根据鼠标所在屏幕反复切换目标 screen。
  - 展开时 window 可临时使用最大尺寸作为 clipping viewport；收起动画结束后再缩回 compact，避免定位漂移。

### 实施步骤

1. **补充失败测试**
   - 在 `NotchGeometryCalculatorTests` 中新增 compact top cap 测试：
     - collapsed 布局只有一个连续 `topCap`，不再有 `leftShoulder/rightShoulder`。
     - `leftStatusSlot` 和 `rightStatusSlot` 必须完全包含在 `topCap` 内。
     - `topCap.width` 至少覆盖真实 notch gap，并根据安全边距限制左右扩展。
     - collapsed 可见高度不应产生向下悬挂的大竖块。
   - 新增 hover 测试：
     - collapsed hover region 覆盖整个 `topCap`。
     - hover region 不覆盖整条 screen 顶部。

2. **重写 geometry 模型**
   - 将 hosted surface layout 从 “left ear/right ear/body/shoulder” 改成：
     - `topCap`
     - `leftStatusSlot`
     - `rightStatusSlot`
     - `body`
     - `contentOpacity`
   - compact 宽度计算参考 SuperIsland：
     - 基础宽度取真实 notch width。
     - 左右扩展先用 44-56pt。
     - 如果左右菜单栏安全空间不足，则自动缩小或关闭 side status。
   - expanded 继续使用现有目标宽度，但从 `topCap` 中心连续插值。

3. **重写 `NotchHostedSurfaceView`**
   - 用同一个连续 top cap 和下拉 body 绘制黑色外壳。
   - collapsed 时只显示 top cap 和内部 status slot。
   - expanded 时同一个 shape 向下长出 body。
   - 移除 `NotchShoulderCapShape` 和独立 shoulder 绘制。
   - 左右状态只作为 overlay 内容渲染在 `leftStatusSlot/rightStatusSlot` 内。

4. **调整 `NotchHostPanelManager`**
   - hit mask 改为 `topCap.union(body)`。
   - hover 判定改为 compact top cap / expanded surface。
   - 保留“展开前窗口放大、收起后延迟缩回”的 clipping viewport 思路，避免再次出现拖拽后位置随机偏移。

5. **文档沉淀**
   - 实现完成后新增 `docs/work-log/2026-06-04-notch-fusion-rebuild.md`。
   - 文档里记录：废弃 shoulder cap 的原因、参考开源项目的架构原则、最终 geometry 约定。

### 本轮实现结果（2026-06-04）

- `NotchHostedSurfaceLayout` 已从 “left/right ear + left/right shoulder + body” 改为：
  - `topCap`
  - `notchGap`
  - `leftStatusSlot`
  - `rightStatusSlot`
  - `body`
  - `contentOpacity`
- collapsed 状态只保留一个连续 `topCap`：
  - `topCap` 覆盖真实 notch gap 和左右状态槽。
  - 左侧进度条、右侧百分比都在 `topCap` 内部渲染，不再作为独立黑块。
  - `body.height == 0`，避免收起时向屏幕下方悬挂一大块。
- expanded 动画从同一个 `topCap` 往下长出 `body`：
  - 黑色 body 在高度增长时先出现。
  - body 内容通过 `contentOpacity` 延迟淡入，避免文字挤在菜单栏区域。
- hover / hitbox 已改为新模型：
  - collapsed hover region 是一个围绕 `topCap` 的连续区域。
  - collapsed 点击命中只接收 `topCap`。
  - expanded 点击命中接收 `topCap.union(body)`。
- 已删除 hosted surface 里的 shoulder cap 绘制路径，不再用左右补丁块遮缝。

### 验证

- `swift test --filter NotchGeometryCalculator`：已通过，48 个 geometry 相关测试通过。
- `swift test`：已通过，111 个测试通过。
- `xcodebuild -project ../token_hud.xcodeproj -scheme token_hud -destination 'platform=macOS' build`：已通过。
- 真机验证：
  - collapsed 时不能再出现两个孤立竖块。
  - 刘海两侧只在同一个 top cap 内显示进度/百分比。
  - 鼠标移到 top cap 任意位置都能展开。
  - 展开动画从刘海区域向下长出，收回时缩回 top cap。
  - 拖拽后再次吸附，位置稳定，不随机偏移。

### 风险

- 公开 `NSPanel` 路线仍可能受菜单栏层级限制；如果需要 100% 覆盖菜单栏，仍要回到 SkyLight / CGS 策略。
- 不同机型 notch 宽度和菜单栏图标密度不同，side status 需要根据安全空间动态缩小。
- 不能复制 GPL 项目源码；只吸收架构原则，重新实现本项目自己的 geometry 和 shape。

---

## 历史记录：修复刘海圆角缝隙并明确触发标识（已实现，但已判定不可接受）

### 问题

用户在 2026-06-04 的截图中指出两个问题：

1. 当前 collapsed 左右小格靠近刘海的一侧是直角，没有考虑真实刘海下方左右两个角的弧度，导致小格和刘海之间出现蓝色镂空缝隙，视觉很不自然。
2. 触摸下拉的范围不明确，用户不知道应该摸哪里才能展开。

用户提出两个方向：

- 完全覆盖，让所有地方都可触发。
- 给出明确视觉标识。

### 当前判断

不建议回到“整条菜单栏都可触发”，因为这会重新引入误触：鼠标扫过任意菜单栏位置都会展开。更合适的路线是：

- 可见层：保留左右小格，但补上刘海底部圆角过渡，让小格与刘海视觉融合。
- 交互层：给左右小格一个明确的触发标识，同时把隐形 hitbox 扩大到比可见标识更容易摸到。

### 本轮目标

- 解决刘海下方左右圆角导致的镂空缝隙：
  - 左右小格靠近 notch gap 的一侧增加黑色圆角过渡/shoulder cap。
  - 过渡层应向刘海下方轻微覆盖 8-12pt，遮住真实刘海圆角外侧的背景缝。
  - collapsed 和 expanded 过程中都不应露出明显蓝色缝。
- 触发范围明确：
  - 左右小格内增加轻量视觉标识，例如底部短横/亮点。
  - 标识不应喧宾夺主，保持弱对比。
  - 实际 hover hitbox 大于可见小格，例如可见 44pt，命中宽度约 64-72pt。
- 保持上一轮策略：
  - hosted window 仍固定 expanded frame。
  - 展开/收回仍由 `expansionProgress` 驱动。
  - 不回退到 window resize 动画。

### 本轮实现结果（2026-06-04）

- `NotchHostedSurfaceLayout` 新增：
  - `leftShoulder`
  - `rightShoulder`
- `NotchGeometryCalculator` 新增常量：
  - `notchShoulderWidth = 12`
  - `notchShoulderDrop = 10`
  - `collapsedTriggerHitPadding = 14`
  - `collapsedHoverPadding` 改为复用 `collapsedTriggerHitPadding`
- `hostedSurfaceLayout` 计算左右 shoulder rect：
  - 左 shoulder 贴住 `notchGap.minX`，向下覆盖 `10pt`。
  - 右 shoulder 贴住 `notchGap.maxX`，向下覆盖 `10pt`。
  - 用于遮住刘海底部圆角外侧的蓝色缝隙。
- `notchHoverRegions` 的可触发 hitbox 从 44pt 可见小格扩大到 72pt 宽，但仍只围绕左右小格，不覆盖整条菜单栏。
- `NotchHostedSurfaceView` 新增：
  - `NotchShoulderCapShape`，绘制左右黑色圆角过渡块。
  - 小格底部低透明短 handle，给用户明确触发位置。
- `NotchHostPanelManager.hostedHitMask` 把 shoulder rect 也纳入 hosted 可交互区域，避免可见黑色过渡块穿透异常。
- `NotchGeometryCalculatorTests` 新增 shoulder cap 与 widened hitbox 测试。

验证结果：

- `swift test --filter NotchGeometryCalculator` 通过，49 个测试通过。
- `swift test` 通过，112 个测试通过。
- `xcodebuild -project ../token_hud.xcodeproj -scheme token_hud -destination 'platform=macOS' build` 通过。

### 实施步骤

1. **补充 geometry/layout 测试**
   - 在 `NotchHostedSurfaceLayout` 增加左右 shoulder/corner fill rect。
   - 测试 collapsed 下：
     - left/right shoulder 与 notch gap 左右边相邻或轻微覆盖。
     - shoulder 高度覆盖菜单栏底部到 body 顶部附近的过渡区。
   - 测试 hover region：
     - hover region 宽度大于可见 pill 宽度。
     - hover region 仍不覆盖整条菜单栏。

2. **调整 `NotchGeometryCalculator`**
   - 新增常量：
     - `notchShoulderWidth`，建议 12pt。
     - `notchShoulderDrop`，建议 10pt。
     - `collapsedTriggerHitPadding`，建议 14pt。
   - `hostedSurfaceLayout` 返回左右 shoulder rect。
   - `notchHoverRegions` 使用更大的 hit padding，但仍只围绕左右小格。

3. **调整 `NotchHostedSurfaceView`**
   - 在 ears/body 之前或之后绘制 shoulder cap：
     - 黑色填充。
     - 用圆角/Path 形成内侧圆角过渡，避免直角贴刘海。
   - 左右小格增加触发标识：
     - 左侧可在进度条下方或底部中央加很短的浅色 handle。
     - 右侧百分比旁或底部加对应 handle。
   - body 顶部保持与 shoulder cap 同色，避免 expanded 时断层。

4. **验证**
   - 运行 `swift test --filter NotchGeometryCalculator`。
   - 运行 `swift test`。
   - 运行 `xcodebuild -project ../token_hud.xcodeproj -scheme token_hud -destination 'platform=macOS' build`。
   - 真机验证：
     - collapsed 时刘海下方左右圆角不再出现蓝色缝。
     - 左右小格触发位置有明确视觉提示。
     - 小格附近容易 hover 展开，但扫过远离刘海的菜单栏位置不会误触。
     - 展开/收回过程圆角过渡不闪烁、不露缝。

### 风险

- 真实刘海圆角尺寸不同设备可能不同；第一版用 12pt/10pt 经验值，后续可根据 safe area 或截图微调。
- shoulder cap 如果画得太多，会像重新变成长条；需要控制宽度和 opacity。
- 视觉标识如果太亮，会影响“融入刘海”的感觉；第一版用低透明白色短 handle。

---

## 历史记录：重做 collapsed 刘海左右小格与下拉展开（已实现，待真机验证）

### 问题

当前 hosted collapsed 状态仍然显得太长、不连贯。用户在 2026-06-04 的截图中指出：刘海两侧的黑色状态区横向过长，视觉上像一整条黑条，而不是刘海左右各一个小状态块。

期望效果：

- 收起时只在刘海左右两边各保留一小格。
- 左右小格仍能表达极简用量状态，例如左侧短进度、右侧百分比。
- 鼠标摸到任意一个小格时，完整小窗从刘海区域向下延展。
- 动画看起来像从刘海两侧状态块自然拉开，而不是长条突然变大。

### 当前判断

当前 `NotchHostedSurfaceView` 已经把 collapsed/expanded 合并为一个 surface，并通过 `expansionProgress` 做连续动画，这是正确基础。

问题主要在 geometry 与 hover 命中区：

1. `hostedSurfaceLayout` 的 ears 在 collapsed 时使用 expanded surface 剩余空间计算，导致左右耳朵过长。
2. `notchRegion` 对刘海屏返回整屏顶部宽度，鼠标扫过顶部菜单栏任何位置都可能触发展开，不符合“摸左右小格才展开”。
3. collapsed body 起始宽度仍偏大，展开时缺少“从两个小格往下长出”的视觉集中感。

### 本轮目标

- collapsed 状态只显示左右两个短状态格：
  - 建议每侧宽度先用 44pt。
  - 中间 notch gap 保持透明。
  - 不画横跨刘海两侧的大面积黑条。
- hover 命中区从“整屏顶部”收缩到左右状态格附近：
  - 命中区覆盖左右小格。
  - 保留少量 padding，避免太难触发。
- expanded 状态保持当前完整小窗能力。
- collapsed -> expanded 动画改为：
  - 左右小格横向扩展。
  - 下方 body 从刘海下方长出。
  - 内容在 body 高度足够后淡入。
- expanded -> collapsed 动画反向收回，只留下左右小格。

### 本轮实现结果（2026-06-04）

- `NotchGeometryCalculator` 新增 `collapsedStatusPillWidth = 44` 和 `collapsedHoverPadding = 10`。
- `hostedSurfaceLayout` 改为：
  - collapsed 时 left/right ear 各 44pt，并贴在 notch gap 左右两侧。
  - expanded 时 ears 和 body 从 notch center 向外插值扩展到完整面板宽度。
  - body collapsed 起始宽度改为 `notchGapWidth + 2 * collapsedStatusPillWidth`，不再一开始就铺成宽条。
- 新增 `notchHoverRegions(screenFrame:geometry:)`：
  - 刘海屏返回左右两个 compact hover region。
  - 不再让整条顶部菜单栏都触发展开。
- `NotchHostPanelManager.isMouseInNotchRegion()` 改为：
  - collapsed 时只看左右小格 hover region。
  - expanded 时额外把 body 作为停留区域，避免鼠标在面板内时立刻收回。
- `NotchHostedSurfaceView` 微调 44pt 小格内部视觉：
  - 左侧进度条缩短并减少 padding。
  - 右侧百分比改小字号和更强缩放，适配 44pt 宽度。
  - 小格底部外侧圆角收紧到 7pt。
- `NotchGeometryCalculatorTests` 新增 compact pill 和 hover region 覆盖。

验证结果：

- `swift test --filter NotchGeometryCalculator` 通过，47 个测试通过。
- `swift test` 通过，110 个测试通过。
- `xcodebuild -project ../token_hud.xcodeproj -scheme token_hud -destination 'platform=macOS' build` 通过。
- 本轮未新增 Swift 文件，不需要重新运行 `xcodegen generate`。

### 实施步骤

1. **补充 geometry 测试**
   - 在 `NotchGeometryCalculatorTests` 中新增 hosted surface collapsed 小格测试：
     - `expansionProgress == 0` 时 left/right ear 宽度等于短小格宽度。
     - collapsed 两个小格的总宽度明显小于 expanded body 宽度。
     - `expansionProgress == 1` 时 body 宽度仍能达到 expanded body 宽度。
   - 新增 hover region 测试：
     - hover region 不再覆盖整屏宽度。
     - hover region 覆盖 collapsed 左右小格所在 x 范围。

2. **调整 `NotchGeometryCalculator` 常量与 layout**
   - 新增 `collapsedStatusPillWidth`，初始值 44pt。
   - 保留 `collapsedStatusEarWidth` 作为旧 fallback 或删除未用路径，避免概念混乱。
   - `hostedSurfaceLayout`：
     - collapsed ear width 从 44pt 起步。
     - expanded ear/body width 继续插值到完整面板宽度。
     - body collapsed width 从 `notchGapWidth + 2 * pillWidth` 起步，避免刚展开就太宽。

3. **收缩 hover 命中区**
   - 新增或调整纯函数，让 hover region 基于 collapsed 小格布局计算。
   - `isMouseInNotchRegion()` 使用新的 compact hover region。
   - 命中区增加 8-12pt padding，确保可用但不误触整条菜单栏。

4. **调整 `NotchHostedSurfaceView` 视觉**
   - collapsed 小格圆角更像独立小 pill：
     - 左格靠刘海一侧可保持直角或微圆。
     - 外侧用 6-8pt 圆角。
   - 左侧进度条缩短到适合 44pt 的长度。
   - 右侧百分比使用可缩放小字号，避免 100% 溢出。

5. **验证**
   - 运行 `swift test --filter NotchGeometryCalculator`。
   - 运行 `swift test`。
   - 如果新增/删除 Swift 文件，运行 `xcodegen generate`。
   - 运行 `xcodebuild -project ../token_hud.xcodeproj -scheme token_hud -destination 'platform=macOS' build`。
   - 真机验证：
     - collapsed 只露左右小格，不再是一长条。
     - 鼠标摸左右小格能顺滑下拉展开。
     - 鼠标扫过其它菜单栏位置不会误展开。
     - 收回后只剩左右小格，视觉连贯。

### 风险

- 44pt 小格可能对右侧百分比文本偏窄，尤其 `100%`；第一版使用 `minimumScaleFactor`，必要时把右侧设为 52pt。
- hover 区域缩小后可能变得难触发；需要真机调 padding。
- 如果系统菜单栏图标靠近刘海，右侧小格仍可能视觉冲突；后续可根据 `auxiliaryTopLeftArea/rightArea` 做更精细避让。
- 当前 hosted window 仍保持 expanded frame 以获得平滑动画和透明穿透；本轮只改变绘制和命中区，不回到 window resize 动画。

### 最近沉淀

- `docs/work-log/2026-06-01-notch-fusion-smooth.md`（hosted 面板重影、漂浮拖拽、动画流畅性修复）
- `docs/work-log/2026-05-31-notch-drag-settle.md`
- `docs/work-log/2026-05-31-notch-collapsed-status.md`
