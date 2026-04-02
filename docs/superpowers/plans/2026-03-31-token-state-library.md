# token-state Library Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a TypeScript library that reads AI service quota data from existing sources (Claude logs, OAuth APIs, OpenAI API) and writes normalized state to `~/.token-hud/state.json` for consumption by token_hud and other tools.

**Architecture:** A `TokenTracker` class manages in-memory quota state and persists it atomically to a JSON file. Provider modules read from platform-specific sources (JSONL logs, HTTP APIs) and feed data into the tracker. A daemon CLI runs providers on a configurable interval.

**Tech Stack:** TypeScript 5.4+, Node.js 18+, Vitest, tsup, tsx (zero runtime dependencies in core)

---

## File Map

```
token-state/
├── src/
│   ├── schema.ts           # TypeScript types matching state.json
│   ├── writer.ts           # Atomic JSON file write + path resolution
│   ├── state-manager.ts    # In-memory state + debounced flush
│   ├── tracker.ts          # TokenTracker: addService / consume / resetQuota
│   ├── session.ts          # Session: per-conversation tracking
│   ├── providers/
│   │   ├── claude-max.ts   # Claude OAuth API + JSONL log reader
│   │   ├── claude-pro.ts   # claude.ai internal API via sessionKey (experimental)
│   │   └── openai.ts       # OpenAI Usage API + Billing API
│   └── plugins/
│       ├── openai.ts       # wrapOpenAI — intercepts chat.completions.create
│       └── anthropic.ts    # wrapAnthropic — intercepts messages.create
├── bin/
│   └── daemon.ts           # CLI: reads config, runs providers on interval
├── tests/
│   ├── writer.test.ts
│   ├── state-manager.test.ts
│   ├── tracker.test.ts
│   ├── session.test.ts
│   ├── providers/
│   │   ├── claude-max.test.ts
│   │   ├── claude-pro.test.ts
│   │   └── openai.test.ts
│   └── plugins/
│       ├── openai.test.ts
│       └── anthropic.test.ts
├── package.json
├── tsconfig.json
└── .gitignore
```

---

## Task 1: Project Initialization

**Files:**
- Create: `package.json`
- Create: `tsconfig.json`
- Create: `.gitignore`

- [ ] **Step 1: Create package.json**

```json
{
  "name": "token-state",
  "version": "0.1.0",
  "description": "Track and display AI service token quotas",
  "type": "module",
  "main": "./dist/index.js",
  "types": "./dist/index.d.ts",
  "exports": {
    ".": "./dist/index.js",
    "./openai": "./dist/plugins/openai.js",
    "./anthropic": "./dist/plugins/anthropic.js"
  },
  "scripts": {
    "build": "tsup",
    "dev": "tsx watch src/index.ts",
    "test": "vitest run",
    "test:watch": "vitest",
    "daemon": "tsx bin/daemon.ts"
  },
  "devDependencies": {
    "typescript": "^5.4.5",
    "vitest": "^1.6.0",
    "tsx": "^4.7.3",
    "tsup": "^8.0.2",
    "@types/node": "^20.14.0"
  }
}
```

- [ ] **Step 2: Create tsconfig.json**

```json
{
  "compilerOptions": {
    "target": "ES2022",
    "module": "NodeNext",
    "moduleResolution": "NodeNext",
    "outDir": "dist",
    "rootDir": "src",
    "strict": true,
    "declaration": true,
    "declarationMap": true,
    "sourceMap": true,
    "esModuleInterop": true
  },
  "include": ["src"],
  "exclude": ["node_modules", "dist"]
}
```

- [ ] **Step 3: Create .gitignore**

```
node_modules/
dist/
*.js.map
.DS_Store
```

- [ ] **Step 4: Install dependencies**

```bash
npm install
```

Expected: `node_modules/` created, no errors.

- [ ] **Step 5: Create src/index.ts (empty barrel for now)**

```typescript
export { TokenTracker } from './tracker.js'
export { Session } from './session.js'
export type { StateFile, Service, Quota, QuotaType } from './schema.js'
```

- [ ] **Step 6: Commit**

```bash
git init
git add .
git commit -m "chore: initialize token-state project"
```

---

## Task 2: Schema Types

**Files:**
- Create: `src/schema.ts`

- [ ] **Step 1: Write schema.ts**

```typescript
export type QuotaType = 'time' | 'tokens' | 'money' | 'requests'

export interface Quota {
  type: QuotaType
  total: number
  used: number
  unit: string
  resetsAt?: string // ISO 8601
}

export interface SessionSnapshot {
  id: string
  startedAt: string // ISO 8601
  tokens?: number
  time?: number
  money?: number
  requests?: number
}

export interface Service {
  label: string
  quotas: Quota[]
  currentSession: SessionSnapshot | null
}

export interface StateFile {
  version: 1
  updatedAt: string // ISO 8601
  services: Record<string, Service>
}
```

No tests needed — TypeScript compiler validates types at build time.

- [ ] **Step 2: Verify types compile**

```bash
npx tsc --noEmit
```

Expected: no errors.

- [ ] **Step 3: Commit**

```bash
git add src/schema.ts src/index.ts
git commit -m "feat: add state.json schema types"
```

---

## Task 3: Atomic Writer

**Files:**
- Create: `src/writer.ts`
- Create: `tests/writer.test.ts`

- [ ] **Step 1: Write the failing tests**

```typescript
// tests/writer.test.ts
import { describe, it, expect, beforeEach, afterEach } from 'vitest'
import { mkdtemp, readFile, rm } from 'node:fs/promises'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { atomicWriteJson, resolvePath } from '../src/writer.js'

let tmpDir: string

beforeEach(async () => {
  tmpDir = await mkdtemp(join(tmpdir(), 'token-state-test-'))
})

afterEach(async () => {
  await rm(tmpDir, { recursive: true, force: true })
})

describe('resolvePath', () => {
  it('expands ~ to home directory', () => {
    const result = resolvePath('~/.token-hud/state.json')
    expect(result).not.toContain('~')
    expect(result).toContain('.token-hud/state.json')
  })

  it('leaves absolute paths unchanged', () => {
    const result = resolvePath('/absolute/path.json')
    expect(result).toBe('/absolute/path.json')
  })
})

describe('atomicWriteJson', () => {
  it('writes JSON to file', async () => {
    const filePath = join(tmpDir, 'state.json')
    await atomicWriteJson(filePath, { version: 1, data: 'test' })
    const content = await readFile(filePath, 'utf8')
    expect(JSON.parse(content)).toEqual({ version: 1, data: 'test' })
  })

  it('does not leave a .tmp file behind', async () => {
    const filePath = join(tmpDir, 'state.json')
    await atomicWriteJson(filePath, { ok: true })
    const { readdir } = await import('node:fs/promises')
    const files = await readdir(tmpDir)
    expect(files).not.toContain('state.json.tmp')
  })

  it('creates parent directories if they do not exist', async () => {
    const filePath = join(tmpDir, 'nested', 'dir', 'state.json')
    await atomicWriteJson(filePath, { nested: true })
    const content = await readFile(filePath, 'utf8')
    expect(JSON.parse(content)).toEqual({ nested: true })
  })
})
```

