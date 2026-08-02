# Security and recovery reports

This plugin intercepts a physical input device and can disable touchscreen input. Treat recovery failures as high-priority defects.

For a public report, remove personal documents and account information from logs. Include only the minimum relevant lines from `/tmp/touchlockbuttons-power.log`.

A report should state:

- device model and firmware;
- KOReader version;
- whether the device could be recovered with triple-click or forced restart;
- whether the Power button remained exclusively grabbed;
- exact steps immediately before the failure.
