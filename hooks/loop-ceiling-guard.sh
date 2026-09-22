#!/usr/bin/env bash
# PreToolUse/Bash: цикл ожидания без потолка запрещён.
# Причина (24.08): until/while без ограничителя переживает сессию и блокирует выход владельца.
# Два случая за сутки: 11ч (оркестратор) и 12ч (соседняя сессия).
# FAIL-OPEN: любой сбой -> exit 0.
set -u
IN=$(cat 2>/dev/null) || exit 0
CMD=$(printf '%s' "$IN" | jq -r '.tool_input.command // ""' 2>/dev/null) || exit 0
[ -z "$CMD" ] && exit 0
printf '%s' "$CMD" | grep -qE '\b(until|while)\b' || exit 0
# потолок засчитывается: timeout N, счётчик итераций, ограничение -ge/-lt
printf '%s' "$CMD" | grep -qE 'timeout [0-9]|-ge [0-9]|-lt [0-9]|\+\+|n=\$\(\(n' && exit 0
R='ЦИКЛ БЕЗ ПОТОЛКА ЗАПРЕЩЁН (правило 24.08). until/while без ограничителя переживает сессию и блокирует выход владельца — два случая за сутки, 11ч и 12ч. Добавь потолок: timeout 600 <команда>, либо счётчик: n=0; until <условие> || [ $n -ge 40 ]; do sleep 15; n=$((n+1)); done'
jq -nc --arg r "$R" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}' 2>/dev/null || exit 0
exit 0
