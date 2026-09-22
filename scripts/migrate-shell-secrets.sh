#!/bin/bash
#
# migrate-shell-secrets.sh — переносит секретные присваивания из профиля оболочки
# в отдельный env-файл (права 700/600) и подключает его выше строки раннего
# выхода профиля (spec:054).
#
# Использование:
#   migrate-shell-secrets.sh --profile <путь> --env-file <путь> [--dry-run]
#
# Коды возврата: 0 — перенос выполнен или нечего переносить;
#                1 — ошибка (профиль, синтаксис, env-файл); 2 — ошибка вызова.
#
# Значения секретов никогда не печатаются (ни в выводе, ни в логах,
# ни в сообщениях об ошибке).
set -u

PROFILE=
ENV_FILE=
DRY_RUN=0

usage() {
  cat <<'EOF'
Usage: migrate-shell-secrets.sh --profile <path> --env-file <path> [--dry-run]
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --profile) PROFILE="${2:-}"; shift 2 ;;
    --env-file) ENV_FILE="${2:-}"; shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; exit 2 ;;
  esac
done

if [ -z "$PROFILE" ] || [ -z "$ENV_FILE" ]; then
  usage >&2
  exit 2
fi

if [ ! -f "$PROFILE" ]; then
  echo "error: profile not found: $PROFILE" >&2
  exit 1
fi

SECRET_PATTERN='[0-9]{8,12}:[A-Za-z0-9_-]{34,36}|sk-[A-Za-z0-9_-]{16,}|ghp_[A-Za-z0-9]{20,}|AKIA[0-9A-Z]{16}|AIza[0-9A-Za-z_-]{30,}'

LNO=() NAME=() VAL=()

