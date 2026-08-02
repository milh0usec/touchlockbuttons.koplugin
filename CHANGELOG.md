# Changelog

All notable changes to this project will be documented in this file. The project follows Semantic Versioning while it remains feasible for the KOReader plugin API.

## [0.1.0] - 2026-08-01

### Added

- Five-segment virtual button bar with previous, bar-lock, touchscreen status, sleep, and next controls.
- Reserved bottom layout that accounts for KOReader's native footer.
- Independent Font Awesome 4 icons for lock, unlock, touch on, touch off, and sleep.
- Optional PW4 Power-button daemon.
- Single-click next page, double-click previous page, and triple-click full touchscreen toggle.
- Configurable 200, 250, or 300 ms click window.
- Mandatory safety warning when enabling the physical controller.
- Touch-lock watchdog and resume recovery.
- English and Brazilian Portuguese documentation.
- Validation, packaging, CI, and tagged-release workflows.

### Changed

- Removed composite SVG state icons.
- Separated the virtual bar lock from the full touchscreen lock.
- Moved daemon management to the settings menu.
- Moved sleep to a dedicated virtual-bar button.
- Removed the deprecated `name` field from `_meta.lua` for current KOReader releases.

### Safety

- The plugin releases the physical controller and reenables touch before requesting sleep.
- Heartbeat loss no longer implicitly reenables the touchscreen.
