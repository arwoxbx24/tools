# ТЗ dcfg-hr9he — tmux-send: окно с точкой в имени и цель-индекс адресуются точно

## U1 — разрешение цели в window_id
Причина (bd dcfg-hr9he): tmux читает `.` в `-t cd-forms.arwox` как разделитель окно.панель → «can't find pane: arwox»; цель `0` без сессии tmux разрешил не в окно 0 сессии `cl`, текст ушёл в cl:5.

Решение (ADR: разрешить цель до send-keys по точному совпадению; KISS), правка только `bin/tmux-send` и `bin/tmux-send-test`:
1. В `bin/tmux-send` после проверки пустой цели добавить разрешение. Цель вида `%N` или `@N` (pane/window id) — без изменений. Иначе: `sess` = часть до первого `:` (если `:` есть), `win` = остаток. Список `t list-windows -a -F '#{session_name}	#{window_index}	#{window_name}	#{window_id}'`. Кандидаты: (`sess` пуст или равен session_name) и `win` == window_name. Нет по имени → кандидаты по `win` == window_index. Ровно один кандидат → `target` = его window_id. Больше одного → `tmux-send: ambiguous target <target>` в stderr, rc 2. Ноль → цель без изменений (панели вида `cl:1.0` работают как раньше).
2. Сообщения и коды остальные не менять.

Тест `bin/tmux-send-test`, новые проверки 6 и 7 (итог `PASS N/7`):
- 6: окно `cd-forms.arwox` (`new-window -d -n cd-forms.arwox 'cat'`), `tmux-send 't:cd-forms.arwox' 'DOT-1' --expect 'DOT-1'` → rc 0, `capture-pane -p -t <window_id>` содержит `DOT-1`.
- 7: `tmux-send 't:0' 'echo IDX-7' --expect '^IDX-7$'` → rc 0 и `IDX-7` в панели окна 0, не в окне `cat`.
Прочие проверки не ослаблять.

Запреты: только два файла и этот ТЗ. Без `--force`, `reset --hard`, `rm -rf` вне `/tmp`. KISS, YAGNI.

Критерии:
1. `bash -n bin/tmux-send` → rc 0.
2. `bash bin/tmux-send-test` → `PASS 7/7`, rc 0.
3. `python3 tests/test_agent_tools.py` → OK.

## Уточнение 1 (замер после первого прогона)
`bash bin/tmux-send-test` → `PASS 6/7`, `FAIL 6: rc=2`. В самом тесте `display -p -t "t:cd-forms.arwox" '#{window_id}'` вернул `@0` — tmux сам неверно разбирает точку, брать window_id так нельзя: взять его из `list-windows -F '#{window_name} #{window_id}'` по точному имени. Найти, почему `tmux-send 't:cd-forms.arwox'` даёт rc 2 (вывести stderr `$e` при отладке), исправить в `bin/tmux-send`. Итог: `PASS 7/7`.

## Уточнение 2 (замер главного агента, 09.10 21:55)
Разрешение цели в `bin/tmux-send` работает: трасса (`SHELLOPTS=xtrace BASH_XTRACEFD=7`) показала `windows='t 0 bash @0 / t 1 cat @1 / t 2 cd-forms.arwox @2'` → `target=@2` → `send-keys -t @2` → под трассой `PASS 7/7`. Без трассы стабильно `FAIL 6: rc=2` (3 из 3) — гонка по времени: окно `cat` только создано. Вывести `$e` проверки 6, найти, какая команда tmux падает (rc 2 = `die`), устранить гонку (ожидание готовности панели в тесте, не ослабляя проверку). Итог: `PASS 7/7` трижды подряд.

## Уточнение 3 — Уточнение 2 неверно; причина доказана (главный агент, 10.10)
Ошибка: было «гонка по времени, под трассой PASS 7/7» — факт: при `SHELLOPTS=xtrace` текст трассы (содержит `DOT-1`) попал в панель окна и дал ложный PASS. Гонки нет.

Факт (трасса через `BASH_XTRACEFD`, вызов `tmux -L tmux-send-test-1731162 list-windows -a` внутри `tmux-send` на проверке 6): на тестовом сервере две сессии — `cl` (окна `0..3,5 cat`, `4 cd-forms.arwox @7`) и `t` (`0 bash @0`, `1 cat @1`). Окно `cd-forms.arwox` создано тестом без `-t` и попало в сессию `cl`; цель `t:cd-forms.arwox` даёт 0 совпадений → `send-keys -t t:cd-forms.arwox` → ошибка tmux → rc 2. Сессия `cl` на тестовом сокете — восстановление tmux-continuum: `/root/.tmux.conf:283,294` (`@continuum-restore 'on'`), `:300` (`run tpm`); тестовый `new-session` без `-f` грузит этот конфиг; файл `~/.local/share/tmux/resurrect/last` содержит 7 окон сессии `cl`. `bin/tmux-send` работает верно — не менять.

Исправление только в `bin/tmux-send-test`:
1. строка 23: `tmux -L "$srv" -f /dev/null new-session -d -s t -x 80 -y 24` — сервер без пользовательского конфига, плагинов и хуков;
2. строки 37 и 45: `new-window -d -t t: -n …` — окно явно в сессию `t`;
3. строка 47: `list-windows -t t -F …`.

Больше ничего не менять. Итог: `bash bin/tmux-send-test` → `PASS 7/7` три раза подряд; критерии U1 без изменений.
