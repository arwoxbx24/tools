# CLI contract: bin/repo-visibility

```
usage: repo-visibility publish <repo> | report
```

| Call | stdout (exact lines) | rc |
|---|---|---|
| `--help`, `-h` | `usage: …` | 0, no external call |
| no args / unknown | usage on stderr | 2 |
| `publish X`, X in never_public | `refused: X is never_public` | 1 |
| `publish X`, X not in public | `refused: X not in public allowlist` | 1 |
| `publish X`, already PUBLIC | `X: PUBLIC` | 0 |
| `publish X`, findings N > 0 | `secrets: N`, `refused: X has secrets in history` | 1 |
| `publish X`, scanner error | `refused: X scan failed` | 1 |
| `publish X`, clean | `secrets: 0`, `X: PUBLIC` | 0 |
| `publish X`, read-back not PUBLIC | `secrets: 0`, `failed: X is <VIS>` | 1 |
| `report` | `<repo> <VIS> <min>`…, `private total: <P>/<I>`, `all repos total: <A>/<I>` | 0 |

Overrides for tests: `SECRET_GATE` (default `<bin dir>/secret-gate`), `GITLEAKS` (default `/root/.local/bin/gitleaks`, as in `git-hooks/pre-push:39`); `gh` from PATH.
