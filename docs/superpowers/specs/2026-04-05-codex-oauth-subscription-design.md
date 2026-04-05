# Codex OAuth 订阅查询功能设计

**日期：** 2026-04-05
**状态：** 待实现
**范围：** token-state daemon + token_hud macOS App

---

## 背景

token_hud 目前支持 Claude（session key）和 OpenAI（API key）两个平台的用量展示。本次新增对 OpenAI Codex CLI 的支持，通过读取 Codex CLI 存储在本地的 OAuth token，查询订阅状态与用量 quota。

**核心原则：** 查询与展示完全解耦。所有认证和数据拉取工作在 token-state daemon 完成，macOS App 仅读取 state.json。

---

## 调研结论

Codex CLI（2025 年 5 月发布，开源：github.com/openai/codex）的认证数据存储在 `~/.codex/auth.json`：

```json
{
  "auth_mode": "<AuthMode>",
  "tokens": {
    "id_token": "<JWT>",
    "access_token": "<JWT>",
    "refresh_token": "<string>",
    "account_id": "<optional>"
  },
  "last_refresh": "<ISO 8601>"
}
```

- **订阅 Plan**：解码 `id_token` JWT payload，读取 `chatgpt_plan_type` 字段（值：`free` / `plus` / `pro` / `team` / `enterprise` 等）
- **用量 quota**：无独立查询端点，仅在 API 响应 header 中被动返回：
  - `x-codex-primary-used-percent`：已用百分比
  - `x-codex-primary-window-minutes`：quota 窗口时长
  - `x-codex-primary-reset-at`：重置时间（ISO 8601）
- **主动探测端点**：`GET https://chatgpt.com/backend-api/codex/models`（轻量，不消耗 quota）
- **Token 刷新**：POST `https://auth.openai.com/oauth/token`，使用 `refresh_token`

---

## 架构设计

### 选型：Daemon 层处理，App 层零感知

```
~/.codex/auth.json
        │
        ▼
token-state daemon
  └─ codex-provider.js
       ├─ 文件监听（fs.watch）
       ├─ JWT 解码（本地）
       ├─ Token 刷新
       └─ 定时探测 GET /models
              │
              ▼
     ~/.token-hud/state.json
              │
              ▼
     token_hud macOS App（只读）
```

---

## 详细设计

### 一、Daemon 层：`codex-provider.js`

#### 启动流程

```
启动
  └─ 检查 ~/.codex/auth.json 是否存在
       ├─ 不存在 → 写入 codex: null，监听文件出现
       └─ 存在 → 解析 JWT，启动探测循环
```

#### 文件监听

使用 `fs.watch` 监听 `~/.codex/auth.json`，文件变化时重新解析 JWT，更新 plan/email，触发立即探测。

#### 定时探测（默认 5 分钟）

```
定时触发
  └─ 检查 access_token 是否过期（解析 JWT exp 字段）
       ├─ 已过期 → POST /oauth/token 换新 token，回写 auth.json
       └─ 未过期 → 直接使用
  └─ GET https://chatgpt.com/backend-api/codex/models
       ├─ 200 → 解析 rate limit headers → 写入 state.json
       ├─ 401 → 标记 unauthenticated，停止探测
       └─ 其他错误 → 保留上次数据，记录错误
```

#### 三个核心子函数

| 函数 | 职责 |
|------|------|
| `readAuthFile()` | 读取并验证 `~/.codex/auth.json` 结构完整性 |
| `decodeJwt(idToken)` | Base64 decode JWT payload，提取 `chatgpt_plan_type`、`email`、`exp` |
| `probeQuota(accessToken)` | GET /models，解析 `x-codex-primary-*` response headers |

Token 刷新使用原生 `fetch`（Node 18+），与现有 provider 保持一致。

---

### 二、state.json Schema

复用现有 schema，无需新增字段。

**正常状态（已登录 + 探测成功）：**

```json
{
  "services": {
    "codex": {
      "label": "Codex",
      "quotas": [
        {
          "type": "requests",
          "total": 100,
          "used": 43,
          "unit": "%",
          "resetsAt": "2026-04-05T18:00:00Z"
        }
      ],
      "currentSession": null
    }
  }
}
```

> `total: 100` + `used: <used_percent>`：将百分比映射进现有 `usedFraction` 计算逻辑，无需修改 App 数据模型。

**未登录 / auth.json 不存在：**

```json
"codex": null
```

**已登录但探测失败（网络错误等）：**

```json
"codex": {
  "label": "Codex",
  "quotas": [],
  "currentSession": null
}
```

空 `quotas` 数组，App 现有逻辑会显示 "no data"，不崩溃。

**Plan 和 email 的处理：** 不写入 state.json（避免破坏现有 schema），由 macOS App Settings UI 直接读取 `~/.codex/auth.json` 本地展示。

---

### 三、macOS App 改动

改动最小化，不涉及数据层。

#### 1. `PlatformConfig` 新增 Codex

```swift
static let all: [PlatformConfig] = [
    .claude,
    .openai,
    .codex  // 新增
]
```

#### 2. `PlatformRowView` — Codex credential section（只读）

Codex 无需用户输入 key，仅展示本地认证状态：

| 状态 | 展示内容 |
|------|----------|
| auth.json 存在且有效 | 🟢 Configured · `user@example.com` · Plan: **Pro** |
| 文件不存在 | 🟠 Not configured · "Run `codex login` to authenticate" |
| Token 已过期 | 🟡 Token expired · "Run `codex login` to refresh" |

Plan 和 email 在 App 侧本地 decode JWT 读取，不走网络。

#### 3. 不改动的文件

- `KeychainHelper.swift`：Codex token 由 CLI 自管理，不入 Keychain
- `StateModel.swift`：schema 完全兼容，无需修改
- `WidgetRenderer.swift`：Codex 复用 `requests` 类型，渲染逻辑不变

#### 4. 可选：Widget 默认值

`WidgetStore` 默认 widget 列表可加一个 Codex 用量 ring（`service: "codex"`, `metric: .usagePercent`, `style: .ring`）。

#### 文件改动清单

| 文件 | 改动类型 | 说明 |
|------|----------|------|
| `PlatformConfig.swift` | 新增 | `.codex` case |
| `PlatformRowView.swift` | 修改 | 新增 Codex 只读 credential section |
| `WidgetStore.swift` | 可选修改 | 加 Codex 默认 widget |
| token-state / `codex-provider.js` | 新增 | 完整新模块 |
| token-state / `index.js`（或入口） | 修改 | 注册 codex-provider |

---

## 错误处理策略

| 场景 | Daemon 行为 | App 展示 |
|------|-------------|----------|
| auth.json 不存在 | `codex: null` | Platform row 显示 Not configured |
| Token 过期，刷新失败 | `quotas: []`，停止探测 | Token expired 提示 |
| 探测请求网络超时 | 保留上次 quota 数据，下次重试 | 数据正常显示（可能略旧） |
| 探测返回 401 | `quotas: []`，停止探测直到文件更新 | Token expired 提示 |
| JWT decode 失败（格式异常） | `codex: null`，记录错误日志 | Not configured |

---

## 不在本次范围内

- Codex CLI 的 OAuth 登录流程（用户自行运行 `codex login`）
- 绝对用量数字（OpenAI 未提供独立查询端点）
- 多账户 / 多 workspace 支持
- Codex 的 session 级别追踪
