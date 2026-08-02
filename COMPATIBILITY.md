# Compatibility

## Supported target

| Component | Status | Notes |
|---|---|---|
| Kindle Paperwhite 4 (10th generation) | Target device | Physical controller is designed for this device |
| Kindle firmware 5.14.2 | Development target | Other firmware versions may map input devices differently |
| KOReader 2026.07.1 | Recommended | Source/API review performed against this release |
| Reflowable documents | Supported by design | Bottom margin is recalculated |
| Fixed-layout documents | Supported by design | Visible area is recalculated |

## Unsupported or unverified

- Kindle Paperwhite 5 and newer models
- Kindle Oasis, Basic, Scribe, Voyage, and legacy Paperwhite models
- Kobo, PocketBook, Android, desktop, and other KOReader platforms
- Any device where the Power button is not `/dev/input/event1`, key code `116`

The virtual bar may be portable to other KOReader devices, but the physical-button daemon is not. Do not enable the Power controller on an unverified model.

## KOReader API notes

The plugin uses `UIManager:setIgnoreTouchInput()` when available and retains an event-based fallback. It also integrates with ReaderView and ReaderFooter internals to reserve layout space. Those internal APIs may change in later KOReader releases; report regressions with the exact KOReader version.
