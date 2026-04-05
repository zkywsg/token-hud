# Codex OAuth Subscription Query Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add OpenAI Codex CLI quota and subscription display to token_hud by reading `~/.codex/auth.json` in the token-state daemon and exposing the data via state.json.

**Architecture:** The token-state daemon gains a new `src/providers/codex.ts` module that reads the Codex CLI auth file on every sync interval, decodes the JWT locally for plan/email, refreshes the access token if expired, then probes `GET /models` to capture rate-limit headers. The result is written as a `"codex"` service entry in `state.json` using the existing schema. The macOS App gets a read-only Codex row in Settings that decodes the same JWT locally to display status.

**Tech Stack:** TypeScript (token-state daemon, Node 20+, ES modules, vitest), Swift/SwiftUI (macOS App)

---

## File Map

### Daemon (`/Users/lauzanhing/Desktop/token-state`)

| Action | Path | Responsibility |
|--------|------|----------------|
| Create | `src/providers/codex.ts` | JWT decode, token refresh, quota probe — all Codex data logic |
| Create | `tests/providers/codex.test.ts` | Unit tests for all exported functions |
| Modify | `src/config.ts` lines 6–9 | Add `codex?: Record<string, never>` to services |
| Modify | `bin/daemon.ts` | Import Codex provider, pass `manager` to `syncAll`, add Codex sync block |

### macOS App (`/Users/lauzanhing/Desktop/token_hud`)

| Action | Path | Responsibility |
|--------|------|----------------|
| Modify | `token_hud/Settings/PlatformRowView.swift` | Add `codexLocalAuth` credential type, `CodexAuthStatus` enum, Codex row UI, JWT decode helper |

---

## Task 1 — Codex Provider: Pure Functions

**Files:**
- Create: `src/providers/codex.ts`
- Create: `tests/providers/codex.test.ts`

- [ ] **Step 1: Write failing tests for `decodeJwt` and `parseRateLimitHeaders`**

Create `tests/providers/codex.test.ts`:

```typescript
import { describe, it, expect } from 'vitest'
import { decodeJwt, parseRateLimitHeaders } from '../../src/providers/codex.js'

// Helper: build a minimal 3-part JWT with a given payload
function makeJwt(payload: object): string {
  const header = Buffer.from(JSON.stringify({ alg: 'RS256', typ: 'JWT' })).toString('base64url')
  const body = Buffer.from(JSON.stringify(payload)).toString('base64url')
  return `${header}.${body}.fakesignature`
}

describe('decodeJwt', () => {
  it('extracts planType from nested auth claim', () => {
    const token = makeJwt({
      email: 'user@example.com',
      exp: 9_999_999_999,
      auth: { chatgpt_plan_type: 'pro' },
    })
    const result = decodeJwt(token)
    expect(result.planType).toBe('pro')
    expect(result.email).toBe('user@example.com')
    expect(result.exp).toBe(9_999_999_999)
  })

  it('defaults planType to "unknown" when auth claim is absent', () => {
    const token = makeJwt({ email: 'x@y.com', exp: 1 })
    const result = decodeJwt(token)
    expect(result.planType).toBe('unknown')
    expect(result.email).toBe('x@y.com')
  })

  it('defaults email to empty string when absent', () => {
    const token = makeJwt({ exp: 1, auth: { chatgpt_plan_type: 'free' } })
    const result = decodeJwt(token)
    expect(result.email).toBe('')
  })

  it('throws on token with wrong number of segments', () => {
    expect(() => decodeJwt('only.two')).toThrow('Invalid JWT format')
    expect(() => decodeJwt('one')).toThrow('Invalid JWT format')
  })
})

describe('parseRateLimitHeaders', () => {
  it('returns parsed quota when all three headers are present', () => {
    const headers = new Headers({
      'x-codex-primary-used-percent': '43',
      'x-codex-primary-window-minutes': '300',
      'x-codex-primary-reset-at': '2026-04-05T18:00:00Z',
    })
    expect(parseRateLimitHeaders(headers)).toEqual({
      usedPercent: 43,
      windowMinutes: 300,
      resetsAt: '2026-04-05T18:00:00Z',
    })
  })

  it('returns null when any header is missing', () => {
    const partial = new Headers({
      'x-codex-primary-used-percent': '50',
      'x-codex-primary-window-minutes': '300',
      // resetsAt missing
    })
    expect(parseRateLimitHeaders(partial)).toBeNull()
    expect(parseRateLimitHeaders(new Headers())).toBeNull()
  })
})
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd /Users/lauzanhing/Desktop/token-state
npx vitest run tests/providers/codex.test.ts
```

