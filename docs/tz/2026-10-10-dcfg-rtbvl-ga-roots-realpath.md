# ТЗ dcfg-rtbvl — ship: убрать шум `realpath: ''` из вывода (git-auto-lib ga_roots)

## U1 — ga_roots молча пропускает вложенный `.git/.git`
Цель (bd dcfg-rtbvl): в выводе ship нет строки `realpath: '': No such file or directory`.

Причина (воспроизведено 10.10): `bin/ship:5` подключает `bin/git-auto-lib`. `ga_roots` ищет `find "$p" -maxdepth 4 -name .git` и находит `<repo>/.git/.git` (на сервере `projects/arwox-v3-src/.git/.git`). Для `wt=<repo>/.git` строка 36 (`--git-common-dir`) успешна, а `--show-toplevel` пуст, и на строке 37 `realpath ""` пишет в stderr. Ветка `continue` верна, лишний только stderr.

Правка, только два файла:
1. `bin/git-auto-lib:37` — у первого `realpath` (аргумент `$(git -C "$wt" rev-parse --show-toplevel 2>/dev/null)`) добавить `2>/dev/null`. Больше в файле ничего не менять.
2. `bin/git-auto-lib-test` — новый случай T10 перед последней строкой `[[ $sum == 14 ]]`:
   ```bash
   # T10: nested .git/.git skipped silently
   mkdir -p "$proj/real/.git/.git"
   err=$(ga_roots 2>&1 >/dev/null)
   names=$(ga_roots 2>/dev/null | cut -f1)
   [[ -z $err ]] && ! grep -qx 'real/.git' <<<"$names" && pass T10 || fail "T10: err=$err"
   ```
   Последнюю строку заменить на `[[ $sum == 15 ]]`.

3. `docs/ship-post-ARCHITECTURE.md` §6 — строка о молчаливом пропуске `<repo>/.git/.git` в `ga_roots` (гейт CI `bin/ship-doc-check`: правка `bin/git-auto-lib` требует правки этой доки).

Не менять: `bin/ship`, `bin/ship-post`, `bin/ship-promote`, `bin/git-sync`, прочие строки `bin/git-auto-lib`.

Паспорт источников:
- `realpath` — GNU coreutils 9.4 (`realpath --version` → `realpath (GNU coreutils) 9.4`). [webfetch] https://www.gnu.org/software/coreutils/manual/html_node/realpath-invocation.html: «Exit status: 0 if all file names were printed without issue. 1 otherwise.» Замер: `realpath ""` → stderr `realpath: '': No such file or directory`, rc 1; `x=$(realpath "" 2>/dev/null)` → rc 1, `x` пуст. Сравнение на строке 37 остаётся ложным, поведение `continue` не меняется.

Критерии:
1. `bash -n bin/git-auto-lib` → rc 0.
2. `bash bin/git-auto-lib-test` → rc 0, в выводе `PASS T10`.
3. До правки строки 37 T10 падает (red), после неё проходит (green).
