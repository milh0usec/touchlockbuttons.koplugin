# Contributing

Bug reports and focused pull requests are welcome.

## Before opening an issue

Confirm the problem on the latest release and collect:

- Kindle model and firmware;
- KOReader version;
- controller enabled/disabled state;
- click-window setting;
- `/tmp/touchlockbuttons-power.log`;
- exact reproduction steps.

## Development rules

- Keep the virtual bar lock and full touchscreen lock as independent states.
- Do not introduce composite icons that encode multiple variables.
- Do not bind daemon management to the virtual lock button.
- Preserve a non-touch recovery path whenever the full touchscreen can be disabled.
- Keep the physical controller PW4-specific unless a new device is explicitly tested.

Run before submitting:

```sh
./scripts/validate.sh
./scripts/package.sh
```

## Commit scope

Prefer small commits with one behavioral change. Document user-visible changes in `CHANGELOG.md`.
