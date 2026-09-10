#!/usr/bin/env bash
# agent-tool-pm2-status.sh — PM2 process status viewer (pure bash+jq)
# Usage: agent-tool-pm2-status.sh [--name PROC] [--status STATUS] [--format table|json] [--help]

set -euo pipefail

FILTER_NAME=""
FILTER_STATUS=""
FORMAT="table"

usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Show PM2 process status in table or JSON format.

Options:
  --name PROC       Filter by process name (partial match, case-insensitive)
  --status STATUS   Filter by status: running|stopped|online|errored|launching
  --format FORMAT   Output format: table (default) or json
  --help            Show this help

Default output columns: id, name, status, cpu(%), mem(MB), restarts

Examples:
  $(basename "$0")
  $(basename "$0") --name transcription
  $(basename "$0") --status stopped
  $(basename "$0") --format json
  $(basename "$0") --name api --format json
EOF
  exit 0
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --name)
      FILTER_NAME="${2:-}"
      shift 2
      ;;
    --status)
      FILTER_STATUS="${2:-}"
      shift 2
      ;;
    --format)
      FORMAT="${2:-table}"
      shift 2
      ;;
    --help|-h)
      usage
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage
      ;;
  esac
done

if [[ "$FORMAT" != "table" && "$FORMAT" != "json" ]]; then
  echo "Error: --format must be 'table' or 'json'" >&2
  exit 1
fi

RAW_JSON=$(pm2 jlist 2>/dev/null) || {
  echo "Error: failed to get pm2 process list" >&2
  exit 2
}

JQ_STATUS_FILTER=""
if [[ -n "$FILTER_STATUS" ]]; then
  NORM_STATUS="$FILTER_STATUS"
  [[ "$NORM_STATUS" == "running" ]] && NORM_STATUS="online"
  JQ_STATUS_FILTER="| select((.pm2_env.status | ascii_downcase) == \"${NORM_STATUS}\")"
fi

JQ_NAME_FILTER=""
if [[ -n "$FILTER_NAME" ]]; then
  JQ_NAME_FILTER="| select((.name | ascii_downcase) | contains(\"${FILTER_NAME,,}\"))"
fi

JQ_QUERY="[
  .[]
  | select(.pm2_env.pmx_module != true)
  ${JQ_NAME_FILTER}
  ${JQ_STATUS_FILTER}
  | {
      id: .pm_id,
      name: .name,
      status: .pm2_env.status,
      cpu: (.monit.cpu // 0 | . * 10 | round | . / 10),
      mem_mb: (.monit.memory // 0 | . / 1048576 | . * 10 | round | . / 10),
      restarts: (.pm2_env.restart_time // 0)
    }
]"

PROCESSED=$(echo "$RAW_JSON" | jq "$JQ_QUERY")

COUNT=$(echo "$PROCESSED" | jq 'length')

if [[ "$FORMAT" == "json" ]]; then
  echo "$PROCESSED"
  exit 0
fi

if [[ "$COUNT" -eq 0 ]]; then
  echo "No processes found."
  exit 0
fi

printf "%-5s %-35s %-12s %8s %10s %9s\n" "ID" "NAME" "STATUS" "CPU(%)" "MEM(MB)" "RESTARTS"
printf "%-5s %-35s %-12s %8s %10s %9s\n" "-----" "-----------------------------------" "------------" "--------" "----------" "---------"

while IFS=$'\t' read -r id name status cpu mem_mb restarts; do
  case "$status" in
    online)   status_fmt="\033[32m${status}\033[0m" ;;
    stopped)  status_fmt="\033[33m${status}\033[0m" ;;
    errored)  status_fmt="\033[31m${status}\033[0m" ;;
    *)        status_fmt="\033[36m${status}\033[0m" ;;
  esac

  name_short="${name:0:35}"

  printf "%-5s %-35s %-12b %8s %10s %9s\n" \
    "$id" "$name_short" "$status_fmt" "$cpu" "$mem_mb" "$restarts"
done < <(echo "$PROCESSED" | jq -r '.[] | [.id, .name, .status, .cpu, .mem_mb, .restarts] | @tsv')

echo ""
printf "Total: %d process(es)\n" "$COUNT"
