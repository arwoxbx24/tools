#!/usr/bin/env bash
# sandbox-janitor — авто-уборка мусора разработки в /root/workspaces/sandbox
# bd dcfg-jm1nw.39 (владелец 27.09: весь мусор очистить немедленно, всегда, автоматически)
# Usage: sandbox-janitor.sh [--dry-run]
set -euo pipefail

# ── Config (настраивается здесь) ─────────────────────────────────────────
SANDBOX=/root/workspaces/sandbox
FILES_AGE_H=24        # артефакты-файлы верхнего уровня, старше N ч
DIRS_AGE_H=24         # каталоги верхнего уровня, старше N ч
INNER_AGE_MIN=120     # внутренние артефакты, старше N мин (2 ч)
PROC_AGE_S=3600       # процессы, старше N сек (60 мин)
KILL_GRACE_S=5        # TERM, через N сек KILL

# ── Белый список: никогда не удалять ────────────────────────────────────
# По имени (верхний уровень и любой компонент пути)
PROTECTED_NAMES=( .git .agents .claude .codex .repowise .restore opencode \
  hook_outputs goal-control-plane goal-sandbox pilot-sandbox \
  test-ui-chat test-ui-chat-live )
# По содержимому имени (логины и креды не удаляются никогда)
PROTECTED_KEYWORDS=( secret token auth cred login cookie session .env key )

DRY_RUN=false
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=true

deleted=0
kept=0
killed=0
freed_kb=0

# ── Помощники ───────────────────────────────────────────────────────────
mtime() { stat -c %Y -- "$1" 2>/dev/null || echo 0; }

under_sandbox() {
  local rp
  rp=$(realpath -m -- "$1" 2>/dev/null) || return 1
  case "$rp" in
    "$SANDBOX"/*) return 0 ;;
  esac
  return 1
}

# Один компонент пути против белого списка (имя и ключевые слова)
is_protected_seg() {
  local seg="$1" n kw
  for n in "${PROTECTED_NAMES[@]}"; do
    [[ "$seg" == "$n" ]] && return 0
  done
  for kw in "${PROTECTED_KEYWORDS[@]}"; do
    case "$seg" in *"$kw"*) return 0 ;; esac
  done
  return 1
}

# Все компоненты пути свободны от защиты
path_clear() {
  local rel seg
  rel="${1#"$SANDBOX"/}"
  [[ -z "$rel" ]] && return 0
  local -a parts
  IFS='/' read -r -a parts <<< "$rel"
  local i
  for ((i = 0; i < ${#parts[@]}; i++)); do
    seg="${parts[$i]}"
    [[ -z "$seg" ]] && continue
    if is_protected_seg "$seg"; then return 1; fi
  done
  return 0
}

do_del() {
  local p="$1" reason="$2" kb
  kb=$(du -sk -- "$p" 2>/dev/null | awk '{print $1}') || kb=0
  kb=${kb:-0}
  freed_kb=$((freed_kb + kb))
  deleted=$((deleted + 1))
  printf 'DEL %s %s\n' "$p" "$reason"
  if [[ "$DRY_RUN" != true ]]; then
    rm -rf -- "$p"
  fi
}

do_keep() {
  printf 'KEEP %s %s\n' "$1" "$2"
  kept=$((kept + 1))
}

# Есть ли процесс, чей cwd или аргумент относится к пути
proc_active() {
  local p="$1" d t
  for d in /proc/[0-9]*/cwd; do
    [[ -L "$d" ]] || continue
    t=$(readlink -f "$d" 2>/dev/null) || continue
    case "$t" in
      "$p"|"$p"/*) return 0 ;;
    esac
  done
  local cm args
  for cm in /proc/[0-9]*/cmdline; do
    [[ -r "$cm" ]] || continue
    args=$(tr '\0' ' ' < "$cm" 2>/dev/null) || continue
    case "$args" in
      *"$p"*) return 0 ;;
    esac
  done
  return 1
}

# Связанный git worktree (отличен от основного репозитория)
is_git_worktree() {
  local p="$1" gd cd
  gd=$(git -C "$p" rev-parse --git-dir 2>/dev/null) || return 1
  cd=$(git -C "$p" rev-parse --git-common-dir 2>/dev/null) || return 1
  gd=$(realpath -m -- "$gd")
  cd=$(realpath -m -- "$cd")
  [[ -n "$gd" && -n "$cd" && "$gd" != "$cd" ]]
}

