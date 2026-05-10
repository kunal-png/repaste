<p align="center">
  <img src="assets/logo.png" alt="Repaste" height="48">
</p>

<p align="center">
  A lightweight macOS clipboard manager that lets you scroll through your clipboard history and paste any previous item — instantly.
</p>

## How It Works

1. Copy things as usual (⌘C)
2. Hold **⌘⇧V** (or your custom shortcut)
3. A rotary carousel appears with your clipboard history
4. Scroll to pick an item, release to paste
5. Press **Esc** to cancel

## Features

- **Rotary carousel UI** — scroll through clipboard history with a smooth, animated arc
- **Custom shortcut** — click to record any key combination you want
- **Position options** — show the picker centered on screen or above your text cursor
- **Lightweight** — runs as a menu bar app, no Dock icon
- **Privacy-first** — all data stays local, no network access except optional update checks
- **Auto-update checks** — get notified when a new version is available on GitHub

## Installation

### Download
1. Go to the [Releases](https://github.com/kunalzed/repaste/releases) page
2. Download the latest `.dmg` file
3. Open the DMG, drag **Repaste** to your Applications folder
4. Launch Repaste — it appears in your menu bar
5. Grant **Accessibility** permission when prompted (required for global shortcuts)

### Build from Source
```bash
git clone https://github.com/kunalzed/repaste.git
cd repaste
open Repaste.xcodeproj
```
Then build and run in Xcode (⌘R).

**Requirements:** macOS 14.0+, Xcode 15+

## First Launch

1. Open Repaste from your menu bar
2. Click **Settings**
3. Grant **Accessibility** access (click "Grant Access…")
4. Click **Start Listening**
5. You're ready! Hold ⌘⇧V anywhere to try it

## Settings

| Setting | Description |
|---------|-------------|
| **Shortcut** | Click the shortcut pill to record a new key combo |
| **History** | Keep 5–200 clipboard items |
| **Popup Position** | Centered on screen, or above your text cursor |
| **Updates** | Check for new versions from GitHub Releases |

## License

[MIT License](LICENSE) — free to use, modify, and distribute.

## Contributing

Issues and pull requests are welcome! Please open an issue first to discuss any major changes.