- [ ] **Step 2: Run tests — verify they fail**

```bash
npm test -- tests/writer.test.ts
```

Expected: FAIL — `atomicWriteJson` not found.

- [ ] **Step 3: Implement writer.ts**

```typescript
// src/writer.ts
import { writeFile, rename, mkdir } from 'node:fs/promises'
import { resolve, dirname } from 'node:path'
import { homedir } from 'node:os'

export function resolvePath(p: string): string {
  if (p.startsWith('~/')) return resolve(homedir(), p.slice(2))
  if (p === '~') return homedir()
  return resolve(p)
}

export async function atomicWriteJson(filePath: string, data: unknown): Promise<void> {
  const resolved = resolvePath(filePath)
  const tmp = resolved + '.tmp'
  await mkdir(dirname(resolved), { recursive: true })
  await writeFile(tmp, JSON.stringify(data, null, 2), 'utf8')
  await rename(tmp, resolved)
}
```

- [ ] **Step 4: Run tests — verify they pass**

```bash
npm test -- tests/writer.test.ts
```

Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add src/writer.ts tests/writer.test.ts
git commit -m "feat: atomic JSON writer with ~ path resolution"
```

---

## Task 4: StateManager

**Files:**
- Create: `src/state-manager.ts`
- Create: `tests/state-manager.test.ts`

- [ ] **Step 1: Write the failing tests**

```typescript
// tests/state-manager.test.ts
import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest'
import { mkdtemp, readFile, rm } from 'node:fs/promises'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { StateManager } from '../src/state-manager.js'
import type { Service } from '../src/schema.js'

let tmpDir: string

beforeEach(async () => {
  tmpDir = await mkdtemp(join(tmpdir(), 'token-state-test-'))
  vi.useFakeTimers()
})

afterEach(async () => {
  vi.useRealTimers()
  await rm(tmpDir, { recursive: true, force: true })
})

const makeService = (label: string): Service => ({
  label,
  quotas: [{ type: 'tokens', total: 1000, used: 0, unit: 'tokens' }],
  currentSession: null,
})

describe('StateManager', () => {
  it('starts with empty services', () => {
    const mgr = new StateManager(join(tmpDir, 'state.json'))
    expect(mgr.getState().services).toEqual({})
  })

  it('addService stores a service', () => {
    const mgr = new StateManager(join(tmpDir, 'state.json'))
    mgr.addService('claude', makeService('Claude Max'))
    expect(mgr.getState().services['claude']?.label).toBe('Claude Max')
  })

  it('updateService modifies an existing service', () => {
    const mgr = new StateManager(join(tmpDir, 'state.json'))
    mgr.addService('claude', makeService('Claude Max'))
    mgr.updateService('claude', s => ({
      ...s,
      quotas: [{ type: 'tokens', total: 1000, used: 500, unit: 'tokens' }],
    }))
    expect(mgr.getState().services['claude']?.quotas[0]?.used).toBe(500)
  })

  it('updateService throws for unknown service', () => {
    const mgr = new StateManager(join(tmpDir, 'state.json'))
    expect(() => mgr.updateService('unknown', s => s)).toThrow("Service 'unknown' not registered")
  })

  it('flush writes state.json to disk', async () => {
    const filePath = join(tmpDir, 'state.json')
    const mgr = new StateManager(filePath)
    mgr.addService('openai', makeService('OpenAI'))
    await mgr.flush()
    const raw = await readFile(filePath, 'utf8')
    const parsed = JSON.parse(raw)
    expect(parsed.version).toBe(1)
    expect(parsed.services.openai.label).toBe('OpenAI')
  })

  it('scheduleWrite debounces: multiple updates cause one flush', async () => {
    const filePath = join(tmpDir, 'state.json')
    const mgr = new StateManager(filePath)
    mgr.addService('claude', makeService('Claude'))
    mgr.addService('openai', makeService('OpenAI'))
    // Advance timers to trigger debounce
    await vi.runAllTimersAsync()
    const raw = await readFile(filePath, 'utf8')
    const parsed = JSON.parse(raw)
    expect(Object.keys(parsed.services)).toHaveLength(2)
  })
})
```

- [ ] **Step 2: Run tests — verify they fail**

```bash
npm test -- tests/state-manager.test.ts
```

Expected: FAIL — `StateManager` not found.

- [ ] **Step 3: Implement state-manager.ts**

```typescript
// src/state-manager.ts
import type { StateFile, Service } from './schema.js'
import { atomicWriteJson } from './writer.js'

export class StateManager {
  private state: StateFile
  private readonly filePath: string
  private writeTimer: ReturnType<typeof setTimeout> | null = null

  constructor(filePath: string = '~/.token-hud/state.json') {
    this.filePath = filePath
    this.state = { version: 1, updatedAt: new Date().toISOString(), services: {} }
  }

  getState(): Readonly<StateFile> {
    return this.state
  }

  addService(serviceId: string, service: Service): void {
    this.state = {
      ...this.state,
      updatedAt: new Date().toISOString(),
      services: { ...this.state.services, [serviceId]: service },
    }
    this.scheduleWrite()
  }

  updateService(serviceId: string, updater: (service: Service) => Service): void {
    const current = this.state.services[serviceId]
    if (!current) throw new Error(`Service '${serviceId}' not registered`)
    this.state = {
      ...this.state,
      updatedAt: new Date().toISOString(),
      services: { ...this.state.services, [serviceId]: updater(current) },
    }
    this.scheduleWrite()
  }

  private scheduleWrite(): void {
    if (this.writeTimer) clearTimeout(this.writeTimer)
    this.writeTimer = setTimeout(() => { void this.flush() }, 100)
  }