# discover: заполняет LNO/NAME/VAL строками присваивания, которые являются секретами.
discover() {
  LNO=() NAME=() VAL=()
  local ln=0 work name val issecret line
  while IFS= read -r line || [ -n "$line" ]; do
    ln=$((ln + 1))
    work="$line"
    work="${work#"${work%%[![:space:]]*}"}"   # убрать ведущие пробелы/табы
    if [[ "$work" == "export "* ]]; then
      work="${work#export }"
    fi
    [[ "$work" == *=* ]] || continue
    name="${work%%=*}"
    val="${work#*=}"
    [[ "$name" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || continue
    # Секретом считается только литерал: значение без подстановки команды
    # ($(...) или обратных кавычек) и без ссылки на другую переменную ($…).
    if [ -z "$val" ] \
      || [[ "$val" == *'$('* ]] \
      || [[ "$val" == *'`'* ]] \
      || [ "${val:0:1}" = '$' ]; then
      continue
    fi
    issecret=0
    if [[ "$val" =~ $SECRET_PATTERN ]]; then
      issecret=1
    elif [[ "$name" =~ _(KEY|TOKEN|SECRET|PASSWORD)$ ]]; then
      issecret=1
    fi
    if [ "$issecret" -eq 1 ]; then
      LNO+=("$ln"); NAME+=("$name"); VAL+=("$val")
    fi
  done < "$PROFILE"
}

discover

if [ "${#LNO[@]}" -eq 0 ]; then
  echo "nothing to migrate"
  exit 0
fi

if [ "$DRY_RUN" -eq 1 ]; then
  for i in "${!LNO[@]}"; do
    echo "${NAME[$i]} строка ${LNO[$i]}"
  done
  echo "total ${#LNO[@]}"
  exit 0
fi

# Боевой режим. Сначала проверяем синтаксис профиля до любых правок.
if ! bash -n "$PROFILE"; then
  echo "error: profile has syntax errors" >&2
  exit 1
fi

# (a) окружение env-файла: каталог 700.
ENVDIR="$(dirname "$ENV_FILE")"
if ! mkdir -p "$ENVDIR"; then
  echo "error: cannot create directory $ENVDIR" >&2
  exit 1
fi
chmod 700 "$ENVDIR"

# Временные файлы и единый обработчик очистки на выходе.
TMPE=; TMP1=; TMP2=
trap 'rm -f -- "$TMPE" "$TMP1" "$TMP2"' EXIT

# (b) запись по имени, а не дописыванием: для каждой переменной удалить все
#     существующие строки `^NAME=` (в т.ч. дубли от прошлых отбитых прогонов)
#     и добавить ровно одну. Порядок прочих строк не меняем — повторный запуск
#     после частичного отказа сходится, а не плодит дубликаты.
mapfile -t OLDLINES < "$ENV_FILE" 2>/dev/null || OLDLINES=()
for i in "${!NAME[@]}"; do
  n="${NAME[$i]}"; v="${VAL[$i]}"
  KEPT=()
  for idx in "${!OLDLINES[@]}"; do
    [[ "${OLDLINES[$idx]}" == "$n="* ]] || KEPT+=("${OLDLINES[$idx]}")
  done
  OLDLINES=("${KEPT[@]}" "$n=$v")
done

# Пишем во временный файл рядом с env-файлом (600) и подменяем атомарно.
TMPE="$(mktemp -- "$ENVDIR/.env.XXXXXX")" || exit 1
if [ "${#OLDLINES[@]}" -gt 0 ]; then
  printf '%s\n' "${OLDLINES[@]}" > "$TMPE"
else
  : > "$TMPE"
fi
chmod 600 "$TMPE"
mv -f "$TMPE" "$ENV_FILE"
chmod 600 "$ENV_FILE"

# (c) проверить читаемость и присутствие каждого из перенесённых имён
#     (лишние записи от прошлых прогонов — не ошибка).
if [ ! -r "$ENV_FILE" ]; then
  echo "error: $ENV_FILE is not readable" >&2
  exit 1
fi
for i in "${!NAME[@]}"; do
  CNT="$(grep -c "^${NAME[$i]}=" "$ENV_FILE")"
  if [ "$CNT" -ne 1 ]; then
    echo "error: $ENV_FILE entry for ${NAME[$i]} missing or duplicated" >&2
    exit 1
  fi
done

# (d) удалить исходные секретные строки из профиля (во временный файл).
TMP1="$(mktemp -- "$(dirname "$PROFILE")/.mig.XXXXXX")" || exit 1

SEDARGS=()
for n in "${LNO[@]}"; do
  # Заменяем строку комментарием-заглушкой, а не вырезаем: так структура
  # блоков if/then/fi, case и циклов остаётся корректной в любом случае.
  SEDARGS+=(-e "${n}c\\"$'\n'"  :  # moved to secrets store")
done
sed "${SEDARGS[@]}" "$PROFILE" > "$TMP1"

# (e) если блока подключения к env-файлу нет — вставить выше первой строки
#     раннего выхода.
NEED_INSERT=0
if ! grep -qF -- "$ENV_FILE" "$PROFILE"; then
  NEED_INSERT=1
fi

if [ "$NEED_INSERT" -eq 1 ]; then
  TARGET="$(awk '/\[ -z "\$PS1" \] && return|case \$-[[:space:]]*in/ { print NR; exit }' "$TMP1")"
  if [ -z "$TARGET" ]; then
    TARGET=1
  fi
  TMP2="$(mktemp -- "$(dirname "$PROFILE")/.mig.XXXXXX")" || exit 1
  awk -v target="$TARGET" -v envfile="$ENV_FILE" '
    BEGIN { done = 0 }
    {
      if (!done && NR == target) {
        printf "if [ -r %s ]; then\n", envfile
        print "  set -a"
        printf "  . %s\n", envfile
        print "  set +a"
        print "fi"
        done = 1
      }
      print
    }
  ' "$TMP1" > "$TMP2"
else
  TMP2="$TMP1"
fi

# Синтаксис после правки; при поломке профиль не меняем и завершаемся кодом 1.
if ! bash -n "$TMP2"; then
  echo "error: profile would have syntax errors after migration" >&2
  exit 1
fi

MODE="$(stat -c %a "$PROFILE" 2>/dev/null || echo 644)"
mv -f "$TMP2" "$PROFILE"
chmod "$MODE" "$PROFILE"

echo "migrated ${#NAME[@]} secret(s) to $ENV_FILE"
exit 0
