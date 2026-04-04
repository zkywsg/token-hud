# token-hud

Your AI quota, always visible — tucked into the MacBook notch.

[中文版](README.zh.md) · [![macOS 14+](https://img.shields.io/badge/macOS-14%2B-blue?style=flat-square)](https://www.apple.com/macos/) [![Swift 6](https://img.shields.io/badge/Swift-6-orange?style=flat-square)](https://swift.org) [![MIT](https://img.shields.io/badge/license-MIT-green?style=flat-square)](LICENSE)

---

<!-- Replace with a real screenshot once the app UI is finalised -->
> 📸 **Screenshot coming soon** — drop a notch overlay image here when ready.

---

## Features

- Real-time Claude · OpenAI usage sync
- 5-hour & 7-day quota countdown
- Ring · Bar · Text widgets — mix and match
- Lives entirely in the notch, zero screen footprint

## Quick Start

**Requirements:** macOS 14+, notched MacBook, Node.js 18+

**1. Start the data source**

```bash
npm install -g token-state
token-state
```

**2. Build the app**

```bash
git clone https://github.com/zkywsg/token-hud.git
open token_hud.xcodeproj   # then press ⌘R
```

**3. Configure services**

Click the menu bar icon → **Settings** → paste your API key, or use one-click extraction for Claude session keys directly from Safari / Chrome.

---

<details>
<summary>Architecture & developer docs</summary>

token-hud never calls AI APIs directly. All data flows through a local file:

```
token-state daemon  →  ~/.token-hud/state.json  →  token-hud
```

Any tool that writes to the same schema works as a drop-in replacement for the daemon. See the [state.json schema →](https://github.com/zkywsg/token-state#statejson-schema)

</details>

## License

MIT
