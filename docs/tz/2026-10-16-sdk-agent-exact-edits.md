# TZ dcfg-vt31j — sdk-agent code mode: exact edits instead of full-file rewrite

Why (owner 16.10: speed up architecturally): `bin/sdk-agent` line ~321 asks the model for the FULL new content of every changed file. A one-line fix in a ~250-line file means the whole file is generated: slow, costly, and the model alters lines nobody asked for (dcfg-8kv99: check 53 changed unrequested).
Index: repowise/CBM checked; one bash file + its test. Principles: KISS, YAGNI, fail fast, minimal diff; keep every existing guard (listed paths, symlink/denylist check, realpath under WT_REAL, Check: handling, budget, daily cap).

## U1 — bin/sdk-agent, bin/sdk-agent-test
Skills: caveman:surgical-patch (2 files), ponytail:ponytail (minimal code), superpowers:test-driven-development (new offline cases), security-review (trust boundary: model output → files on disk)
1. `CODE_SCHEMA` (line ~18): replace `files[{path,content}]` with `edits[{path,old,new}]` (all strings, all required).
2. Prompt line (~321): "Return only exact edits as JSON {\"edits\":[{\"path\":...,\"old\":...,\"new\":...}]}. `old` is an exact, unique fragment of the current file (include enough surrounding lines to be unique); `new` replaces it. To create a new file use old \"\" (only when the file does not exist). Do not touch lines the task does not ask for. Use only the paths listed above."
3. Apply step (replaces the full-content write loop, keeps the existing path guards per edit): first validate ALL edits — type check (object, three strings), path is a listed path, realpath under `$WT_REAL`; for old ≠ "": the current file content (with earlier edits of the same file already applied in memory) contains `old` exactly once, else die rc 5 `refused edit: old not unique|not found: <path>`; for old = "": the file must not exist. Only when every edit passes, write each changed file once (temp file in the same directory + mv, keep mode). Nothing is written if any edit fails. Do the matching in jq (string `index`/`indices`, `split`/`join`), no shell glob or sed on model text.
4. Tests in `bin/sdk-agent-test` (offline, no key): a fake engine is not available, so test the apply step through a small function you can call with a prepared JSON result (e.g. `sdk-agent --apply-edits WT JSON_FILE` hidden test entry, only when `SDK_AGENT_TEST=1`): edit applied once → file changed only in that fragment; old not found → rc 5, file unchanged; old found twice → rc 5, file unchanged; two edits where the second fails → rc 5 and the first is not written either.

Files: `bin/sdk-agent` `bin/sdk-agent-test`