Expected: `Error: Cannot find module '../../src/providers/codex.js'`

- [ ] **Step 3: Create `src/providers/codex.ts` with the pure functions**

```typescript
// src/providers/codex.ts
import { readFile, writeFile } from 'node:fs/promises'
import { resolve } from 'node:path'
import { homedir } from 'node:os'

// ── Constants ─────────────────────────────────────────────────────────────────

const AUTH_FILE_PATH = resolve(homedir(), '.codex', 'auth.json')
const CODEX_API_BASE = 'https://chatgpt.com/backend-api/codex'
const OAUTH_TOKEN_URL = 'https://auth.openai.com/oauth/token'
const CODEX_CLIENT_ID = 'app_EMoamEEZ73f0CkXaXp7hrann'

// ── Public types ──────────────────────────────────────────────────────────────

export interface CodexJwtClaims {
  /** chatgpt_plan_type from the nested "auth" JWT claim */
  planType: string
  email: string
  /** Unix timestamp (seconds) — when the token expires */
  exp: number
}

export interface CodexRateLimits {
  /** 0–100, from x-codex-primary-used-percent header */
  usedPercent: number
  /** Quota window length in minutes, from x-codex-primary-window-minutes */
  windowMinutes: number
  /** ISO 8601 reset timestamp, from x-codex-primary-reset-at */
  resetsAt: string
}

export interface CodexUsageResult {
  claims: CodexJwtClaims
  /** null when the probe response lacks rate-limit headers or network error (non-401) */
  rateLimits: CodexRateLimits | null
}

// ── Internal types ────────────────────────────────────────────────────────────

interface CodexTokens {
  id_token: string
  access_token: string
  refresh_token: string
  account_id?: string
}

interface CodexAuthFile {
  auth_mode?: string
  tokens: CodexTokens
  last_refresh?: string
}

// ── Exported pure functions (also tested directly) ───────────────────────────

/**
 * Decode the payload segment of a JWT without verifying the signature.
 * Extracts planType, email, and exp from the Codex CLI id_token claims.
 */
export function decodeJwt(token: string): CodexJwtClaims {
  const parts = token.split('.')
  if (parts.length !== 3) throw new Error('Invalid JWT format')

  // base64url → base64 (replace URL-safe chars, no padding needed for Buffer)
  const base64 = (parts[1] ?? '').replace(/-/g, '+').replace(/_/g, '/')
  const json = Buffer.from(base64, 'base64').toString('utf8')
  const claims = JSON.parse(json) as Record<string, unknown>

  const auth = claims['auth'] as Record<string, unknown> | undefined
  return {
    planType: (auth?.['chatgpt_plan_type'] as string | undefined) ?? 'unknown',
    email: (claims['email'] as string | undefined) ?? '',
    exp: (claims['exp'] as number | undefined) ?? 0,
  }
}

/**
 * Parse Codex rate-limit headers from a fetch Response.
 * Returns null if any of the three required headers are missing.
 */
export function parseRateLimitHeaders(headers: Headers): CodexRateLimits | null {
  const usedPct = headers.get('x-codex-primary-used-percent')
  const windowMin = headers.get('x-codex-primary-window-minutes')
  const resetsAt = headers.get('x-codex-primary-reset-at')
  if (!usedPct || !windowMin || !resetsAt) return null
  return {
    usedPercent: Number(usedPct),
    windowMinutes: Number(windowMin),
    resetsAt,
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
cd /Users/lauzanhing/Desktop/token-state
npx vitest run tests/providers/codex.test.ts
```

Expected: all 7 tests pass.

- [ ] **Step 5: Commit**

```bash
cd /Users/lauzanhing/Desktop/token-state
git add src/providers/codex.ts tests/providers/codex.test.ts
git commit -m "feat: add Codex provider — pure JWT decode and header parsing"
```