  async flush(): Promise<void> {
    if (this.writeTimer) {
      clearTimeout(this.writeTimer)
      this.writeTimer = null
    }
    await atomicWriteJson(this.filePath, this.state)
  }
}
```

- [ ] **Step 4: Run tests — verify they pass**

```bash
npm test -- tests/state-manager.test.ts
```

Expected: PASS (6 tests).

- [ ] **Step 5: Commit**

```bash
git add src/state-manager.ts tests/state-manager.test.ts
git commit -m "feat: StateManager with debounced atomic flush"
```

---

## Task 5: TokenTracker Core

**Files:**
- Create: `src/tracker.ts`
- Create: `tests/tracker.test.ts`

- [ ] **Step 1: Write the failing tests**

```typescript
// tests/tracker.test.ts
import { describe, it, expect, beforeEach, afterEach } from 'vitest'
import { mkdtemp, rm } from 'node:fs/promises'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { TokenTracker } from '../src/tracker.js'
import { StateManager } from '../src/state-manager.js'

let tmpDir: string
let tracker: TokenTracker
let manager: StateManager

beforeEach(async () => {
  tmpDir = await mkdtemp(join(tmpdir(), 'token-state-test-'))
  manager = new StateManager(join(tmpDir, 'state.json'))
  tracker = new TokenTracker(manager)
})

afterEach(async () => {
  await rm(tmpDir, { recursive: true, force: true })
})

describe('addService', () => {
  it('registers a service with zero used', () => {
    tracker.addService('claude', {
      label: 'Claude Max',
      quotas: [{ type: 'time', total: 18000, unit: 'seconds' }],
    })
    const state = manager.getState()
    expect(state.services['claude']?.quotas[0]?.used).toBe(0)
    expect(state.services['claude']?.currentSession).toBeNull()
  })
})

describe('consume', () => {
  beforeEach(() => {
    tracker.addService('claude', {
      label: 'Claude Max',
      quotas: [
        { type: 'tokens', total: 1_000_000, unit: 'tokens' },
        { type: 'time', total: 18000, unit: 'seconds' },
      ],
    })
  })

  it('increases used for matching quota types', () => {
    tracker.consume('claude', { tokens: 500, time: 2.5 })
    const service = manager.getState().services['claude']!
    expect(service.quotas.find(q => q.type === 'tokens')?.used).toBe(500)
    expect(service.quotas.find(q => q.type === 'time')?.used).toBe(2.5)
  })

  it('accumulates across multiple calls', () => {
    tracker.consume('claude', { tokens: 300 })
    tracker.consume('claude', { tokens: 200 })
    const service = manager.getState().services['claude']!
    expect(service.quotas.find(q => q.type === 'tokens')?.used).toBe(500)
  })

  it('ignores quota types not present in the amount', () => {
    tracker.consume('claude', { tokens: 100 })
    const service = manager.getState().services['claude']!
    expect(service.quotas.find(q => q.type === 'time')?.used).toBe(0)
  })
})

describe('resetQuota', () => {
  it('sets used to 0 for the specified type', () => {
    tracker.addService('openai', {
      label: 'OpenAI',
      quotas: [{ type: 'money', total: 20, unit: 'USD' }],
    })
    tracker.consume('openai', { money: 5.5 })
    tracker.resetQuota('openai', 'money')
    const service = manager.getState().services['openai']!
    expect(service.quotas.find(q => q.type === 'money')?.used).toBe(0)
  })
})
```

- [ ] **Step 2: Run tests — verify they fail**

```bash
npm test -- tests/tracker.test.ts
```

Expected: FAIL — `TokenTracker` not found.

- [ ] **Step 3: Implement tracker.ts**

```typescript
// src/tracker.ts
import type { QuotaType, Service } from './schema.js'
import { StateManager } from './state-manager.js'
import { Session } from './session.js'

export interface ServiceConfig {
  label: string
  quotas: Array<{ type: QuotaType; total: number; unit: string; resetsAt?: string }>
}

export interface ConsumeOptions {
  tokens?: number
  time?: number
  money?: number
  requests?: number
}

export class TokenTracker {
  constructor(private readonly manager: StateManager) {}

  addService(serviceId: string, config: ServiceConfig): void {
    this.manager.addService(serviceId, {
      label: config.label,
      quotas: config.quotas.map(q => ({ ...q, used: 0 })),
      currentSession: null,
    })
  }

  consume(serviceId: string, amount: ConsumeOptions): void {
    this.manager.updateService(serviceId, service => ({
      ...service,
      quotas: service.quotas.map(q => {
        const delta = amountForType(q.type, amount)
        return delta !== 0 ? { ...q, used: q.used + delta } : q
      }),
    }))
  }

  resetQuota(serviceId: string, type: QuotaType): void {
    this.manager.updateService(serviceId, service => ({
      ...service,
      quotas: service.quotas.map(q => (q.type === type ? { ...q, used: 0 } : q)),
    }))
  }

  startSession(serviceId: string): Session {
    return new Session(serviceId, this)
  }

  async withSession<T>(serviceId: string, fn: (session: Session) => Promise<T>): Promise<T> {
    const session = this.startSession(serviceId)
    try {
      return await fn(session)
    } finally {
      session.end()
    }
  }

  _setSession(serviceId: string, session: Service['currentSession']): void {
    this.manager.updateService(serviceId, s => ({ ...s, currentSession: session }))
  }

  async flush(): Promise<void> {
    await this.manager.flush()
  }
}

function amountForType(type: QuotaType, amount: ConsumeOptions): number {
  switch (type) {
    case 'tokens': return amount.tokens ?? 0
    case 'time': return amount.time ?? 0
    case 'money': return amount.money ?? 0
    case 'requests': return amount.requests ?? 0
  }
}
```

- [ ] **Step 4: Run tests — verify they pass**

```bash
npm test -- tests/tracker.test.ts
```

Expected: PASS (6 tests).

- [ ] **Step 5: Commit**

```bash
git add src/tracker.ts tests/tracker.test.ts
git commit -m "feat: TokenTracker with addService / consume / resetQuota"
```

---

## Task 6: Session

**Files:**
- Create: `src/session.ts`
- Create: `tests/session.test.ts`

- [ ] **Step 1: Write the failing tests**

```typescript
// tests/session.test.ts
import { describe, it, expect, beforeEach, afterEach } from 'vitest'
import { mkdtemp, rm } from 'node:fs/promises'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { TokenTracker } from '../src/tracker.js'
import { StateManager } from '../src/state-manager.js'

let tmpDir: string
let tracker: TokenTracker

beforeEach(async () => {
  tmpDir = await mkdtemp(join(tmpdir(), 'token-state-test-'))
  const manager = new StateManager(join(tmpDir, 'state.json'))
  tracker = new TokenTracker(manager)
  tracker.addService('claude', {
    label: 'Claude Max',
    quotas: [{ type: 'tokens', total: 1_000_000, unit: 'tokens' }],
  })
})

afterEach(async () => {
  await rm(tmpDir, { recursive: true, force: true })
})