# Удалить worktree через основной репозиторий, затем prune
worktree_remove() {
  local p="$1" common main_tl cb
  common=$(git -C "$p" rev-parse --git-common-dir 2>/dev/null) || common=""
  main_tl="$p"
  if [[ -n "$common" ]]; then
    common=$(realpath -m -- "$common")
    cb=$(basename -- "$common")
    if [[ "$cb" == ".git" ]]; then
      main_tl=$(dirname -- "$common")
    fi
  fi
  printf '  worktree-remove: %s (via %s)\n' "$p" "$main_tl"
  if [[ "$DRY_RUN" != true ]]; then
    git -C "$main_tl" worktree remove --force -- "$p"
    git -C "$main_tl" worktree prune
  fi
}

# ── Правило 1/2: файлы-артефакты и каталоги верхнего уровня ─────────────
file_artifact() { # $1 basename
  case "$1" in
    *.md|*.txt|*.json|*.jsonl|*.log|*.out) return 0 ;;
    *-commit*) return 0 ;;
    *pr-body*) return 0 ;;
    code-channel-*) return 0 ;;
    ce-pr-body.*) return 0 ;;
  esac
  [[ "$1" =~ ^\.[0-9a-f]+-00000000\.so$ ]] && return 0
  return 1
}

dir_artifact() { # $1 basename
  case "$1" in
    test-*|code-channel-test.*|*-npm-cache|dr055-*|factcheck-*|verify*|claude-e2e-*) return 0 ;;
    codex-*-channel-tmp) return 0 ;;
  esac
  return 1
}

do_del_dir() {
  local p="$1"
  if is_git_worktree "$p"; then
    local kb
    kb=$(du -sk -- "$p" 2>/dev/null | awk '{print $1}') || kb=0
    kb=${kb:-0}
    freed_kb=$((freed_kb + kb))
    deleted=$((deleted + 1))
    printf 'DEL %s git worktree\n' "$p"
    if [[ "$DRY_RUN" != true ]]; then
      worktree_remove "$p"
    fi
  else
    do_del "$p" "catalog"
  fi
}

top_scan() {
  local now entry base
  now=$(date +%s)
  shopt -s nullglob dotglob
  for entry in "$SANDBOX"/*; do
    [[ -e "$entry" ]] || continue
    base=$(basename -- "$entry")
    under_sandbox "$entry" || continue
    if [[ -f "$entry" ]]; then
      if file_artifact "$base"; then
        if is_protected_seg "$base"; then
          do_keep "$entry" "protected (name)"
        elif (( now - $(mtime "$entry") <= FILES_AGE_H * 3600 )); then
          do_keep "$entry" "age < ${FILES_AGE_H}h"
        else
          do_del "$entry" "session artifact"
        fi
      fi
    elif [[ -d "$entry" ]]; then
      if dir_artifact "$base"; then
        if is_protected_seg "$base"; then
          do_keep "$entry" "protected (name)"
        elif proc_active "$entry"; then
          do_keep "$entry" "process active"
        elif is_git_worktree "$entry" && git -C "$entry" status --porcelain 2>/dev/null | grep -q .; then
          do_keep "$entry" "git worktree dirty"
        elif (( now - $(mtime "$entry") <= DIRS_AGE_H * 3600 )); then
          do_keep "$entry" "age < ${DIRS_AGE_H}h"
        else
          do_del_dir "$entry"
        fi
      fi
    fi
  done
  shopt -u nullglob dotglob
}

# ── Правило 3: вложенные артефакты внутри проектов (глубина <= 4) ───────
inner_scan() {
  local now p age
  now=$(date +%s)
  while IFS= read -r p; do
    [[ -e "$p" ]] || continue
    under_sandbox "$p" || continue
    age=$((now - $(mtime "$p")))
    if (( age <= INNER_AGE_MIN * 60 )); then continue; fi
    if ! path_clear "$p"; then
      do_keep "$p" "protected (name)"
      continue
    fi
    do_del "$p" "inner artifact"
  done < <(find "$SANDBOX" -xdev -mindepth 1 -maxdepth 4 \
      \( -path '*/e2e/shots' \
         -o -path '*/.agent-work/*/shots' \
         -o -path '*/node_modules/.vite' \
         -o -path '*/node_modules/.cache' \
         -o -name '*.tsbuildinfo' \
         -o -name '.tz-*-prefixed.md' \
         -o -name '.beads.gate.lock' \) \
      -print 2>/dev/null)
}