---

## Task 2 — Codex Provider: `readCodexUsage`

**Files:**
- Modify: `src/providers/codex.ts` (append internal helpers + main export)
- Modify: `tests/providers/codex.test.ts` (append integration-level tests)

- [ ] **Step 1: Add `readCodexUsage` tests to `tests/providers/codex.test.ts`**

Append to the existing test file (after the last `describe` block):

```typescript
import { vi, beforeEach } from 'vitest'
import { readFile, writeFile } from 'node:fs/promises'

vi.mock('node:fs/promises')

describe('readCodexUsage', () => {
  beforeEach(() => {
    vi.resetAllMocks()
    vi.stubGlobal('fetch', vi.fn())
  })

  it('returns usage when token is valid and probe succeeds', async () => {
    const futureExp = Math.floor(Date.now() / 1000) + 3600
    const idToken = makeJwt({ email: 'user@example.com', exp: futureExp, auth: { chatgpt_plan_type: 'pro' } })
    const accessToken = makeJwt({ exp: futureExp })

    vi.mocked(readFile).mockResolvedValueOnce(
      JSON.stringify({ tokens: { id_token: idToken, access_token: accessToken, refresh_token: 'rtoken' } })
    )
    vi.mocked(fetch).mockResolvedValueOnce(
      new Response('[]', {
        status: 200,
        headers: {
          'x-codex-primary-used-percent': '43',
          'x-codex-primary-window-minutes': '300',
          'x-codex-primary-reset-at': '2026-04-05T18:00:00Z',
        },
      })
    )

    const result = await readCodexUsage()
    expect(result.claims.planType).toBe('pro')
    expect(result.claims.email).toBe('user@example.com')
    expect(result.rateLimits).toEqual({ usedPercent: 43, windowMinutes: 300, resetsAt: '2026-04-05T18:00:00Z' })
    expect(vi.mocked(writeFile)).not.toHaveBeenCalled()
  })

  it('refreshes token when access_token is expired and writes auth file', async () => {
    const pastExp = Math.floor(Date.now() / 1000) - 100
    const futureExp = Math.floor(Date.now() / 1000) + 3600
    const oldIdToken = makeJwt({ email: 'u@v.com', exp: pastExp, auth: { chatgpt_plan_type: 'plus' } })
    const oldAccessToken = makeJwt({ exp: pastExp })
    const newAccessToken = makeJwt({ exp: futureExp })
    const newIdToken = makeJwt({ email: 'u@v.com', exp: futureExp, auth: { chatgpt_plan_type: 'plus' } })

    vi.mocked(readFile).mockResolvedValueOnce(
      JSON.stringify({ tokens: { id_token: oldIdToken, access_token: oldAccessToken, refresh_token: 'rtoken' } })
    )
    vi.mocked(fetch)
      // First call: token refresh endpoint
      .mockResolvedValueOnce(new Response(
        JSON.stringify({ access_token: newAccessToken, id_token: newIdToken, refresh_token: 'new-rtoken' }),
        { status: 200, headers: { 'Content-Type': 'application/json' } }
      ))
      // Second call: /models probe
      .mockResolvedValueOnce(new Response('[]', {
        status: 200,
        headers: {
          'x-codex-primary-used-percent': '20',
          'x-codex-primary-window-minutes': '300',
          'x-codex-primary-reset-at': '2026-04-05T20:00:00Z',
        },
      }))

    const result = await readCodexUsage()
    expect(vi.mocked(fetch)).toHaveBeenCalledTimes(2)
    expect(vi.mocked(writeFile)).toHaveBeenCalledOnce()  // wrote refreshed tokens
    expect(result.rateLimits?.usedPercent).toBe(20)
  })

  it('throws when auth file does not exist', async () => {
    vi.mocked(readFile).mockRejectedValueOnce(
      Object.assign(new Error('ENOENT: no such file'), { code: 'ENOENT' })
    )
    await expect(readCodexUsage()).rejects.toThrow('ENOENT')
  })

  it('throws when probe returns 401', async () => {
    const futureExp = Math.floor(Date.now() / 1000) + 3600
    const idToken = makeJwt({ email: 'a@b.com', exp: futureExp, auth: { chatgpt_plan_type: 'free' } })
    const accessToken = makeJwt({ exp: futureExp })
    vi.mocked(readFile).mockResolvedValueOnce(
      JSON.stringify({ tokens: { id_token: idToken, access_token: accessToken, refresh_token: 'r' } })
    )
    vi.mocked(fetch).mockResolvedValueOnce(new Response('Unauthorized', { status: 401 }))
    await expect(readCodexUsage()).rejects.toThrow('Codex: unauthorized (401)')
  })

  it('returns null rateLimits when probe response has no rate-limit headers', async () => {
    const futureExp = Math.floor(Date.now() / 1000) + 3600
    const idToken = makeJwt({ email: 'a@b.com', exp: futureExp, auth: { chatgpt_plan_type: 'free' } })
    const accessToken = makeJwt({ exp: futureExp })
    vi.mocked(readFile).mockResolvedValueOnce(
      JSON.stringify({ tokens: { id_token: idToken, access_token: accessToken, refresh_token: 'r' } })
    )
    vi.mocked(fetch).mockResolvedValueOnce(new Response('[]', { status: 200 }))

    const result = await readCodexUsage()
    expect(result.rateLimits).toBeNull()
  })
})
```

