# TokenState / TokenHUD Split

## Direction

TokenState and TokenHUD should be separate repos that communicate through the
state file contract:

```text
token_state -> ~/.token-hud/state.json -> token_hud
```

The local sibling layout is:

```text
/Users/lauzanhing/Desktop/token_state
/Users/lauzanhing/Desktop/token_hud
```

## TokenState Responsibilities

- Own the `StateFile` schema and provider parsers.
- Read local state sources such as Codex auth and session logs.
- Call provider APIs when usage or credential validation requires network data.
- Merge service data and write `~/.token-hud/state.json`.
- Provide tests for schema compatibility and provider parsing.

## TokenHUD Responsibilities

- Watch `~/.token-hud/state.json`.
- Render HUD widgets and settings.
- Store UI preferences.
- Trigger refresh actions without implementing provider fetching in the UI layer.

## Current Status

`/Users/lauzanhing/Desktop/token_state` has been initialized as a standalone
Swift package with the copied core schema, parser, formatting helpers, tests,
and a one-shot refresh CLI.

`token_hud` still builds using its local `Sources/token_hudCore` copy and still
contains the existing app-side fetchers. This keeps the app working while the
split happens incrementally.

## Next Migration Step

Replace app-side fetch triggers with a TokenState invocation path. The immediate
candidate is:

```bash
cd /Users/lauzanhing/Desktop/token_state
swift run token-state refresh --state-file ~/.token-hud/state.json
```

After TokenHUD triggers TokenState reliably, remove provider fetching from
`token_hud/State/CodexFetcher.swift` and keep TokenHUD consuming `state.json`
through `StateWatcher`.
