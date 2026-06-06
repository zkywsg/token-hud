# Codex API Auth Split

## 背景

Codex 平台此前只有本地 CLI 登录态入口：`codex login`、打开 `~/.codex`、删除 `~/.codex/auth.json`。用户反馈“Codex 的 API 认证相关功能用不了”，根因是 UI 没有把 Codex CLI 本地认证和 OpenAI Admin/API extras 分开。

## 决策

- Codex 主数据源仍然是本地：
  - `~/.codex/auth.json` 用于 email、plan、token 过期状态。
  - `~/.codex/sessions` JSONL 用于 token 和 rate-limit 数据。
- OpenAI Admin/API key 只做可选 extras：
  - 独立保存到 Keychain account `codexOpenAIAdminKey`。
  - 独立重置，不影响 `~/.codex/auth.json`。
  - 只在刷新 Codex 时尝试查询 OpenAI organization Costs。
- Admin/API extras 失败不覆盖本地 Codex 数据：
  - 401/403 只代表 extras 权限不足。
  - 本地 sessions 仍然是有效显示来源。

## 改动

- `ProviderResetAction` 增加 `adminAPIKey`。
- `ProviderCredentialSnapshot` 增加 `codexAdminKey`、`maskedCodexAdminKey` 和 `hasCodexAdminKey`。
- `KeychainHelper` 增加 Codex Admin/API extras key 的保存、读取、存在性检查和删除。
- Settings Codex 认证面板拆成：
  - `Codex 本地登录`
  - `OpenAI Admin / API extras`
- `CodexFetcher` 在本地数据之外，可选查询 OpenAI organization Costs，并在成功时追加 `costSpent` quota。

## 注意

- 不要把 Codex CLI token 复用成 OpenAI Admin API token。
- 不要把普通 OpenAI API key 描述成一定能查 Codex 账单。
- 如果后续要展示 extras 错误详情，应新增独立 extras status，不要用 `Service.error` 覆盖本地 Codex `ready` 状态。