- [ ] **Step 2: Run tests to verify the new tests fail**

```bash
cd /Users/lauzanhing/Desktop/token-state
npx vitest run tests/providers/codex.test.ts
```

Expected: `readCodexUsage` tests fail with `TypeError: readCodexUsage is not a function`

- [ ] **Step 3: Append the internal helpers and `readCodexUsage` to `src/providers/codex.ts`**

Append after the `parseRateLimitHeaders` function:

```typescript
// ── Internal helpers ──────────────────────────────────────────────────────────

async function readAuthFile(): Promise<CodexAuthFile> {
  const raw = await readFile(AUTH_FILE_PATH, 'utf8')
  return JSON.parse(raw) as CodexAuthFile
}

/** Returns true if the token expires within 60 seconds (or is already expired). */
function isTokenExpired(accessToken: string): boolean {
  try {
    const { exp } = decodeJwt(accessToken)
    return Date.now() / 1000 >= exp - 60
  } catch {
    return true
  }
}

async function refreshAccessToken(tokens: CodexTokens): Promise<CodexTokens> {
  const res = await fetch(OAUTH_TOKEN_URL, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      grant_type: 'refresh_token',
      client_id: CODEX_CLIENT_ID,
      refresh_token: tokens.refresh_token,
    }),
  })
  if (!res.ok) throw new Error(`Codex: token refresh failed (${res.status})`)
  const fresh = await res.json() as CodexTokens
  return { ...tokens, ...fresh }
}

async function probeQuota(accessToken: string): Promise<CodexRateLimits | null> {
  const res = await fetch(`${CODEX_API_BASE}/models`, {
    headers: { Authorization: `Bearer ${accessToken}` },
  })
  if (res.status === 401) throw new Error('Codex: unauthorized (401)')
  if (!res.ok) return null  // network/server error — keep last known data
  return parseRateLimitHeaders(res.headers)
}

// ── Main export ───────────────────────────────────────────────────────────────

/**
 * Read Codex CLI auth from ~/.codex/auth.json, refresh the access token if
 * expired, probe /models for rate-limit headers, and return the combined result.
 *
 * Throws if the auth file is missing or the probe returns 401.
 */
export async function readCodexUsage(): Promise<CodexUsageResult> {
  const authFile = await readAuthFile()
  let { tokens } = authFile

  if (isTokenExpired(tokens.access_token)) {
    tokens = await refreshAccessToken(tokens)
    const updated: CodexAuthFile = { ...authFile, tokens, last_refresh: new Date().toISOString() }
    await writeFile(AUTH_FILE_PATH, JSON.stringify(updated, null, 2), 'utf8')
  }

  const claims = decodeJwt(tokens.id_token)
  const rateLimits = await probeQuota(tokens.access_token)

  return { claims, rateLimits }
}
```

- [ ] **Step 4: Run all provider tests**

