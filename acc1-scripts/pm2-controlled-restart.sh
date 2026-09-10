#!/usr/bin/env bash
set +e

# V101 Controlled PM2 Operations (restart / stop / delete)
# All PM2 lifecycle changes MUST go through this wrapper — never direct pm2 commands.
# Requires methodology-based analysis and justification.
#
# Usage (explicit operation — preferred):
#   pm2-controlled-restart.sh restart <process> <methodology> "<justification>"
#   pm2-controlled-restart.sh stop    <process> <methodology> "<justification>"
#   pm2-controlled-restart.sh delete  <process> <methodology> "<justification>"
#
# Usage (legacy — restart assumed):
#   pm2-controlled-restart.sh <process> <methodology> "<justification>"
#
# Approved methodologies:
#   FMEA, Error-Triage, Risk-Matrix, Root-Cause-Analysis, Pre-mortem, Log-Analysis
#
# Examples:
#   pm2-controlled-restart.sh restart resource-guard Error-Triage \
#     "OOM every 2h confirmed via pm2 show metrics. Restart clears memory pressure."
#   pm2-controlled-restart.sh stop old-worker FMEA \
#     "old-worker decommissioned: replaced by worker-v2. Stopping to free port 4001."
#   pm2-controlled-restart.sh delete old-worker FMEA \
#     "old-worker fully removed after successful migration to worker-v2 verified."

# Detect calling convention: if $1 is an operation keyword use explicit mode
OPERATION="restart"
if [[ "$1" == "restart" || "$1" == "stop" || "$1" == "delete" ]]; then
  OPERATION="$1"
  PROCESS="$2"
  METHODOLOGY="$3"
  JUSTIFICATION="$4"
else
  # Legacy: pm2-controlled-restart.sh <process> <methodology> <justification>
  PROCESS="$1"
  METHODOLOGY="$2"
  JUSTIFICATION="$3"
fi

LOG_FILE="/root/workspaces/tools/acc1-scripts/logs/pm2-restarts.log"
mkdir -p "$(dirname "$LOG_FILE")"

# ===== VALIDATION =====

if [[ -z "$PROCESS" ]]; then
  echo "ERROR: Process name required" >&2
  echo "Usage: pm2-controlled-restart.sh <process> <methodology> <justification>" >&2
  exit 2
fi

if [[ -z "$METHODOLOGY" ]]; then
  echo "ERROR: Methodology required" >&2
  echo "Approved: FMEA, Error-Triage, Risk-Matrix, Root-Cause-Analysis, Pre-mortem, Log-Analysis" >&2
  echo "" >&2
  echo "You MUST analyze the problem BEFORE requesting restart:" >&2
  echo "  1. Check pm2 logs <process> --lines 50" >&2
  echo "  2. Check pm2 show <process> for metrics" >&2
  echo "  3. Identify root cause using chosen methodology" >&2
  echo "  4. Confirm restart is the correct remediation" >&2
  exit 2
fi

if [[ -z "$JUSTIFICATION" ]]; then
  echo "ERROR: Justification required" >&2
  echo "Explain WHY restart is needed based on your analysis (minimum 50 chars)" >&2
  exit 2
fi

# Validate methodology is from approved list
VALID_METHODS="^(FMEA|Error-Triage|Risk-Matrix|Root-Cause-Analysis|Pre-mortem|Log-Analysis)$"
if ! echo "$METHODOLOGY" | grep -qE "$VALID_METHODS"; then
  echo "ERROR: Invalid methodology '$METHODOLOGY'" >&2
  echo "Approved: FMEA, Error-Triage, Risk-Matrix, Root-Cause-Analysis, Pre-mortem, Log-Analysis" >&2
  exit 2
fi

