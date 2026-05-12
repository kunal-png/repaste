# Changelog

All notable changes to Repaste will be documented in this file.

## [1.1.0] - 2026-05-12

### Added
- Carousel scroll sensitivity control (discrete slider, persisted to UserDefaults)
- Settings preview carousel to try sensitivity without opening the picker
- Optional haptic feedback when moving between clips (with Settings toggle)

### Changed
- Picker scroll wheel handling shares one code path with the settings preview; delta extraction matches the global shortcut path

## [1.0.0] - 2026-05-10

### Added
- Clipboard history tracking with configurable limit (5–200 items)
- Rotary carousel picker with smooth spring animations
- Custom shortcut recorder (click to record any key combo)
- Shortcut conflict detection for common system shortcuts
- Popup position option: centered on screen or above text cursor
- In-app update checker via GitHub Releases
- Menu bar app with Settings and Clear history
- Accessibility permission onboarding flow
