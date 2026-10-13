# TZ dcfg-4j1mb v7 M5 — one-line fix, paste only
Reason: real run 13.10: `bd create -t bug` refuses: "missing required sections for bug: ## Acceptance Criteria". The test fake bd did not validate, so tests passed.
File: `bin/ship-post`, function `do_break_glass`, the `printf` text passed to `-d` of the break-glass incident (`bd_home create "[ship-post] break-glass ...` or `bd_cmd create` if not yet renamed).
1. In that printf format string replace `\n\n## Fix spec\n` with `\n\n## Acceptance Criteria\n`. Nothing else.
2. Run `bash -n bin/ship-post`. Output rc and `git diff --stat`.
Forbidden: other files, network.