```bash
cd /Users/lauzanhing/Desktop/token-state
npx vitest run tests/providers/codex.test.ts
```

Expected: all 12 tests pass.

- [ ] **Step 5: Run the full test suite to catch regressions**

```bash
cd /Users/lauzanhing/Desktop/token-state
npx vitest run
```

Expected: all tests pass.

- [ ] **Step 6: Commit**

```bash
cd /Users/lauzanhing/Desktop/token-state
git add src/providers/codex.ts tests/providers/codex.test.ts
git commit -m "feat: add readCodexUsage — auth file read, token refresh, quota probe"
```

---

## Task 3 — Wire Codex into the Daemon

**Files:**
- Modify: `src/config.ts`
- Modify: `bin/daemon.ts`

- [ ] **Step 1: Add `codex` to `DaemonConfig` in `src/config.ts`**

Replace the `services` block (current lines 6–9):

```typescript
// src/config.ts
export interface DaemonConfig {
  stateFile?: string        // default: ~/.token-hud/state.json
  intervalSeconds?: number  // default: 60
  services: {
    claudeMax?: { accessToken: string }
    claudePro?: { sessionKey: string }
    openai?: { apiKey: string }
    /** Presence enables Codex — no credentials needed, reads ~/.codex/auth.json */
    codex?: Record<string, never>
  }
}
```

- [ ] **Step 2: Run tests to confirm no regressions**

```bash
cd /Users/lauzanhing/Desktop/token-state
npx vitest run
```

Expected: all tests pass.

- [ ] **Step 3: Update `bin/daemon.ts` — imports and `syncAll` signature**

Replace the import block at the top of `bin/daemon.ts` (lines 1–10):

```typescript
import { readFile } from 'node:fs/promises'
import { resolve } from 'node:path'
import { homedir } from 'node:os'
import { TokenTracker } from '../src/tracker.js'
import { StateManager } from '../src/state-manager.js'
import { readClaudeMaxUsage } from '../src/providers/claude-max.js'
import { readClaudeProUsage } from '../src/providers/claude-pro.js'
import { readOpenAIUsage, readOpenAIBalance } from '../src/providers/openai.js'
import { readCodexUsage } from '../src/providers/codex.js'
import type { DaemonConfig } from '../src/config.js'
import type { Quota } from '../src/schema.js'
```

Replace the `syncAll` signature (line 20):

```typescript
async function syncAll(tracker: TokenTracker, manager: StateManager, config: DaemonConfig): Promise<void> {
```

- [ ] **Step 4: Add the Codex sync block inside `syncAll` in `bin/daemon.ts`**

Append inside `syncAll`, after the `if (config.services.openai)` block and before `await tracker.flush()`:

```typescript
  if (config.services.codex !== undefined) {
    try {
      const result = await readCodexUsage()
      const quota: Quota = result.rateLimits
        ? {
            type: 'requests',
            total: 100,
            used: result.rateLimits.usedPercent,
            unit: '%',
            resetsAt: result.rateLimits.resetsAt,
          }
        : { type: 'requests', total: 100, used: 0, unit: '%' }
      // Use manager.addService directly — overwrites on every sync so resetsAt stays fresh.
      // Codex does not use TokenTracker's consumption-counting features.
      manager.addService('codex', { label: 'Codex', quotas: [quota], currentSession: null })
    } catch (e) {
      errors.push(`codex: ${String(e)}`)
    }
  }
```

- [ ] **Step 5: Update `syncAll` call sites in `main()` to pass `manager`**

Replace both call sites in `main()` (the immediate call and the setInterval callback):

```typescript
  await syncAll(tracker, manager, config)
  setInterval(() => { void syncAll(tracker, manager, config) }, intervalMs)
```

- [ ] **Step 6: Smoke-test manually**

Add `"codex": {}` to `~/.token-hud/config.json` under `services`:

```json
{
  "stateFile": "~/.token-hud/state.json",
  "intervalSeconds": 60,
  "services": {
    "codex": {}
  }
}
```

Run the daemon and verify `~/.token-hud/state.json` contains a `"codex"` service entry:

```bash
cd /Users/lauzanhing/Desktop/token-state
npx tsx bin/daemon.ts
# In another terminal:
cat ~/.token-hud/state.json | grep -A 10 '"codex"'
```