describe('Session', () => {
  it('startSession sets currentSession to non-null', () => {
    const session = tracker.startSession('claude')
    const state = tracker['manager'].getState()
    expect(state.services['claude']?.currentSession).not.toBeNull()
    session.end()
  })

  it('currentSession has id and startedAt', () => {
    const session = tracker.startSession('claude')
    const snap = tracker['manager'].getState().services['claude']?.currentSession!
    expect(snap.id).toMatch(/^[0-9a-f-]{36}$/)
    expect(snap.startedAt).toMatch(/^\d{4}-\d{2}-\d{2}T/)
    session.end()
  })

  it('consume updates quota AND currentSession totals', () => {
    const session = tracker.startSession('claude')
    session.consume({ tokens: 300 })
    session.consume({ tokens: 200 })
    const state = tracker['manager'].getState()
    expect(state.services['claude']?.quotas[0]?.used).toBe(500)
    expect(state.services['claude']?.currentSession?.tokens).toBe(500)
    session.end()
  })

  it('end sets currentSession to null', () => {
    const session = tracker.startSession('claude')
    session.consume({ tokens: 100 })
    session.end()
    expect(tracker['manager'].getState().services['claude']?.currentSession).toBeNull()
  })

  it('end is idempotent — calling twice does not throw', () => {
    const session = tracker.startSession('claude')
    session.end()
    expect(() => session.end()).not.toThrow()
  })

  it('consume after end throws', () => {
    const session = tracker.startSession('claude')
    session.end()
    expect(() => session.consume({ tokens: 1 })).toThrow('Session already ended')
  })

  it('withSession ends session even if fn throws', async () => {
    await expect(
      tracker.withSession('claude', async (session) => {
        session.consume({ tokens: 50 })
        throw new Error('oops')
      })
    ).rejects.toThrow('oops')
    expect(tracker['manager'].getState().services['claude']?.currentSession).toBeNull()
  })
})
```

- [ ] **Step 2: Run tests — verify they fail**

```bash
npm test -- tests/session.test.ts
```

Expected: FAIL — `session.ts` not found.

- [ ] **Step 3: Implement session.ts**

```typescript
// src/session.ts
import { randomUUID } from 'node:crypto'
import type { TokenTracker, ConsumeOptions } from './tracker.js'
import type { Service } from './schema.js'

export class Session {
  private readonly id: string
  private readonly startedAt: string
  private totals: Required<ConsumeOptions> = { tokens: 0, time: 0, money: 0, requests: 0 }
  private ended = false

  constructor(
    private readonly serviceId: string,
    private readonly tracker: TokenTracker,
  ) {
    this.id = randomUUID()
    this.startedAt = new Date().toISOString()
    this.tracker._setSession(serviceId, { id: this.id, startedAt: this.startedAt })
  }

  consume(amount: ConsumeOptions): void {
    if (this.ended) throw new Error('Session already ended')
    for (const key of Object.keys(amount) as (keyof ConsumeOptions)[]) {
      this.totals[key] += amount[key] ?? 0
    }
    this.tracker.consume(this.serviceId, amount)
    const snap: Service['currentSession'] = {
      id: this.id,
      startedAt: this.startedAt,
      ...(this.totals.tokens > 0 && { tokens: this.totals.tokens }),
      ...(this.totals.time > 0 && { time: this.totals.time }),
      ...(this.totals.money > 0 && { money: this.totals.money }),
      ...(this.totals.requests > 0 && { requests: this.totals.requests }),
    }
    this.tracker._setSession(this.serviceId, snap)
  }

  end(): void {
    if (this.ended) return
    this.ended = true
    this.tracker._setSession(this.serviceId, null)
  }
}
```

- [ ] **Step 4: Run tests — verify they pass**

```bash
npm test -- tests/session.test.ts
```

Expected: PASS (7 tests).

- [ ] **Step 5: Commit**

```bash
git add src/session.ts tests/session.test.ts
git commit -m "feat: Session with consume tracking and withSession helper"
```

---

## Task 7: Provider — claude-max

**Files:**
- Create: `src/providers/claude-max.ts`
- Create: `tests/providers/claude-max.test.ts`

- [ ] **Step 1: Write the failing tests**

```typescript
// tests/providers/claude-max.test.ts
import { describe, it, expect, vi, beforeEach } from 'vitest'
import { readClaudeMaxUsage, parseClaudeOAuthResponse } from '../../src/providers/claude-max.js'

describe('parseClaudeOAuthResponse', () => {
  it('parses five_hour and seven_day windows', () => {
    const raw = {
      five_hour: { utilization: 40, resets_at: '2026-03-31T15:00:00Z' },
      seven_day: { utilization: 20, resets_at: '2026-04-07T00:00:00Z' },
    }
    const result = parseClaudeOAuthResponse(raw)
    expect(result.fiveHourUsedPercent).toBe(40)
    expect(result.fiveHourResetsAt).toBe('2026-03-31T15:00:00Z')
    expect(result.sevenDayUsedPercent).toBe(20)
    expect(result.sevenDayResetsAt).toBe('2026-04-07T00:00:00Z')
  })

  it('handles missing seven_day gracefully', () => {
    const raw = {
      five_hour: { utilization: 60, resets_at: '2026-03-31T15:00:00Z' },
    }
    const result = parseClaudeOAuthResponse(raw)
    expect(result.sevenDayUsedPercent).toBeUndefined()
  })
})

describe('readClaudeMaxUsage', () => {
  beforeEach(() => {
    vi.stubGlobal('fetch', vi.fn())
  })

  it('calls Claude OAuth API with Bearer token', async () => {
    const mockFetch = vi.mocked(fetch)
    mockFetch.mockResolvedValueOnce(
      new Response(JSON.stringify({
        five_hour: { utilization: 50, resets_at: '2026-03-31T15:00:00Z' },
        seven_day: { utilization: 30, resets_at: '2026-04-07T00:00:00Z' },
      }), { status: 200, headers: { 'Content-Type': 'application/json' } })
    )

    const result = await readClaudeMaxUsage({ accessToken: 'test-token' })

    expect(mockFetch).toHaveBeenCalledWith(
      'https://api.anthropic.com/api/oauth/usage',
      expect.objectContaining({
        headers: expect.objectContaining({ Authorization: 'Bearer test-token' }),
      })
    )
    expect(result.fiveHourUsedPercent).toBe(50)
  })

  it('throws on non-200 response', async () => {
    vi.mocked(fetch).mockResolvedValueOnce(
      new Response('Unauthorized', { status: 401 })
    )
    await expect(readClaudeMaxUsage({ accessToken: 'bad-token' })).rejects.toThrow('Claude OAuth API returned 401')
  })
})
```

- [ ] **Step 2: Run tests — verify they fail**

```bash
npm test -- tests/providers/claude-max.test.ts
```

Expected: FAIL — module not found.

- [ ] **Step 3: Implement providers/claude-max.ts**

```typescript
// src/providers/claude-max.ts

