#!/usr/bin/env bash
# Жёсткий блок прямой записи в базу мимо утилиты ./hh (требование владельца 27.07).
#
# За день агент трижды полез в screening.db напрямую: при подборе кандидатов (в выборку попал
# человек из чёрного списка), при разборе профиля и при записи журнала отправки (запись потеряна,
# возник риск повторного сообщения кандидату). Уговоры не работают — нужен технический запрет.
#
# Что блокируем: любые ad-hoc команды с INSERT/UPDATE/DELETE/DROP/ALTER по screening.db из консоли.
# Что разрешаем: чтение (SELECT, PRAGMA), запуск скриптов проекта и ./hh — там та же запись идёт
# через код, который прошёл ревизию и тесты.
#
# Вход: JSON от Claude Code на stdin, поле tool_input.command.
# Выход: код 2 = блокировка, текст причины в stderr попадает агенту.

set -uo pipefail
CMD="$(jq -r '.tool_input.command // ""' 2>/dev/null || echo "")"

# Ad-hoc питон/sqlite3 в консоли (python -c, python - <<, sqlite3 file.db "...")
if grep -qiE '(python[0-9.]*|sqlite3)' <<<"$CMD" && \
   grep -qiE '(screening\.db|hhkit\.DB)' <<<"$CMD" && \
   grep -qiE '\b(insert|update|delete|drop|alter|create table)\b' <<<"$CMD"; then
    # Запуск файла проекта — это нормальный путь, там код прошёл ревизию
    if grep -qE '(\./hh |scripts/[a-z_]+\.py|lib/[a-z_]+\.py)( |$)' <<<"$CMD"; then
        exit 0
    fi
    cat >&2 <<'MSG'
ЗАБЛОКИРОВАНО: прямая запись в базу из консоли запрещена.

Работай через утилиту:
  ./hh reply <K-номер> [--record-only]   отправка/фиксация сообщения
  ./hh flag <K-номер> <пауза|risk|снять> решения владельца
  ./hh qualify | cluster | approve       пересчёты и одобрение
Не хватает команды — добавь её в lib/cli.py, а не обходи правило.
MSG
    exit 2
fi
exit 0
