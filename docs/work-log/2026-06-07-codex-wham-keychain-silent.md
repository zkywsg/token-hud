# Codex Wham Usage And Silent Keychain Reads

## Background

Codex settings showed local auth as configured but displayed `Plan: Unknown` and `暂无数据`. Settings and app startup could still trigger repeated macOS Keychain password prompts.

## Findings

- Codex plan is stored in the JWT claim `https://api.openai.com/auth.chatgpt_plan_type`, not in `auth.chatgpt_plan_type`.
- Local `~/.codex/sessions/YYYY/MM` can be empty even when the account has active Codex quota.
- `GET https://chatgpt.com/backend-api/wham/usage` works for the current Codex login and returns:
  - `plan_type`
  - `rate_limit.primary_window`
  - `rate_limit.secondary_window`
  - `credits`
- `GET https://chatgpt.com/backend-api/codex/usage` can return 403 and should not be the only implementation path.
- Repeated Keychain prompts were still possible because background fetchers read secret data on startup/timers.

## Decision

- Codex fetch now prefers `wham/usage` via the existing Codex CLI access token, and falls back to local JSONL scanning.
- `wham/usage` success must not be overwritten by `noLocalSessions` when local session files are absent.
- Background and timer refreshes use silent Keychain reads with `LAContext.interactionNotAllowed`.
- Metadata checks such as `hasAPIKey` are used before reading secret data.
- User-initiated refreshes can still allow Keychain interaction because the user explicitly requested an operation requiring a secret.

## Notes

- Do not move Codex CLI auth into token-hud Keychain.
- Do not use OpenAI Admin/API extras key for basic Codex subscription quota; it is only an optional cost/usage extras key.
- If `wham/usage` returns 401, show token expired and ask the user to run `codex login`.