export interface ClaudeRateWindow {
  fiveHourUsedPercent: number
  fiveHourResetsAt: string
  sevenDayUsedPercent?: number
  sevenDayResetsAt?: string
}

export interface ClaudeMaxConfig {
  accessToken: string
}

export function parseClaudeOAuthResponse(raw: Record<string, unknown>): ClaudeRateWindow {
  const fiveHour = raw['five_hour'] as Record<string, unknown> | undefined
  const sevenDay = raw['seven_day'] as Record<string, unknown> | undefined

  return {
    fiveHourUsedPercent: Number(fiveHour?.['utilization'] ?? 0),
    fiveHourResetsAt: String(fiveHour?.['resets_at'] ?? new Date().toISOString()),
    ...(sevenDay && {
      sevenDayUsedPercent: Number(sevenDay['utilization']),
      sevenDayResetsAt: String(sevenDay['resets_at']),
    }),
  }
}

export async function readClaudeMaxUsage(config: ClaudeMaxConfig): Promise<ClaudeRateWindow> {
  const res = await fetch('https://api.anthropic.com/api/oauth/usage', {
    headers: {
      Authorization: `Bearer ${config.accessToken}`,
      'anthropic-beta': 'oauth-2025-04-20',
      Accept: 'application/json',
    },
  })
  if (!res.ok) throw new Error(`Claude OAuth API returned ${res.status}`)
  const body = await res.json() as Record<string, unknown>
  return parseClaudeOAuthResponse(body)
}
```

- [ ] **Step 4: Run tests — verify they pass**

```bash
npm test -- tests/providers/claude-max.test.ts
```

Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add src/providers/claude-max.ts tests/providers/claude-max.test.ts
git commit -m "feat: claude-max provider reads OAuth rate window"
```

---

## Task 8: Provider — claude-pro

**Files:**
- Create: `src/providers/claude-pro.ts`
- Create: `tests/providers/claude-pro.test.ts`

- [ ] **Step 1: Write the failing tests**

```typescript
// tests/providers/claude-pro.test.ts
import { describe, it, expect, vi, beforeEach } from 'vitest'
import { readClaudeProUsage, parseClaudeWebUsage } from '../../src/providers/claude-pro.js'

describe('parseClaudeWebUsage', () => {
  it('parses five_hour and seven_day from web API response', () => {
    const orgUsage = {
      five_hour: { utilization: 55, resets_at: '2026-03-31T15:00:00Z' },
      seven_day: { utilization: 25, resets_at: '2026-04-07T00:00:00Z' },
    }
    const result = parseClaudeWebUsage(orgUsage)
    expect(result.fiveHourUsedPercent).toBe(55)
    expect(result.fiveHourResetsAt).toBe('2026-03-31T15:00:00Z')
    expect(result.sevenDayUsedPercent).toBe(25)
  })
})

describe('readClaudeProUsage', () => {
  beforeEach(() => {
    vi.stubGlobal('fetch', vi.fn())
  })

  it('fetches org ID then usage in sequence', async () => {
    const mockFetch = vi.mocked(fetch)

    // First call: GET /api/organizations
    mockFetch.mockResolvedValueOnce(
      new Response(JSON.stringify([{ uuid: 'org-123', name: 'My Org' }]), {
        status: 200,
        headers: { 'Content-Type': 'application/json' },
      })
    )

    // Second call: GET /api/organizations/org-123/usage
    mockFetch.mockResolvedValueOnce(
      new Response(JSON.stringify({
        five_hour: { utilization: 70, resets_at: '2026-03-31T15:00:00Z' },
        seven_day: { utilization: 40, resets_at: '2026-04-07T00:00:00Z' },
      }), {
        status: 200,
        headers: { 'Content-Type': 'application/json' },
      })
    )

    const result = await readClaudeProUsage({ sessionKey: 'sk-ant-test' })
    expect(mockFetch).toHaveBeenCalledTimes(2)
    expect(result.fiveHourUsedPercent).toBe(70)
  })

  it('throws when no organizations returned', async () => {
    vi.mocked(fetch).mockResolvedValueOnce(
      new Response(JSON.stringify([]), { status: 200, headers: { 'Content-Type': 'application/json' } })
    )
    await expect(readClaudeProUsage({ sessionKey: 'sk-ant-test' })).rejects.toThrow('No Claude organization found')
  })

  it('throws on 401', async () => {
    vi.mocked(fetch).mockResolvedValueOnce(
      new Response('Unauthorized', { status: 401 })
    )
    await expect(readClaudeProUsage({ sessionKey: 'sk-ant-bad' })).rejects.toThrow('claude.ai returned 401')
  })
})
```

- [ ] **Step 2: Run tests — verify they fail**

```bash
npm test -- tests/providers/claude-pro.test.ts
```

Expected: FAIL — module not found.

- [ ] **Step 3: Implement providers/claude-pro.ts**

```typescript
// src/providers/claude-pro.ts
// @experimental — uses claude.ai internal API, may break without notice

import type { ClaudeRateWindow } from './claude-max.js'

export interface ClaudeProConfig {
  sessionKey: string // sk-ant-... cookie value, extracted by token_hud
}

export function parseClaudeWebUsage(raw: Record<string, unknown>): ClaudeRateWindow {
  const fiveHour = raw['five_hour'] as Record<string, unknown> | undefined
  const sevenDay = raw['seven_day'] as Record<string, unknown> | undefined

  return {
    fiveHourUsedPercent: Number(fiveHour?.['utilization'] ?? 0),
    fiveHourResetsAt: String(fiveHour?.['resets_at'] ?? new Date().toISOString()),
    ...(sevenDay && {
      sevenDayUsedPercent: Number(sevenDay['utilization']),
      sevenDayResetsAt: String(sevenDay['resets_at']),
    }),
  }
}

async function claudeAiFetch(path: string, sessionKey: string): Promise<Response> {
  const res = await fetch(`https://claude.ai${path}`, {
    headers: {
      Cookie: `sessionKey=${sessionKey}`,
      Accept: 'application/json',
    },
  })
  if (!res.ok) throw new Error(`claude.ai returned ${res.status} for ${path}`)
  return res
}

