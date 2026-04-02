# Token HUD — Design Spec

**Date:** 2026-03-31
**Status:** Approved

---

## Overview

利用 MacBook 刘海区域常驻显示 AI 工具订阅配额剩余量及当前 Session 消耗情况。核心目标是**被动监控**——不需要修改任何现有代码，数据来自各平台已有的 API 和本地日志。

项目拆为两个独立子项目，通过 `~/.token-hud/state.json` 完全解耦。

---

## 项目分解

| 项目 | 语言 | 职责 |
|------|------|------|
| `token-state` | TypeScript / Node.js | 开源库：从各平台读取数据，归一化写入 state.json |
| `token_hud` | Swift + SwiftUI | macOS App：监听 state.json，渲染刘海 HUD |

---

## state.json Schema（两项目唯一契约）

```json
{
  "version": 1,
  "updatedAt": "2026-03-31T10:00:00Z",
  "services": {
    "claude": {
      "label": "Claude Max",
      "quotas": [
        {
          "type": "time",
          "total": 18000,
          "used": 3600,
          "unit": "seconds",
          "resetsAt": "2026-04-30T00:00:00Z"
        },
        {
          "type": "tokens",
          "total": 1000000,
          "used": 150000,
          "unit": "tokens"
        }
      ],
      "currentSession": {
        "id": "sess_abc123",
        "startedAt": "2026-03-31T09:50:00Z",
        "tokens": 1500,
        "time": 142.5
      }
    },
    "openai": {
      "label": "OpenAI",
      "quotas": [
        { "type": "money", "total": 20.00, "used": 1.50, "unit": "USD" }
      ],
      "currentSession": null
    }
  }
}
```

**设计决策：**
- `total - used` 模式（不直接存 remaining），方便消费方计算百分比
- `currentSession` 为 `null` 表示无活跃会话
- 原子写入：先写 `state.tmp.json`，再 `rename`，防止 HUD 读到半写状态
- `resetsAt` 可选，用于重置倒计时 widget

---

## 项目 1：token-state（TypeScript 开源库）

### 定位

数据读取器 + 归一化器。被动读取各平台已有数据，写入 state.json。其他开发者可独立使用此库（不依赖 HUD）。

### 数据来源

| 平台 | 数据 | 获取方式 |
|------|------|---------|
| Claude Max | 5h/周 rate window + token 用量 | Claude OAuth API + `~/.config/claude/projects/` JSONL 日志 |
| Claude Pro | 5h/周窗口使用百分比 + 重置时间 + Claude Extra 消费 | `claude.ai` 内部 API（非官方，experimental）；sessionKey 由 Swift HUD 提取后写入 config.json |
| OpenAI | 每日 token 用量 + 消耗金额 + 预付费余额 | `/v1/usage` + `/v1/dashboard/billing/credit_grants` |
| Gemini | 配额使用率 | Google Cloud OAuth API |
| 自定义服务 | 任意配额 | 手动 `consume()`（可选兜底） |

### API 设计（三层渐进式）

```typescript
// 层 1：核心
const tracker = new TokenTracker({ stateFile: '~/.token-hud/state.json' })
tracker.addService('custom', { label: 'My API', quotas: [...] })
tracker.consume('custom', { tokens: 500, money: 0.01 })

// 层 2：Session 追踪
await tracker.withSession('claude', async (session) => {
  session.consume({ tokens: 800 })
}) // 自动 end()

// 层 3：SDK 插件（自动拦截）
import { wrapOpenAI } from 'token-state/openai'
import { wrapAnthropic } from 'token-state/anthropic'
const openai = wrapOpenAI(new OpenAI(), tracker, 'openai')
```

### Daemon 模式

```bash
token-state daemon --interval 60
```

读取 `~/.token-hud/config.json`（存放 API Key、刷新间隔、Claude sessionKey），定时拉取所有 provider 数据写入 state.json。

### 文件结构

```
token-state/
├── src/
│   ├── tracker.ts          # TokenTracker 核心类
│   ├── session.ts          # Session 类
│   ├── writer.ts           # 原子写入 state.json
│   ├── schema.ts           # TypeScript 类型定义
│   ├── providers/
│   │   ├── claude-max.ts   # Claude OAuth API + JSONL 日志
│   │   ├── claude-pro.ts   # claude.ai 内部 API（experimental）
│   │   ├── openai.ts       # OpenAI Usage + Billing API
│   │   └── gemini.ts       # Google Cloud OAuth API
│   └── plugins/
│       ├── openai.ts       # wrapOpenAI SDK 插件
│       └── anthropic.ts    # wrapAnthropic SDK 插件
├── bin/daemon.ts           # Daemon CLI
└── package.json
```

