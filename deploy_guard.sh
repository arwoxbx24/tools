#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

repo_name_from_url() {
    local url="$1"
    local name="${url##*/}"
    name="${name##*:}"
    name="${name%.git}"
    echo "$name"
}

count_refs() {
    local count=0
    while IFS= read -r line; do
        [[ -n "$line" ]] && count=$((count + 1))
    done
    echo "$count"
}

read_deny_list() {
    deny_list=()
    while IFS= read -r line; do
        if [[ "$line" =~ \| ]]; then
            if [[ "$line" =~ \`([^\`]+)\` ]]; then
                deny_list+=("${BASH_REMATCH[1]}")
            fi
        fi
    done < "$1"
}

if [[ "${DEPLOY_GUARD_SELFTEST:-}" == "1" ]]; then
    exit_code=0

    # Проверка 1: deny-list непуст и содержит stroyremont
    if [[ "${DEPLOY_GUARD_SELFTEST:-}" == "1" ]]; then
        read_deny_list "$DIR/../docs/ACTIONS-ALLOWLIST.md"
        if [[ " ${deny_list[*]} " == *" stroyremont "* ]]; then
            echo "✓ deny-list содержит stroyremont"
        else
            echo "✗ deny-list не содержит stroyremont" >&2
            exit_code=1
        fi
    fi

    # Проверка 2: my-tw-server не в списке
    if [[ "${DEPLOY_GUARD_SELFTEST:-}" == "1" ]]; then
        read_deny_list "$DIR/../docs/ACTIONS-ALLOWLIST.md"
        if [[ " ${deny_list[*]} " != *" my-tw-server "* ]]; then
            echo "✓ my-tw-server не в deny-list"
        else
            echo "✗ my-tw-server в deny-list" >&2
            exit_code=1
        fi
    fi

    # Проверка 3: 4 ref дают блок
    count=$(echo -e "ref1\nref2\nref3\nref4" | count_refs)
    if [[ $count -gt 3 ]]; then
        echo "✓ 4 ref блокируют push"
    else
        echo "✗ 4 ref не блокируют push" >&2
        exit_code=1
    fi

    # Проверка 4: DEPLOY_GUARD_OK=1 снимает блок
    if DEPLOY_GUARD_OK=1 "$DIR/deploy_guard.sh"; then
        echo "✓ DEPLOY_GUARD_OK=1 снимает блок"
    else
        echo "✗ DEPLOY_GUARD_OK=1 не снимает блок" >&2
        exit_code=1
    fi

    # Проверка 5: имя репозитория режется верно
    result1=$(repo_name_from_url "git@github.com:arwoxbx24/stroyremont.git")
    result2=$(repo_name_from_url "https://github.com/arwoxbx24/stroyremont.git")
    if [[ "$result1" == "stroyremont" ]] && [[ "$result2" == "stroyremont" ]]; then
        echo "✓ имя репозитория режется верно"
    else
        echo "✗ имя репозитория режется неверно (got: $result1, $result2)" >&2
        exit_code=1
    fi

    if [[ $exit_code -eq 0 ]]; then
        echo "ОК"
    fi
    exit $exit_code
fi

# Этап 1: DEPLOY_GUARD_OK=1 -> обход
if [[ "${DEPLOY_GUARD_OK:-}" == "1" ]]; then
    echo "обход по разрешению" >&2
    exit 0
fi

# Этап 2: читаем deny-list из docs/ACTIONS-ALLOWLIST.md (только строки таблицы)
read_deny_list "$DIR/../docs/ACTIONS-ALLOWLIST.md"

# Этап 3: имя репозитория из git remote get-url origin
repo_url=$(git remote get-url origin 2>/dev/null || true)
repo_name=$(repo_name_from_url "$repo_url")

for denied in "${deny_list[@]}"; do
    if [[ "$repo_name" == "$denied" ]]; then
        echo "блок: деплойный репозиторий $repo_name" >&2
        echo "обход только по DEPLOY_GUARD_OK=1 от владельца" >&2
        exit 1
    fi
done

# Этап 4: счётчик ref (из stdin, если не tty)
if [[ ! -t 0 ]]; then
    ref_count=$(count_refs)
    if [[ $ref_count -gt 3 ]]; then
        echo "блок: массовый push ($ref_count refs, максимум 3)" >&2
        echo "обход только по DEPLOY_GUARD_OK=1 от владельца" >&2
        exit 1
    fi
fi

exit 0
