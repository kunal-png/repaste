<p align="center">
  <img src="assets/logo.png" alt="Repaste" height="48">
</p>

<p align="center">
  A lightweight macOS clipboard manager that lets you scroll through your clipboard history and paste any previous item — instantly.
</p>

<p align="center">
  <a href="https://github.com/kunal-png/repaste/releases/latest/download/Repaste-v1.0.0.dmg">
    <img src="https://img.shields.io/badge/Download-Repaste.dmg-8B5CF6?style=for-the-badge&logo=apple&logoColor=white" alt="Download DMG">
  </a>
  &nbsp;&nbsp;
  <a href="https://github.com/kunal-png/repaste/releases/latest">
    <img src="https://img.shields.io/github/v/release/kunal-png/repaste?style=for-the-badge&color=1e1e2e&label=Latest" alt="Latest Release">
  </a>
</p>

## How It Works

1. Copy things as usual (⌘C)
2. Hold **⌘⇧V** (or your custom shortcut)
3. A rotary carousel appears with your clipboard history
4. Scroll to pick an item, release to paste
5. Press **Esc** to cancel

## Features

- **Custom shortcut** — click to record any key combination you want
- **Position options** — show the picker centered on screen or above your text cursor
- **Privacy-first** — all data stays local, no network access except optional update checks

## Installation

### Download
1. Go to the [Releases](https://github.com/kunal-png/repaste/releases) page
2. Download the latest `.dmg` file
3. Open the DMG, double click to launch, it appears in your menu bar
4. Grant **Accessibility** permission when prompted (required for global shortcuts)
5. click on **start listning** in repaste/settings to listen for your shortcut, click on refresh listner everytime you update shortcut key or for general troubleshooting

### Build from Source
```bash
git clone https://github.com/kunal-png/repaste.git
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

the code is generated with cursor(composer).
