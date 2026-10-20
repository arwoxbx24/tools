# Data Model: repo-visibility

## Config `config/repo-visibility.json`
| Field | Type | Rule |
|---|---|---|
| `org` | string | `arwoxbx24` |
| `included_minutes` | integer | `2000` |
| `public` | string[] | names allowed to be opened (`tools`, `arwox-v3-src`) |
| `never_public` | string[] | names never opened; wins over `public` |

## Usage line (report)
`<repo> <PUBLIC|PRIVATE|INTERNAL|UNKNOWN> <minutes>` — one per repo with minutes this month, sorted by name.

## Publish states
`refused (never_public | not allowlisted | secrets | scan failed)` → rc 1, no change · `already PUBLIC` → rc 0, no change · `scanned 0 → changed → read back PUBLIC` → rc 0 · `read back not PUBLIC` → rc 1.
