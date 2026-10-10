# ТЗ dcfg-demsy.16 — tests/disk-rotate-selfcheck.sh: инварианты только по TSV-кандидатам

Атом bd dcfg-demsy.16. Дефект: инварианты 2 и 3 ловят отчётные строки `--dry-run` (`hh-scoring-dev size: NNNNM (closed zone)`, `s3:`, `total candidates`, `forecast`), которые меняются между прогонами.
Разведка — repowise; индекс: repowise/CBM проверен, нет — `tools/bin/code-memory-enable`.
Принципы: минимальный дифф; тест не ослаблять — сравниваются те же кандидаты, только без отчётных строк.

Файл: только `scripts/tests/disk-rotate-selfcheck.sh`.

U1. В инвариантах 2 (запретный список) и 3 (идемпотентность) брать из вывода `--dry-run` только строки TSV кандидата: ровно 4 поля через таб (`awk -F'\t' 'NF==4'`).

Запреты: `scripts/disk-rotate.sh` и другие файлы не трогать, git push, сеть.

Проверка:
1) `bash -n scripts/tests/disk-rotate-selfcheck.sh` → rc 0
2) `timeout 590 bash scripts/tests/disk-rotate-selfcheck.sh` → 0 FAILED
3) `git diff --stat` → 1 file changed