# ── Правило 4: ветки atom/* в test-ui-chat, влитые в master ─────────────
branch_cleanup() {
  local repo="$SANDBOX/test-ui-chat" b
  [[ -d "$repo" ]] || return 0
  git -C "$repo" rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 0
  while IFS= read -r b; do
    [[ -n "$b" ]] || continue
    if git -C "$repo" branch -d "$b" >/dev/null 2>&1; then
      deleted=$((deleted + 1))
      printf 'DEL %s (branch merged into master)\n' "$b"
    else
      do_keep "$b (branch)" "not deletable (worktree/unmerged)"
    fi
  done < <(git -C "$repo" branch --merged master 2>/dev/null \
      | sed 's/^[* ] //' | grep '^atom/' || true)
}

# ── Правило 5: процессы, старше 60 мин, под sandbox ─────────────────────
http_port() {
  local cmd="$1" f
  f=$(awk '{ for (i=1;i<=NF;i++) if ($i ~ /^http\.server$/) { if (i+1<=NF) print $(i+1) } }' <<< "$cmd")
  [[ -n "$f" && "$f" =~ ^[0-9]+$ ]] && { printf '%s\n' "$f"; return 0; }
  printf '8000\n'
}

process_scan() {
  local pid cmd age cwd port match reason under
  for pid in /proc/[0-9]*; do
    pid=${pid#/proc/}
    cmd=$( { tr '\0' ' ' < "/proc/$pid/cmdline"; } 2>/dev/null) || continue
    [[ -n "$cmd" ]] || continue
    match=0; reason=""
    case "$cmd" in
      *"vite preview"*)
        match=1; reason="vite preview" ;;
      *"http.server"*)
        port=$(http_port "$cmd")
        if [[ "$port" != "20101" ]]; then
          match=1; reason="python3 http.server :$port"
        fi ;;
      *"e2e/chat.mjs"*)
        match=1; reason="node e2e/chat.mjs" ;;
      *google-chrome*--headless*)
        match=1; reason="google-chrome --headless" ;;
    esac
    [[ $match -eq 1 ]] || continue
    age=$(ps -o etimes= -p "$pid" 2>/dev/null | tr -d ' ')
    [[ -n "$age" ]] || continue
    if (( age <= PROC_AGE_S )); then continue; fi
    under=0
    cwd=$(readlink -f "/proc/$pid/cwd" 2>/dev/null) || cwd=""
    case "$cwd" in "$SANDBOX"*) under=1 ;; esac
    case "$cmd" in *"$SANDBOX"*) under=1 ;; esac
    [[ $under -eq 1 ]] || continue
    killed=$((killed + 1))
    printf 'KILL %s (%s, pid %s)\n' "$reason" "cmd=$cmd" "$pid"
    if [[ "$DRY_RUN" != true ]]; then
      kill -TERM "$pid" 2>/dev/null || true
      local i=0
      while [[ -d "/proc/$pid" && $i -lt $KILL_GRACE_S ]]; do
        sleep 1; i=$((i + 1))
      done
      [[ -d "/proc/$pid" ]] && kill -KILL "$pid" 2>/dev/null || true
    fi
  done
}

# ── Запуск ──────────────────────────────────────────────────────────────
[[ -d "$SANDBOX" ]] || { printf 'ERROR: %s missing\n' "$SANDBOX" >&2; exit 1; }

if [[ "$DRY_RUN" == true ]]; then
  printf '%s\n' "=== sandbox-janitor DRY-RUN ==="
else
  printf '%s\n' "=== sandbox-janitor ==="
fi

top_scan
inner_scan
branch_cleanup
process_scan

printf 'deleted=%d kept=%d freed=%d\n' "$((deleted + killed))" "$kept" "$freed_kb"
exit 0
