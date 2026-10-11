# TZ dcfg-ayus6 — agent-browser 0.39.0 local in tools, no lingering daemon

## U1 — local install + wrapper `bin/agent-browser`
Worktree: /root/workspaces/tools/.worktrees/claude/dcfg-ayus6 (branch claude/dcfg-ayus6-agent-browser). Recon — repowise; index: repowise/CBM checked, missing → `tools/bin/code-memory-enable`.

Facts:
- `npm view agent-browser@0.39.0`: bin `agent-browser` → `./bin/agent-browser.js`; `postinstall: node scripts/postinstall.js`; no optionalDependencies (native binary comes via postinstall).
- `tools/.gitignore` already ignores `vendor/`.
- Node must stay v20.19.4 (do not touch node/nvm). No `npm -g`, no `npx`.
- Playwright Chromium is already on disk under `/root/.cache/ms-playwright/` (chromium-*/chrome-linux/chrome).
- agent-browser docs: daemon starts on the first command and exits after an idle timeout (default 1 h); `--idle-timeout` / `AGENT_BROWSER_IDLE_TIMEOUT_MS` shortens it; `close --all` closes browsers; `--executable-path` / `AGENT_BROWSER_EXECUTABLE_PATH` points to a browser binary.

Steps:
1. Before install: `npm pack agent-browser@0.39.0` into a fresh /tmp dir, read `scripts/postinstall.js`. If it downloads Chrome/Chromium (not only the native agent-browser binary) — install with that download disabled (env var the script itself checks) or `--ignore-scripts` plus the native-binary step done by hand; report which.
2. Install into the shared, git-ignored path: `npm install --prefix /root/workspaces/tools/vendor/agent-browser agent-browser@0.39.0` (exact version).
3. Write wrapper `bin/agent-browser` (bash, executable, in the worktree): `--help` prints usage on stdout, rc 0, no action (tools contract); if `/root/workspaces/tools/vendor/agent-browser/node_modules/.bin/agent-browser` is missing → install it with the step-2 command; export `AGENT_BROWSER_EXECUTABLE_PATH` = newest `/root/.cache/ms-playwright/chromium-*/chrome-linux/chrome` unless already set; export `AGENT_BROWSER_IDLE_TIMEOUT_MS=10000` unless already set; then `exec` the vendor binary with all args.
4. Add one line for `agent-browser` to `TOOLS-REGISTRY.md` in the same style as neighbours.
5. Smoke (one run): write `/tmp/ab-smoke.html` with text `agent-browser smoke ok`; run via the WORKTREE wrapper: `open file:///tmp/ab-smoke.html`, `snapshot`, `close --all` — each rc 0, snapshot contains `agent-browser smoke ok`. Then wait at most 15 s and confirm `pgrep -fa agent-browser` prints nothing; if a daemon survives, report it (do not kill other users' processes).
6. Confirm `npm ls -g agent-browser` is empty and `node --version` is v20.19.4.

Principles: KISS, YAGNI, fail fast; minimal diff.
Forbidden: rm -rf, git commit/push, `npm -g`, changing Node, secrets, `~/.ssh`, `/etc`, editing outside the worktree except the vendor install dir and /tmp.

Acceptance:
1) `bin/agent-browser --version` (worktree) prints 0.39.0.
2) smoke open/snapshot/close rc 0, snapshot contains the page text.
3) `pgrep -fa agent-browser` empty after the run; `npm ls -g agent-browser` empty; `node --version` v20.19.4.

Sources: npm registry `npm view agent-browser@0.39.0` (this session); agent-browser README (github.com/vercel-labs/agent-browser) — idle timeout, `close`, `--executable-path` (quoted in docs/research/2026-10-11-plugin-updates-audit.md, projects repo).
