# ТЗ dcfg-demsy.22 — слить origin/main в цепочку disk-rotate .13–.21

Причина: PR #170–#174 в состоянии DIRTY. Ветки .13–.21 стоят на исходном коммите .12 (b870008), а main содержит squash #169 (3b5d941) с тем же деревом (`git diff --stat b870008 3b5d941` пуст).

U1. Ветка `claude/dcfg-demsy.22-merge-main` от `claude/dcfg-demsy.21-backups-before`; `git merge --no-commit --no-ff origin/main`; конфликт `scripts/disk-rotate.sh` решается версией ветки (.21) — она уже содержит изменения .12 из main.

Проверка:
1) `git diff --no-index` файла с версией .21 → пусто
2) `git diff --stat origin/main -- scripts/disk-rotate.sh` → только изменения .13–.21 (84+/3-)
3) `disk-rotate-gate-selfcheck.sh` → PASS 26/26