---

## 项目 2：token_hud（Swift + SwiftUI macOS App）

### 技术栈

Swift 6（strict concurrency）+ SwiftUI，macOS 13+

### Widget 系统

每个 Widget = **数据源** × **显示风格**

**数据源维度：**
```
{ service: "claude" | "openai" | "gemini" | ...,
  metric:  "remaining_time" | "reset_countdown" | "tokens_remaining" |
           "balance" | "session_tokens" | "usage_percent" }
```

**显示风格维度：**
- `ring` — 圆弧进度 + 数值
- `bar` — 横向进度条 + 数值
- `text` — 格式化文字标签（`4h 12m`、`$18.5`、`↺ 2h 14m`）
- `aggregate` — 带前缀图标的数字（`↑ 1.5k`）

**用户配置（存 UserDefaults）：**
```json
{
  "leftWidgets":  [{ "service": "claude", "metric": "remaining_time", "style": "ring" }, ...],
  "rightWidgets": [{ "service": "claude", "metric": "reset_countdown", "style": "text" }, ...]
}
```

### 核心组件

```
token_hud/
├── App/AppDelegate.swift           # LSUIElement=true，LaunchAtLogin
├── Overlay/NotchOverlayWindow.swift # 无边框透明窗口，.statusBar+1 层级，跨所有 Space
├── Overlay/LeftSideView.swift      # 刘海左侧 widget 列表
├── Overlay/RightSideView.swift     # 刘海右侧 widget 列表
├── Widgets/WidgetRenderer.swift    # 根据 WidgetConfig dispatch 到对应组件
├── Widgets/RingWidget.swift
├── Widgets/BarWidget.swift
├── Widgets/TextWidget.swift
├── Widgets/AggregateWidget.swift
├── State/StateModel.swift          # state.json Codable 模型
├── State/StateWatcher.swift        # FSEvents 监听，@Observable 推送更新
└── Settings/
    ├── SettingsWindow.swift
    ├── WidgetListEditor.swift      # 拖拽排序 + 添加/删除
    └── ServiceConfig.swift         # API Key + Claude sessionKey 提取（Safari/Chrome/Firefox/Arc）
```

### 刘海定位

- `NSScreen.main?.auxiliaryTopLeftArea` / `auxiliaryTopRightArea`（macOS 12+ API）
- `collectionBehavior: .canJoinAllSpaces`（跨所有 Space）
- 响应 `NSApplication.didChangeScreenParametersNotification`
- 无刘海机型：降级为普通 menu bar item

### Claude Pro sessionKey 提取

Swift HUD 负责从浏览器提取 `sessionKey` cookie（值以 `sk-ant-` 开头）：
- Safari：直接读取 cookie 数据库
- Chrome/Arc/Brave：SQLite + Keychain 解密
- Firefox：直接读取 SQLite

提取后：存入 Keychain + 写入 `~/.token-hud/config.json`，供 TypeScript daemon 使用。支持手动粘贴作为备选。

参考实现：[CodexBar ClaudeWebAPIFetcher](https://github.com/steipete/CodexBar)（已在生产验证）

---

## 数据流

```
各平台数据源（Claude JSONL / OAuth API / OpenAI API / Gemini API）
        ↓ token-state daemon（TypeScript，定时拉取）
~/.token-hud/state.json（原子写入）
        ↓ FSEvents（<100ms 响应）
token_hud Swift App（读取 + 渲染 widget）
        ↓
MacBook 刘海两侧常驻显示
```

---

## 验证方式

**token-state 库：**
- `npm test`：覆盖 `consume()`、原子写入、各 provider 读取器
- 手动：`token-state daemon` 运行后检查 `~/.token-hud/state.json` 是否正确更新

**token_hud：**
- 手写测试 state.json → 验证刘海 overlay 正确渲染
- FSEvents 测试：修改 state.json → HUD 应在 <100ms 内刷新
- 设置持久化测试：退出重启，widget 配置是否保留
- 无刘海机型 fallback 测试