export async function readClaudeProUsage(config: ClaudeProConfig): Promise<ClaudeRateWindow> {
  const orgsRes = await claudeAiFetch('/api/organizations', config.sessionKey)
  const orgs = await orgsRes.json() as Array<{ uuid: string }>
  const org = orgs[0]
  if (!org) throw new Error('No Claude organization found')

  const usageRes = await claudeAiFetch(`/api/organizations/${org.uuid}/usage`, config.sessionKey)
  const usage = await usageRes.json() as Record<string, unknown>
  return parseClaudeWebUsage(usage)
}
```

- [ ] **Step 4: Run tests — verify they pass**

```bash
npm test -- tests/providers/claude-pro.test.ts
```

Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add src/providers/claude-pro.ts tests/providers/claude-pro.test.ts
git commit -m "feat: claude-pro provider reads claude.ai internal API (experimental)"
```

---

## Task 9: Provider — openai

**Files:**
- Create: `src/providers/openai.ts`
- Create: `tests/providers/openai.test.ts`

- [ ] **Step 1: Write the failing tests**

```typescript
// tests/providers/openai.test.ts
import { describe, it, expect, vi, beforeEach } from 'vitest'
import { readOpenAIUsage, readOpenAIBalance } from '../../src/providers/openai.js'

describe('readOpenAIUsage', () => {
  beforeEach(() => { vi.stubGlobal('fetch', vi.fn()) })

  it('returns total token usage for current month', async () => {
    vi.mocked(fetch).mockResolvedValueOnce(
      new Response(JSON.stringify({
        data: [
          { aggregation_timestamp: 1711843200, n_requests: 10, n_context_tokens_total: 5000, n_generated_tokens_total: 1000 },
          { aggregation_timestamp: 1711929600, n_requests: 5, n_context_tokens_total: 3000, n_generated_tokens_total: 500 },
        ],
      }), { status: 200, headers: { 'Content-Type': 'application/json' } })
    )
    const result = await readOpenAIUsage({ apiKey: 'sk-test' })
    expect(result.totalTokens).toBe(9500)
    expect(result.totalRequests).toBe(15)
  })

  it('throws on 401', async () => {
    vi.mocked(fetch).mockResolvedValueOnce(new Response('', { status: 401 }))
    await expect(readOpenAIUsage({ apiKey: 'bad' })).rejects.toThrow('OpenAI Usage API returned 401')
  })
})

describe('readOpenAIBalance', () => {
  beforeEach(() => { vi.stubGlobal('fetch', vi.fn()) })

  it('returns available balance in USD', async () => {
    vi.mocked(fetch).mockResolvedValueOnce(
      new Response(JSON.stringify({
        grants: {
          data: [
            { grant_amount: 20.00, used_amount: 1.50, effective_at: 1700000000, expires_at: 1800000000 },
          ],
        },
      }), { status: 200, headers: { 'Content-Type': 'application/json' } })
    )
    const result = await readOpenAIBalance({ apiKey: 'sk-test' })
    expect(result.totalGranted).toBe(20.00)
    expect(result.totalUsed).toBe(1.50)
    expect(result.remaining).toBeCloseTo(18.50)
  })

  it('returns null when endpoint returns 404 (subscription account, no prepaid)', async () => {
    vi.mocked(fetch).mockResolvedValueOnce(new Response('', { status: 404 }))
    const result = await readOpenAIBalance({ apiKey: 'sk-test' })
    expect(result).toBeNull()
  })
})
```

- [ ] **Step 2: Run tests — verify they fail**

```bash
npm test -- tests/providers/openai.test.ts
```

Expected: FAIL — module not found.

- [ ] **Step 3: Implement providers/openai.ts**

```typescript
// src/providers/openai.ts

export interface OpenAIConfig {
  apiKey: string
}

export interface OpenAIUsageResult {
  totalTokens: number
  totalRequests: number
}

export interface OpenAIBalanceResult {
  totalGranted: number
  totalUsed: number
  remaining: number
}

export async function readOpenAIUsage(config: OpenAIConfig): Promise<OpenAIUsageResult> {
  const startDate = new Date()
  startDate.setDate(1) // first of current month
  const startTime = Math.floor(startDate.getTime() / 1000)

  const res = await fetch(
    `https://api.openai.com/v1/usage?date=${startDate.toISOString().slice(0, 10)}`,
    {
      headers: {
        Authorization: `Bearer ${config.apiKey}`,
        Accept: 'application/json',
      },
    }
  )
  if (!res.ok) throw new Error(`OpenAI Usage API returned ${res.status}`)

  const body = await res.json() as { data: Array<{ n_context_tokens_total: number; n_generated_tokens_total: number; n_requests: number }> }
  const totalTokens = body.data.reduce((sum, d) => sum + d.n_context_tokens_total + d.n_generated_tokens_total, 0)
  const totalRequests = body.data.reduce((sum, d) => sum + d.n_requests, 0)
  return { totalTokens, totalRequests }
}

export async function readOpenAIBalance(config: OpenAIConfig): Promise<OpenAIBalanceResult | null> {
  const res = await fetch('https://api.openai.com/v1/dashboard/billing/credit_grants', {
    headers: {
      Authorization: `Bearer ${config.apiKey}`,
      Accept: 'application/json',
    },
  })
  if (res.status === 404) return null // subscription account, no prepaid credits
  if (!res.ok) throw new Error(`OpenAI Billing API returned ${res.status}`)

  const body = await res.json() as { grants: { data: Array<{ grant_amount: number; used_amount: number }> } }
  const totalGranted = body.grants.data.reduce((sum, g) => sum + g.grant_amount, 0)
  const totalUsed = body.grants.data.reduce((sum, g) => sum + g.used_amount, 0)
  return { totalGranted, totalUsed, remaining: totalGranted - totalUsed }
}
```

- [ ] **Step 4: Run tests — verify they pass**

```bash
npm test -- tests/providers/openai.test.ts
```

Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add src/providers/openai.ts tests/providers/openai.test.ts
git commit -m "feat: OpenAI provider reads Usage API and prepaid balance"
```

---

## Task 10: SDK Plugin — wrapOpenAI

**Files:**
- Create: `src/plugins/openai.ts`
- Create: `tests/plugins/openai.test.ts`

- [ ] **Step 1: Write the failing tests**

