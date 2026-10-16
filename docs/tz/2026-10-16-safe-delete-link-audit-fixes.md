# TZ dcfg-ii1ih — safe-delete link: close SDK audit C defects

Why: SDK audit C 16.10 on bin/safe-delete `link)` branch (origin/main 9f9e850, lines ~181–212). Principles: KISS, YAGNI, fail fast, minimal diff; the deny list is never narrowed.

## U1 — bin/safe-delete, bin/safe-delete-test
Skills: caveman:surgical-patch (fix in 2 files), ponytail:ponytail (minimal code), superpowers:test-driven-development (each new test fails first, then passes), security-review (deletion safety, forbidden zones)
1. Forbidden zones apply to links too. In the `link)` branch, before the live/dead root checks, run the same refusal the other modes use: call `check_path "$p"` (line 59; segments `secrets hh-scoring .codex .git .beads`, plus whatever else check_path already refuses). If check_path refuses paths that are legal for this mode (e.g. the agents root), apply only its segment/name checks — do not weaken check_path for other modes.
2. Resolve the live root: `lroot=$(realpath -m -- "$lroot")` before the comparison.
3. Checked ledger writes: `log link ... backup-ok || exit 1` before `rm`, and `log link ... deleted || exit 1` after it. After deletion print `восстановить: safe-delete restore $log_n` like the other modes.
4. Restore of a link: add a `link` branch in `restore`: target is column 6 of the ledger line (the `$t` written by `log link "$p" - - "$t" ...`); refuse if `$obj` exists (`-e` or `-L`); `ln -s -- "$t" "$obj" || exit 1`; `log link "$obj" - - "$t" - restored`.
5. Tests in bin/safe-delete-test, under a /tmp live root (`SAFE_DELETE_LIVE_LINK_ROOT`):
   - live link `lr/.git/x -> lr/t` and `lr/secrets/k -> lr/t` → rc 2, link survives;
   - delete a live link, then `safe-delete restore <N>` → link exists again with the same target;
   - ledger not writable (read-only ledger in the test BK) → non-zero rc and the link survives.
   Existing T23/T23b stay green; update the final total.

Files: `bin/safe-delete` `bin/safe-delete-test`
Check: bin/safe-delete-test