Expected: either a quota with `"type": "requests"` or an error log if `~/.codex/auth.json` doesn't exist.

- [ ] **Step 7: Commit**

```bash
cd /Users/lauzanhing/Desktop/token-state
git add src/config.ts bin/daemon.ts
git commit -m "feat: wire Codex provider into daemon sync loop"
```

---

## Task 4 — macOS App: Codex Settings Row

**Files:**
- Modify: `token_hud/Settings/PlatformRowView.swift`

- [ ] **Step 1: Add `codexLocalAuth` credential type, `.codex` platform, and `CodexAuthStatus` enum**

In `PlatformRowView.swift`, replace the `PlatformConfig` struct block (lines 6–17):

```swift
struct PlatformConfig: Identifiable {
    let id: String           // matches StateFile.services key, e.g. "claude", "openai", "codex"
    let displayName: String
    let credentialType: CredentialType

    enum CredentialType { case sessionKey, apiKey, codexLocalAuth }

    static let all: [PlatformConfig] = [
        PlatformConfig(id: "claude", displayName: "Claude", credentialType: .sessionKey),
        PlatformConfig(id: "openai", displayName: "OpenAI", credentialType: .apiKey),
        PlatformConfig(id: "codex", displayName: "Codex", credentialType: .codexLocalAuth),
    ]
}

enum CodexAuthStatus: Equatable {
    case configured(email: String, plan: String)
    case expired
    case notConfigured
}
```

- [ ] **Step 2: Add Codex state and badge helpers to `PlatformRowView`**

Inside the `PlatformRowView` struct, after `private let extractor = SessionKeyExtractor()` (line 32), add:

```swift
    // Codex-specific
    @State private var codexStatus: CodexAuthStatus = .notConfigured

    // MARK: - Badge helpers (used by rowHeader for all platforms)

    private var configBadgeColor: Color {
        switch platform.credentialType {
        case .sessionKey, .apiKey:
            return storedKey != nil ? .green : .orange
        case .codexLocalAuth:
            switch codexStatus {
            case .configured:    return .green
            case .expired:       return .yellow
            case .notConfigured: return .orange
            }
        }
    }

    private var configBadgeText: String {
        switch platform.credentialType {
        case .sessionKey, .apiKey:
            return storedKey != nil ? "Configured" : "Not configured"
        case .codexLocalAuth:
            switch codexStatus {
            case .configured:    return "Configured"
            case .expired:       return "Token expired"
            case .notConfigured: return "Not configured"
            }
        }
    }
```

- [ ] **Step 3: Update `rowHeader` to use the new badge helpers**

In `rowHeader`, replace the two hard-coded lines (inside the `HStack`):

```swift
                Circle()
                    .fill(configBadgeColor)
                    .frame(width: 7, height: 7)
                Text(configBadgeText)
                    .font(.caption)
                    .foregroundColor(configBadgeColor == .green ? .green : .secondary)
```

- [ ] **Step 4: Add `codexCredentials` view and update `credentialsSection` switch**

Replace `credentialsSection` (lines 95–102):

```swift
    @ViewBuilder private var credentialsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            switch platform.credentialType {
            case .sessionKey:     claudeCredentials
            case .apiKey:         openAICredentials
            case .codexLocalAuth: codexCredentials
            }
        }
    }

    @ViewBuilder private var codexCredentials: some View {
        switch codexStatus {
        case .configured(let email, let plan):
            HStack {
                Text("Email").font(.caption).foregroundColor(.secondary)
                Spacer()
                Text(email).font(.caption.monospaced()).foregroundColor(.secondary)
            }
            HStack {
                Text("Plan").font(.caption).foregroundColor(.secondary)
                Spacer()
                Text(plan.capitalized)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
            }
        case .expired:
            Label("Token expired", systemImage: "exclamationmark.triangle")
                .font(.caption).foregroundColor(.yellow)
            Text("Run `codex login` in Terminal to refresh.")
                .font(.caption).foregroundColor(.secondary)
        case .notConfigured:
            Label("Not configured", systemImage: "info.circle")
                .font(.caption).foregroundColor(.secondary)
            Text("Run `codex login` in Terminal to authenticate.")
                .font(.caption).foregroundColor(.secondary)
        }
    }
```