```typescript
// tests/plugins/openai.test.ts
import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest'
import { mkdtemp, rm } from 'node:fs/promises'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { wrapOpenAI } from '../../src/plugins/openai.js'
import { TokenTracker } from '../../src/tracker.js'
import { StateManager } from '../../src/state-manager.js'

let tmpDir: string
let tracker: TokenTracker

beforeEach(async () => {
  tmpDir = await mkdtemp(join(tmpdir(), 'token-state-test-'))
  const manager = new StateManager(join(tmpDir, 'state.json'))
  tracker = new TokenTracker(manager)
  tracker.addService('openai', {
    label: 'OpenAI',
    quotas: [{ type: 'tokens', total: 1_000_000, unit: 'tokens' }],
  })
})

afterEach(async () => {
  await rm(tmpDir, { recursive: true, force: true })
})

describe('wrapOpenAI', () => {
  it('intercepts chat.completions.create and consumes token usage', async () => {
    const fakeClient = {
      chat: {
        completions: {
          create: vi.fn().mockResolvedValue({
            choices: [{ message: { content: 'Hello' } }],
            usage: { prompt_tokens: 100, completion_tokens: 50, total_tokens: 150 },
          }),
        },
      },
    }

    const wrapped = wrapOpenAI(fakeClient as never, tracker, 'openai')
    await wrapped.chat.completions.create({ model: 'gpt-4o', messages: [] } as never)

    const state = tracker['manager'].getState()
    expect(state.services['openai']?.quotas[0]?.used).toBe(150)
  })

  it('still returns the original response', async () => {
    const response = {
      choices: [{ message: { content: 'Hi' } }],
      usage: { total_tokens: 80 },
    }
    const fakeClient = {
      chat: { completions: { create: vi.fn().mockResolvedValue(response) } },
    }
    const wrapped = wrapOpenAI(fakeClient as never, tracker, 'openai')
    const result = await wrapped.chat.completions.create({ model: 'gpt-4o', messages: [] } as never)
    expect(result).toBe(response)
  })

  it('does not consume if usage is missing from response', async () => {
    const fakeClient = {
      chat: { completions: { create: vi.fn().mockResolvedValue({ choices: [] }) } },
    }
    const wrapped = wrapOpenAI(fakeClient as never, tracker, 'openai')
    await wrapped.chat.completions.create({ model: 'gpt-4o', messages: [] } as never)
    expect(tracker['manager'].getState().services['openai']?.quotas[0]?.used).toBe(0)
  })
})
```

- [ ] **Step 2: Run tests — verify they fail**

```bash
npm test -- tests/plugins/openai.test.ts
```

Expected: FAIL — module not found.

- [ ] **Step 3: Implement plugins/openai.ts**

```typescript
// src/plugins/openai.ts
import type { TokenTracker } from '../tracker.js'

interface OpenAILike {
  chat: {
    completions: {
      create(params: unknown): Promise<{ usage?: { total_tokens?: number } }>
    }
  }
}

export function wrapOpenAI<T extends OpenAILike>(
  client: T,
  tracker: TokenTracker,
  serviceId: string,
): T {
  return {
    ...client,
    chat: {
      ...client.chat,
      completions: {
        ...client.chat.completions,
        create: async (params: unknown) => {
          const result = await client.chat.completions.create(params)
          const tokens = result.usage?.total_tokens
          if (tokens) tracker.consume(serviceId, { tokens })
          return result
        },
      },
    },
  } as T
}
```

- [ ] **Step 4: Run tests — verify they pass**

```bash
npm test -- tests/plugins/openai.test.ts
```

Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add src/plugins/openai.ts tests/plugins/openai.test.ts
git commit -m "feat: wrapOpenAI plugin auto-consumes token usage"
```

---

## Task 11: SDK Plugin — wrapAnthropic

**Files:**
- Create: `src/plugins/anthropic.ts`
- Create: `tests/plugins/anthropic.test.ts`

- [ ] **Step 1: Write the failing tests**

```typescript
// tests/plugins/anthropic.test.ts
import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest'
import { mkdtemp, rm } from 'node:fs/promises'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { wrapAnthropic } from '../../src/plugins/anthropic.js'
import { TokenTracker } from '../../src/tracker.js'
import { StateManager } from '../../src/state-manager.js'

let tmpDir: string
let tracker: TokenTracker

beforeEach(async () => {
  tmpDir = await mkdtemp(join(tmpdir(), 'token-state-test-'))
  const manager = new StateManager(join(tmpDir, 'state.json'))
  tracker = new TokenTracker(manager)
  tracker.addService('claude', {
    label: 'Claude',
    quotas: [{ type: 'tokens', total: 1_000_000, unit: 'tokens' }],
  })
})

afterEach(async () => {
  await rm(tmpDir, { recursive: true, force: true })
})

describe('wrapAnthropic', () => {
  it('intercepts messages.create and consumes input + output tokens', async () => {
    const fakeClient = {
      messages: {
        create: vi.fn().mockResolvedValue({
          content: [{ text: 'Hello' }],
          usage: { input_tokens: 80, output_tokens: 40 },
        }),
      },
    }
    const wrapped = wrapAnthropic(fakeClient as never, tracker, 'claude')
    await wrapped.messages.create({ model: 'claude-opus-4-6', messages: [] } as never)

    expect(tracker['manager'].getState().services['claude']?.quotas[0]?.used).toBe(120)
  })

  it('returns the original response unchanged', async () => {
    const response = { content: [{ text: 'Hi' }], usage: { input_tokens: 10, output_tokens: 5 } }
    const fakeClient = { messages: { create: vi.fn().mockResolvedValue(response) } }
    const wrapped = wrapAnthropic(fakeClient as never, tracker, 'claude')
    const result = await wrapped.messages.create({} as never)
    expect(result).toBe(response)
  })
})
```

- [ ] **Step 2: Run tests — verify they fail**

```bash
npm test -- tests/plugins/anthropic.test.ts
```

Expected: FAIL — module not found.

- [ ] **Step 3: Implement plugins/anthropic.ts**

```typescript
// src/plugins/anthropic.ts
import type { TokenTracker } from '../tracker.js'

interface AnthropicLike {
  messages: {
    create(params: unknown): Promise<{ usage?: { input_tokens?: number; output_tokens?: number } }>
  }
}

export function wrapAnthropic<T extends AnthropicLike>(
  client: T,
  tracker: TokenTracker,
  serviceId: string,
): T {
  return {
    ...client,
    messages: {
      ...client.messages,
      create: async (params: unknown) => {
        const result = await client.messages.create(params)
        const tokens = (result.usage?.input_tokens ?? 0) + (result.usage?.output_tokens ?? 0)
        if (tokens > 0) tracker.consume(serviceId, { tokens })
        return result
      },
    },
  } as T
}
```

- [ ] **Step 4: Run tests — verify they pass**

```bash
npm test -- tests/plugins/anthropic.test.ts
```

Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add src/plugins/anthropic.ts tests/plugins/anthropic.test.ts
git commit -m "feat: wrapAnthropic plugin consumes input + output tokens"
```

---

## Task 12: Daemon CLI

**Files:**
- Create: `bin/daemon.ts`
- Create: `~/.token-hud/config.json` (documented, not committed)

