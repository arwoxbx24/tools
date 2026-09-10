#!/usr/bin/env bash
# project-registry-watcher.sh
# Keeps Redis hash projects:registry in sync with /root/claude-projects/ top-level dirs
# PM2-supervised via /root/workspaces/tools/acc1-scripts/ecosystem/project-registry.config.js

set -uo pipefail

PROJECTS_ROOT="/root/claude-projects"
CLIENTS_DIR="${PROJECTS_ROOT}/clients"
LOG_FILE="/root/workspaces/tools/acc1-scripts/logs/project-registry-watcher.log"
DEBOUNCE_SECS=2

log() {
  echo "[$(date '+%Y-%m-%dT%H:%M:%S')] $*" | tee -a "${LOG_FILE}"
}

# --------------------------------------------------------------------------
# do_scan: build desired state, push to Redis, prune stale keys
# --------------------------------------------------------------------------
do_scan() {
  log "Starting full scan..."

  declare -A new_registry

  # --- Special hardcoded entry: teamlead ---
  if [ -d "${PROJECTS_ROOT}/.teamlead-agent" ]; then
    new_registry["teamlead"]="${PROJECTS_ROOT}/.teamlead-agent"
  fi

  # --- Top-level directories ---
  while IFS= read -r -d '' entry; do
    base=$(basename "${entry}")

    # Skip prefixes and well-known non-project names
    case "${base}" in
      .*|_*|temp-*|.t-*|_dead|node_modules|state|runtime|clients) continue ;;
    esac

    # Include only if .git dir or CLAUDE.md file exists
    if [ -d "${entry}/.git" ] || [ -f "${entry}/CLAUDE.md" ]; then
      new_registry["${base}"]="${entry}"
    fi
  done < <(find "${PROJECTS_ROOT}" -mindepth 1 -maxdepth 1 -type d -print0 2>/dev/null)

  # --- clients/* subdirectories ---
  if [ -d "${CLIENTS_DIR}" ]; then
    while IFS= read -r -d '' entry; do
      base=$(basename "${entry}")

      # Skip hidden / prefixed dirs
      case "${base}" in
        .*|_*|temp-*|.t-*) continue ;;
      esac

      if [ -d "${entry}/.git" ] || [ -f "${entry}/CLAUDE.md" ]; then
        new_registry["${base}"]="${entry}"
      fi
    done < <(find "${CLIENTS_DIR}" -mindepth 1 -maxdepth 1 -type d -print0 2>/dev/null)
  fi

  # --------------------------------------------------------------------------
  # Sync to Redis
  # --------------------------------------------------------------------------

  # Get current keys in registry
  mapfile -t existing_keys < <(redis-cli HKEYS projects:registry 2>/dev/null || true)

  # Add/update entries
  local count=0
  for key in "${!new_registry[@]}"; do
    path="${new_registry[${key}]}"
    redis-cli HSET projects:registry "${key}" "${path}" >/dev/null
    redis-cli HSET projects:paths "${path}" "${key}" >/dev/null
    (( count++ )) || true
  done

  # Remove stale entries from registry
  for key in "${existing_keys[@]}"; do
    if [ -z "${key}" ]; then continue; fi
    if [[ -z "${new_registry[${key}]+x}" ]]; then
      # Key no longer present on disk — get old path for reverse cleanup
      old_path=$(redis-cli HGET projects:registry "${key}" 2>/dev/null || true)
      redis-cli HDEL projects:registry "${key}" >/dev/null
      if [ -n "${old_path}" ]; then
        redis-cli HDEL projects:paths "${old_path}" >/dev/null
      fi
      log "Removed stale key: ${key}"
    fi
  done

  log "Scan complete. Registry contains ${count} entries."
}

# --------------------------------------------------------------------------
# Initial scan on startup
# --------------------------------------------------------------------------
log "project-registry-watcher starting (PID $$)"
do_scan

# --------------------------------------------------------------------------
# inotify watch loop with 2-second debounce
# --------------------------------------------------------------------------
log "Starting inotify watch on ${PROJECTS_ROOT} and ${CLIENTS_DIR}"

DEBOUNCE_FILE=$(mktemp /tmp/prw-debounce.XXXXXX)
trap 'rm -f "${DEBOUNCE_FILE}"' EXIT

inotifywait -m -q \
  -e create -e delete -e moved_to -e moved_from \
  --format '%e %w%f' \
  "${PROJECTS_ROOT}" \
  "${CLIENTS_DIR}" 2>/dev/null | \
while IFS= read -r event_line; do
  log "Event: ${event_line}"
  # Touch debounce file to signal pending rescan
  touch "${DEBOUNCE_FILE}"

  # Sleep 2s debounce — wait until no new events for 2 seconds
  # We use a background rescan trigger approach:
  # After touching, a separate check runs after 2s
  (
    sleep 2
    # Only run if debounce file still exists and is recent (modified within last 3s)
    if [ -f "${DEBOUNCE_FILE}" ]; then
      mod_time=$(stat -c %Y "${DEBOUNCE_FILE}" 2>/dev/null || echo 0)
      now=$(date +%s)
      age=$(( now - mod_time ))
      if [ "${age}" -le 3 ]; then
        do_scan
      fi
    fi
  ) &
done
