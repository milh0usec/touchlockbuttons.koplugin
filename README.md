# TouchLockButtons for KOReader

An experimental KOReader plugin for the **Kindle Paperwhite 4 (10th generation)**. It adds a reserved five-button bar below the reading area and an optional physical Power-button controller.

> [!WARNING]
> The optional controller takes exclusive control of the Kindle Power button while it is active. Native short-press and long-press Power actions are temporarily unavailable. Read the recovery instructions before enabling it.

## Features

The bottom bar uses five equal segments:

| Position | Control | Action |
|---|---|---|
| 1 | Previous page | Tap: previous page; hold: 10 pages back |
| 2 | Bar lock | Toggles whether gestures outside the bar reach KOReader |
| 3 | Touchscreen indicator | Shows whether the complete touchscreen is enabled or disabled |
| 4 | Sleep | Releases the controller and puts the Kindle to sleep |
| 5 | Next page | Tap: next page; hold: 10 pages forward |

The bar reserves its own layout space instead of covering book text or KOReader's native status bar.

### Optional Power-button controller

When enabled on a supported PW4:

- **One click:** next page
- **Two clicks:** previous page
- **Three clicks:** enable or disable the complete touchscreen
- **Long press:** ignored by the plugin

The full touchscreen state is independent from the virtual bar lock. The center indicator changes between Font Awesome 4 `toggle-on` and `toggle-off`; the bar lock uses `unlock` and `lock`; sleep uses `moon-o`.

## Compatibility

See [COMPATIBILITY.md](COMPATIBILITY.md) for the complete support matrix.

Current target:

- Kindle Paperwhite 4 / 10th generation (PW4)
- Kindle firmware 5.14.2 as the development target
- KOReader 2026.07.1 recommended for the first public release

Other Kindle models and input-event layouts are not supported unless independently verified. The daemon currently expects the Power key at `/dev/input/event1`, key code `116`.

## Installation

1. Download the release asset named `touchlockbuttons.koplugin-vX.Y.Z.zip`.
2. Extract it. The archive contains a folder named `touchlockbuttons.koplugin`.
3. Copy that folder to:

   ```text
   /mnt/us/koreader/plugins/
   ```

4. Fully restart KOReader.
5. Open **Tools → Plugin management** and confirm the plugin is enabled.

Do not copy only the files inside the folder. KOReader requires the directory name to end in `.koplugin`.

## Configuration

Open **Tools → Virtual buttons**.

Available settings:

- **Lock gestures outside the bar by default**
- **Power-button controller (PW4)**
  - Enable physical Power-button support
  - Click latency: 200, 250, or 300 ms
  - Usage hint
  - Current touchscreen status

The warning dialog is shown whenever the physical controller is enabled.

## Recovery and safety

Before disabling the touchscreen, verify that the physical controller is active.

To restore touch input normally, press Power **three times** within the configured click window. If the controller has stopped unexpectedly, its wrapper releases the exclusive input grab and restores the Kindle power-management setting. As a last resort, use the Kindle's normal forced-restart procedure.

The plugin writes controller diagnostics to:

```text
/tmp/touchlockbuttons-power.log
```

Temporary state and command files are stored under `/tmp` and are removed during normal shutdown.

## Troubleshooting

### Custom icons do not appear

Perform a complete KOReader restart after installation or upgrade. The plugin copies its uniquely named SVG files to KOReader's icon search paths and falls back to text labels if installation fails.

### The controller does not start

Check `/tmp/touchlockbuttons-power.log`. The most common causes are:

- unsupported Kindle model;
- a different `/dev/input/event*` assignment;
- insufficient access to the input device;
- missing Kindle `lipc-*` utilities;
- another process already holding an exclusive input grab.

### Touch becomes responsive again after a popup or resume

While full touch lock is active, the plugin monitors KOReader's gesture state and reapplies the lock after automatic popups, screen-saver exit, and resume events.

## Development

The repository root is the plugin directory. For a development installation, clone it directly as:

```text
/mnt/us/koreader/plugins/touchlockbuttons.koplugin
```

Local checks:

```sh
./scripts/validate.sh
./scripts/package.sh
```

The package command creates an installable ZIP and SHA-256 checksum under `dist/`.

## Reporting bugs

Include all of the following:

- Kindle model and firmware;
- KOReader version;
- whether the physical controller was enabled;
- configured click latency;
- exact steps to reproduce;
- relevant lines from `/tmp/touchlockbuttons-power.log`.

## License

Plugin code is licensed under the **GNU Affero General Public License v3.0 or later**. See [LICENSE](LICENSE).

The bundled icon outlines are derived from Font Awesome 4.7.0 and are distributed under the **SIL Open Font License 1.1**. See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) and [LICENSES/OFL-1.1.txt](LICENSES/OFL-1.1.txt).

KOReader, Kindle, Amazon, and Font Awesome are trademarks or projects of their respective owners. This project is not affiliated with or endorsed by them.