- [ ] **Step 1: Document config schema**

Create `src/config.ts`:

```typescript
// src/config.ts
export interface DaemonConfig {
  stateFile?: string        // default: ~/.token-hud/state.json
  intervalSeconds?: number  // default: 60
  services: {
    claudeMax?: { accessToken: string }
    claudePro?: { sessionKey: string }
    openai?: { apiKey: string }
  }
}
```

- [ ] **Step 2: Implement bin/daemon.ts**

```typescript
// bin/daemon.ts
import { readFile } from 'node:fs/promises'
import { resolve } from 'node:path'
import { homedir } from 'node:os'
import { TokenTracker } from '../src/tracker.js'
import { StateManager } from '../src/state-manager.js'
import { readClaudeMaxUsage } from '../src/providers/claude-max.js'
import { readClaudeProUsage } from '../src/providers/claude-pro.js'
import { readOpenAIUsage, readOpenAIBalance } from '../src/providers/openai.js'
import type { DaemonConfig } from '../src/config.js'

async function loadConfig(): Promise<DaemonConfig> {
  const configPath = resolve(homedir(), '.token-hud', 'config.json')
  const raw = await readFile(configPath, 'utf8')
  return JSON.parse(raw) as DaemonConfig
}

async function syncAll(tracker: TokenTracker, config: DaemonConfig): Promise<void> {
  const errors: string[] = []

  if (config.services.claudeMax) {
    try {
      const usage = await readClaudeMaxUsage(config.services.claudeMax)
      // Convert percent-used back to used amount for storage
      tracker.addService('claude-max', {
        label: 'Claude Max',
        quotas: [
          {
            type: 'time',
            total: 18000,
            unit: 'seconds',
            resetsAt: usage.fiveHourResetsAt,
          },
        ],
      })
      const used = Math.round((usage.fiveHourUsedPercent / 100) * 18000)
      tracker['manager'].updateService('claude-max', s => ({
        ...s,
        quotas: s.quotas.map(q => ({ ...q, used })),
      }))
    } catch (e) {
      errors.push(`claude-max: ${String(e)}`)
    }
  }

  if (config.services.claudePro) {
    try {
      const usage = await readClaudeProUsage(config.services.claudePro)
      tracker.addService('claude-pro', {
        label: 'Claude Pro',
        quotas: [{ type: 'time', total: 18000, unit: 'seconds', resetsAt: usage.fiveHourResetsAt }],
      })
      const used = Math.round((usage.fiveHourUsedPercent / 100) * 18000)
      tracker['manager'].updateService('claude-pro', s => ({
        ...s,
        quotas: s.quotas.map(q => ({ ...q, used })),
      }))
    } catch (e) {
      errors.push(`claude-pro: ${String(e)}`)
    }
  }

  if (config.services.openai) {
    try {
      const [usage, balance] = await Promise.all([
        readOpenAIUsage(config.services.openai),
        readOpenAIBalance(config.services.openai),
      ])
      const quotas = [{ type: 'tokens' as const, total: 10_000_000, used: usage.totalTokens, unit: 'tokens' }]
      if (balance) {
        quotas.push({ type: 'money' as const, total: balance.totalGranted, used: balance.totalUsed, unit: 'USD' })
      }
      tracker.addService('openai', { label: 'OpenAI', quotas })
    } catch (e) {
      errors.push(`openai: ${String(e)}`)
    }
  }

  await tracker.flush()

  if (errors.length) {
    console.error('[token-state daemon] Errors during sync:')
    errors.forEach(e => console.error(' •', e))
  } else {
    console.log(`[token-state daemon] Sync complete at ${new Date().toISOString()}`)
  }
}

async function main(): Promise<void> {
  const config = await loadConfig()
  const stateFile = config.stateFile ?? '~/.token-hud/state.json'
  const intervalMs = (config.intervalSeconds ?? 60) * 1000
  const manager = new StateManager(stateFile)
  const tracker = new TokenTracker(manager)

  console.log(`[token-state daemon] Starting. Interval: ${config.intervalSeconds ?? 60}s`)
  await syncAll(tracker, config)
  setInterval(() => { void syncAll(tracker, config) }, intervalMs)
}

main().catch(err => {
  console.error('[token-state daemon] Fatal error:', err)
  process.exit(1)
})
```

- [ ] **Step 3: Verify daemon compiles**

```bash
npx tsc --noEmit
```

Expected: no errors.

- [ ] **Step 4: Document sample config**

Create `config.example.json` (committed to repo):

```json
{
  "stateFile": "~/.token-hud/state.json",
  "intervalSeconds": 60,
  "services": {
    "claudeMax": {
      "accessToken": "YOUR_CLAUDE_OAUTH_ACCESS_TOKEN"
    },
    "claudePro": {
      "sessionKey": "sk-ant-YOUR_SESSION_KEY_FROM_TOKEN_HUD_APP"
    },
    "openai": {
      "apiKey": "sk-YOUR_OPENAI_API_KEY"
    }
  }
}
```

- [ ] **Step 5: Run full test suite**

```bash
npm test
```

Expected: all tests pass (≥ 30 tests).

- [ ] **Step 6: Final commit**

```bash
git add bin/daemon.ts src/config.ts config.example.json
git commit -m "feat: daemon CLI syncs all providers on configurable interval"
```

---

## Self-Review

**Spec coverage check:**
- ✅ `state.json` schema → Task 2 (`schema.ts`)
- ✅ Atomic write → Task 3 (`writer.ts`)
- ✅ `consume()` / `addService()` / `resetQuota()` → Task 5 (`tracker.ts`)
- ✅ Session tracking + `withSession()` → Task 6 (`session.ts`)
- ✅ Claude Max OAuth API → Task 7 (`claude-max.ts`)
- ✅ Claude Pro web API → Task 8 (`claude-pro.ts`)
- ✅ OpenAI Usage + Balance API → Task 9 (`openai.ts`)
- ✅ `wrapOpenAI` plugin → Task 10
- ✅ `wrapAnthropic` plugin → Task 11
- ✅ Daemon CLI + config file → Task 12
- ⚠️ Gemini provider — deferred to next iteration (complex Google OAuth, not in MVP)

**Type consistency check:**
- `ConsumeOptions` defined in `tracker.ts`, used in `session.ts` ✅
- `ClaudeRateWindow` defined in `claude-max.ts`, re-used by `claude-pro.ts` via import ✅
- `SessionSnapshot` (schema.ts) vs `Session` class (session.ts) — distinct on purpose ✅
- `tracker['manager']` accessed in tests — acceptable for white-box testing ✅

**Placeholder scan:** No TBD/TODO found. All code blocks are complete. ✅
