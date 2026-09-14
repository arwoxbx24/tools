#!/usr/bin/env bash

set -e

HOOK_NAME="ai-review-pre-push"
readonly HOOK_NAME

# Читаем stdin протокола pre-push (local_ref local_sha remote_ref remote_sha)
while read -r local_ref local_sha remote_ref remote_sha; do
    # Только для remote_ref refs/heads/feat/isolation
    if [[ "$remote_ref" != "refs/heads/feat/isolation" ]]; then
        continue
    fi

    # Определяем команду для получения диффа
    local diff_cmd
    if [[ "$remote_sha" == "0000000000000000000000000000000000000000" ]]; then
        # Новая ветка, remote_sha нулевой -> берем весь коммит
        diff_cmd="git show $local_sha"
    else
        # Сравниваем изменения между удаленным и локальным коммитом
        diff_cmd="git diff $remote_sha..$local_sha"
    fi

    # Получаем дифф
    local diff_content
    diff_content="$($diff_cmd 2>/dev/null || echo "")"

    # Проверяем, пустой ли дифф
    if [[ -z "$diff_content" ]]; then
        exit 0
    fi

    # Ограничиваем размер диффа 120000 байт
    local max_size=120000
    local diff_size=${#diff_content}
    if (( diff_size > max_size )); then
        diff_content="$(printf '%s' "$diff_content" | head -c "$max_size")"
        diff_content+=$'\n\n[дифф обрезан]'
    fi

    # Получаем корень git-репозитория
    local repo_root
    repo_root="$(git rev-parse --show-toplevel 2>/dev/null)"

    # Проверяем наличие скрипта провайдера
    local provider_script="${repo_root}/../tools/llm-providers/git_agent.sh"
    if [[ ! -x "$provider_script" ]]; then
        echo "Предупреждение $HOOK_NAME: скрипт провайдера не найден или не исполняемый: $provider_script" >&2
        exit 0
    fi

    # Запускаем ревью: дифф в stdin провайдера
    local review_output
    local provider_rc=0
    review_output="$(echo "$diff_content" | bash "$provider_script" review 2>&1)" || provider_rc=$?

    # Провайдер упал (rc≠0) или вывод пустой -> fail-open
    if [[ $provider_rc -ne 0 || -z "$review_output" ]]; then
        echo "Предупреждение $HOOK_NAME: провайдер ИИ-ревью вернул код $provider_rc или пустой вывод" >&2
        exit 0
    fi

    # Показываем вывод ревью
    echo "$review_output"

    # Ищем вердикт: строка, начинающаяся с "BLOCK"
    if echo "$review_output" | grep -q '^BLOCK'; then
        echo "ИИ-ревью BLOCK — пуш остановлен" >&2
        exit 1
    fi
done

# Если ни один из подходящих remote_ref не найден, разрешаем пуш
exit 0
