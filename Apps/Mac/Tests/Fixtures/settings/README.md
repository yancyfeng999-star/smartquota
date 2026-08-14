# Settings fixtures (P1 baseline)

Reusable JSON fixtures for migration, recovery, and settings-store tests.

**Rules**

- Copy into a **temporary directory** before use. Never point stores at these files for write tests without copying first.
- Never read or write the user's real `~/.smartquota`.
- Fixtures must not contain API keys, tokens, cookies, passwords, or Keychain material.

| File | Purpose |
|------|---------|
| `old-fields-settings.json` | Sparse / pre-schema fields still read by current code (`app.overviewMode` legacy naming, minimal provider map). |
| `unknown-fields-settings.json` | Known fields plus unknown keys that must be preserved on read/write/migration. |
| `corrupted-settings.json` | Invalid JSON; load must fail soft and must not clobber the original on recovery paths. |
| `empty-settings.json` | Zero-byte file; treat as empty dict / missing useful content. |
| `v1-settings.json` | Schema v1 snapshot with a future field that must survive the v1→v2 step. |