# Validate justification length (minimum 50 chars for meaningful analysis)
JUST_LEN=${#JUSTIFICATION}
if [[ $JUST_LEN -lt 50 ]]; then
  echo "ERROR: Justification too short ($JUST_LEN chars, minimum 50)" >&2
  echo "Provide detailed analysis: what problem, what evidence, why restart solves it" >&2
  exit 2
fi

# Check process exists in PM2
if ! pm2 describe "$PROCESS" &>/dev/null; then
  echo "ERROR: Process '$PROCESS' not found in PM2" >&2
  echo "" >&2
  echo "Available processes:" >&2
  pm2 list 2>&1 >&2
  exit 2
fi

# ===== DUPLICATE DETECTION =====
# Count how many PM2 processes share this name
EXISTING=$(pm2 jlist 2>/dev/null | python3 -c "
import sys,json
count=0
try:
    for p in json.load(sys.stdin):
        if p.get('name')=='$PROCESS': count+=1
except: pass
print(count)
" 2>/dev/null)

if [ "${EXISTING:-0}" -gt 1 ]; then
  echo "ERROR: $EXISTING duplicate PM2 processes named '$PROCESS' detected." >&2
  echo "Clean up duplicates first:" >&2
  echo "  pm2 list | grep $PROCESS   (check IDs)" >&2
  echo "  pm2 delete <id>            (delete extras, keep one)" >&2
  echo "  pm2 save" >&2
  {
    echo "=== PM2 DUPLICATE ABORT ==="
    echo "Timestamp:  $(date -Iseconds)"
    echo "Process:    $PROCESS"
    echo "Duplicates: $EXISTING"
    echo "Action:     ABORTED — clean up duplicates first"
    echo "================================"
    echo ""
  } >> "$LOG_FILE"
  exit 3
fi

# ===== PRE-OPERATION REPORT =====

OP_UPPER=$(echo "$OPERATION" | tr '[:lower:]' '[:upper:]')
echo "╔══════════════════════════════════════════════════╗"
printf "║         V101 CONTROLLED PM2 %-20s  ║\n" "$OP_UPPER"
echo "╚══════════════════════════════════════════════════╝"
echo ""
echo "Operation:     $OPERATION"
echo "Process:       $PROCESS"
echo "Methodology:   $METHODOLOGY"
echo "Justification: $JUSTIFICATION"
echo ""

echo "── Pre-Operation Status ──"
pm2 show "$PROCESS" 2>/dev/null | grep -E "name|status|uptime|restart|memory|cpu|pid" || true
echo ""

# ===== LOG =====

{
  echo "=== PM2 CONTROLLED ${OP_UPPER} ==="
  echo "Timestamp:     $(date -Iseconds)"
  echo "Operation:     $OPERATION"
  echo "Process:       $PROCESS"
  echo "Methodology:   $METHODOLOGY"
  echo "Justification: $JUSTIFICATION"
} >> "$LOG_FILE"

# ===== PRE-DEPLOY VALIDATION (restart only) =====

if [[ "$OPERATION" == "restart" ]]; then
  # Look for a project-specific pre-deploy-validate.sh
  VALIDATE_SCRIPT=""
  # Map known process names to project directories
  case "$PROCESS" in
    transcription-panel)
      VALIDATE_SCRIPT="/root/claude-projects/client-video-transcription/scripts/pre-deploy-validate.sh"
      ;;
  esac

  if [[ -n "$VALIDATE_SCRIPT" && -x "$VALIDATE_SCRIPT" ]]; then
    echo "── Pre-deploy validation ──"
    if ! bash "$VALIDATE_SCRIPT"; then
      echo ""
      echo "ERROR: pre-deploy-validate.sh FAILED — restart blocked" >&2
      echo "Fix the errors above before restarting." >&2
      {
        echo "Result:        BLOCKED (pre-deploy validation failed)"
        echo "================================"
        echo ""
      } >> "$LOG_FILE"
      exit 1
    fi
    echo ""
  fi
fi

# ===== EXECUTE OPERATION =====

echo "── ${OP_UPPER}: $PROCESS ──"

case "$OPERATION" in
  restart)
    OP_OUTPUT=$(pm2 restart "$PROCESS" --update-env 2>&1)
    OP_RC=$?
    ;;
  stop)
    OP_OUTPUT=$(pm2 stop "$PROCESS" 2>&1)
    OP_RC=$?
    ;;
  delete)
    OP_OUTPUT=$(pm2 delete "$PROCESS" 2>&1)
    OP_RC=$?
    ;;
esac

echo "$OP_OUTPUT"

if [[ $OP_RC -ne 0 ]]; then
  echo "" >&2
  echo "WARNING: pm2 $OPERATION exited with code $OP_RC" >&2
  {
    echo "Result:        FAILED (exit code $OP_RC)"
    echo "================================"
    echo ""
  } >> "$LOG_FILE"
  exit 1
fi

# ===== POST-OPERATION VERIFICATION =====

sleep 2
echo ""
echo "── Post-Operation Status ──"
if [[ "$OPERATION" == "delete" ]]; then
  echo "(process deleted — no status available)"
  pm2 list 2>/dev/null | grep -v "$PROCESS" | head -5 || true
else
  pm2 show "$PROCESS" 2>/dev/null | grep -E "name|status|uptime|restart|memory|cpu|pid" || true
fi

# Log success
{
  echo "Result:        SUCCESS"
  echo "================================"
  echo ""
} >> "$LOG_FILE"

echo ""
echo "Done: pm2 $OPERATION '$PROCESS' completed and logged (pm2-restarts.log)"
exit 0
