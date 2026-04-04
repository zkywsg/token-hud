# token-hud

A macOS menu bar app that displays your AI service usage quotas (Claude, OpenAI, etc.) as a real-time overlay in the notch area of your MacBook.

![macOS 14+](https://img.shields.io/badge/macOS-14%2B-blue)
![Swift 6](https://img.shields.io/badge/Swift-6-orange)

## What it does

token-hud reads a local JSON file (`~/.token-hud/state.json`) and renders your quota usage directly in the notch — no browser tab, no manual checking.

- Token usage bars
- Time window countdowns (5-hour, 7-day)
- Credit balance
- Configurable widgets (ring, bar, text)
- Works with any service supported by [token-state](https://github.com/zkywsg/token-state)

## Requirements

- macOS 14 (Sonoma) or later
- MacBook with notch display
- [token-state](https://github.com/zkywsg/token-state) daemon running in the background

## Installation

### Build from source

1. Clone the repo:

```bash
git clone https://github.com/zkywsg/token-hud.git
cd token-hud
```

2. Open in Xcode:

```bash
open token_hud.xcodeproj
```

3. Build and run (⌘R)

### Set up the data source

token-hud reads from `~/.token-hud/state.json`, which is written by the [token-state](https://github.com/zkywsg/token-state) daemon. Follow its setup guide to get your API credentials configured.

```bash
# Install and start the daemon
npm install -g token-state
token-state
```

## Configuration

Once the app is running, click the menu bar icon to open Settings:

- **Services** — extract your Claude session key directly from Safari/Chrome, or paste it manually
- **Widgets** — add, remove, and reorder the metrics shown in the notch

## Architecture

token-hud is intentionally decoupled from any specific AI service:

```
token-state daemon  →  ~/.token-hud/state.json  →  token-hud app
```

The app only reads the local JSON file. All API communication happens in [token-state](https://github.com/zkywsg/token-state), which can be replaced with any tool that writes to the same schema.

### Project structure

```
token_hud/
├── App/          # App entry point and AppDelegate
├── Overlay/      # Notch window management and layout
├── Widgets/      # Widget types (bar, ring, text, aggregate)
├── Settings/     # Settings window, session key extractor
├── State/        # StateWatcher (file watcher → StateFile)
└── Support/      # Keychain helper

Sources/token_hudCore/
├── StateModel.swift          # Shared data types (StateFile, Quota, etc.)
└── WidgetValueComputer.swift # Pure logic for computing display values
```

## state.json Schema

See [token-state](https://github.com/zkywsg/token-state#statejson-schema) for the full schema definition.

## License

MIT