- [ ] **Step 5: Add `loadCodexStatus()` and the JWT decode helper, update `loadKey()`**

Append inside `PlatformRowView`, after `extractClaudeKey()`:

```swift
    private func loadCodexStatus() {
        let authPath = (NSHomeDirectory() as NSString).appendingPathComponent(".codex/auth.json")
        guard
            let data = FileManager.default.contents(atPath: authPath),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let tokens = json["tokens"] as? [String: Any],
            let idToken = tokens["id_token"] as? String,
            let accessToken = tokens["access_token"] as? String,
            let payload = decodeCodexJwtPayload(idToken)
        else {
            codexStatus = .notConfigured
            return
        }

        // Check expiry using access_token (same exp as id_token for Codex)
        if let accessPayload = decodeCodexJwtPayload(accessToken),
           let exp = accessPayload["exp"] as? TimeInterval,
           Date().timeIntervalSince1970 >= exp - 60 {
            codexStatus = .expired
            return
        }

        let auth = payload["auth"] as? [String: Any]
        let plan = (auth?["chatgpt_plan_type"] as? String) ?? "unknown"
        let email = (payload["email"] as? String) ?? ""
        codexStatus = .configured(email: email, plan: plan)
    }

    /// Decode the payload segment of a JWT. Returns nil on any parse failure.
    private func decodeCodexJwtPayload(_ token: String) -> [String: Any]? {
        let parts = token.components(separatedBy: ".")
        guard parts.count == 3 else { return nil }
        var b64 = parts[1]
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = b64.count % 4
        if remainder > 0 { b64 += String(repeating: "=", count: 4 - remainder) }
        guard
            let data = Data(base64Encoded: b64),
            let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return obj
    }
```

Replace `loadKey()` (lines 237–242):

```swift
    private func loadKey() async {
        switch platform.credentialType {
        case .sessionKey:     storedKey = await extractor.loadFromKeychain()
        case .apiKey:         storedKey = KeychainHelper.loadOpenAIKey()
        case .codexLocalAuth: loadCodexStatus()
        }
    }
```

- [ ] **Step 6: Build in Xcode and verify visually**

Open `/Users/lauzanhing/Desktop/token_hud/token_hud.xcodeproj` in Xcode, build (⌘B), and confirm:

- Codex appears as a third platform row in Settings → Platforms
- Row shows correct badge: green (if `~/.codex/auth.json` exists and token is valid), yellow (expired), or orange (not configured)
- Expanded credentials section shows email + plan, or appropriate message
- Claude and OpenAI rows are unchanged

- [ ] **Step 7: Commit**

```bash
cd /Users/lauzanhing/Desktop/token_hud
git add token_hud/Settings/PlatformRowView.swift
git commit -m "feat: add Codex platform row to Settings — read-only JWT auth status"
```

---

## Self-Review

**Spec coverage check:**

| Spec requirement | Task |
|-----------------|------|
| Daemon reads `~/.codex/auth.json` | Task 1 (`readAuthFile`) |
| JWT decode for plan/email | Task 1 (`decodeJwt`) |
| Token refresh via POST `/oauth/token` | Task 2 (`refreshAccessToken`) |
| Probe `GET /models`, parse rate-limit headers | Task 2 (`probeQuota`, `parseRateLimitHeaders`) |
| Write as `"codex"` service in state.json, `requests` type, `total:100`, `used:<pct>` | Task 3 |
| `codex: {}` opt-in in config | Task 3 |
| `PlatformConfig.all` gains `.codex` | Task 4 Step 1 |
| Settings row: configured/expired/not-configured states | Task 4 Steps 2–5 |
| `KeychainHelper` unchanged | Confirmed — not touched |
| `StateModel.swift` unchanged | Confirmed — not touched |
| Error handling: auth.json missing → throws (caught by daemon, logged) | Task 2 test + Task 3 try/catch |
| Error handling: 401 → throws (caught by daemon, logged) | Task 2 test + Task 3 try/catch |
| Error handling: non-401 error → null rateLimits | Task 2 (`probeQuota` returns null) |
