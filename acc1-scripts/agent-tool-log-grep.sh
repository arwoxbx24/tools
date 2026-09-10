#!/bin/bash
# agent-tool-log-grep.sh — safe log search with output guards
# Greps log files without flooding agent context (auto-limit 50 lines).
#
# Usage:
#   agent-tool-log-grep.sh PATTERN FILE [options]
#
# Options:
#   --limit N      max output lines (default: 50)
#   --context N    lines of context around match (grep -C N)
#   --since TIME   filter by time: "1h", "24h", "30m", "7d", or absolute "2026-04-09 10:00"
#   --help, -h     show this help
#
# Examples:
#   agent-tool-log-grep.sh "ERROR" /var/log/syslog
#   agent-tool-log-grep.sh "ECONNREFUSED" /var/log/pm2/app.log --limit 20 --context 2
#   agent-tool-log-grep.sh "failed" /var/log/auth.log --since 1h
#   agent-tool-log-grep.sh "exception" /var/log/app.log --since "2026-04-09 10:00" --limit 30

set +e

DEFAULT_LIMIT=50

# ---- help ----
show_help() {
    sed -n '2,22p' "$0" | sed 's/^# \{0,1\}//'
    exit 0
}

# ---- parse args ----
PATTERN=""
FILE=""
LIMIT=$DEFAULT_LIMIT
CTX_LINES=0
SINCE=""

while [ $# -gt 0 ]; do
    case "$1" in
        --limit)   LIMIT="$2";    shift 2 ;;
        --context) CTX_LINES="$2"; shift 2 ;;
        --since)   SINCE="$2";    shift 2 ;;
        --help|-h) show_help ;;
        -*)
            echo "Unknown option: $1" >&2
            exit 1
            ;;
        *)
            if [ -z "$PATTERN" ]; then
                PATTERN="$1"
            elif [ -z "$FILE" ]; then
                FILE="$1"
            else
                echo "Unexpected argument: $1" >&2
                exit 1
            fi
            shift
            ;;
    esac
done

# ---- validate ----
if [ -z "$PATTERN" ] || [ -z "$FILE" ]; then
    echo "Usage: agent-tool-log-grep.sh PATTERN FILE [--limit N] [--context N] [--since TIME]" >&2
    exit 1
fi

if [ ! -f "$FILE" ]; then
    echo "ERROR: File not found: $FILE" >&2
    exit 1
fi

if [ ! -r "$FILE" ]; then
    echo "ERROR: File not readable: $FILE" >&2
    exit 1
fi

# ---- since: compute ISO8601 cutoff string ----
# Strategy: string comparison on first 19 chars of each line.
# Works correctly for ISO8601 (lexicographic == chronological).
# Falls back to epoch-based awk for classic syslog "Mon DD HH:MM:SS" format.
SINCE_ISO=""
SINCE_EPOCH=0
if [ -n "$SINCE" ]; then
    NOW_EPOCH=$(date +%s)

    case "$SINCE" in
        [0-9]*h)
            HOURS="${SINCE%h}"
            SINCE_EPOCH=$(( NOW_EPOCH - HOURS * 3600 ))
            ;;
        [0-9]*d)
            DAYS="${SINCE%d}"
            SINCE_EPOCH=$(( NOW_EPOCH - DAYS * 86400 ))
            ;;
        [0-9]*m)
            MINS="${SINCE%m}"
            SINCE_EPOCH=$(( NOW_EPOCH - MINS * 60 ))
            ;;
        *)
            # Absolute datetime string "YYYY-MM-DD HH:MM" or similar
            SINCE_EPOCH=$(date -d "$SINCE" +%s 2>/dev/null || echo 0)
            if [ "$SINCE_EPOCH" = "0" ]; then
                echo "WARNING: Could not parse --since value '$SINCE', ignoring time filter" >&2
                SINCE_EPOCH=0
            fi
            ;;
    esac

    if [ "$SINCE_EPOCH" -gt 0 ]; then
        # ISO8601 cutoff string for fast string comparison
        SINCE_ISO=$(date -d "@$SINCE_EPOCH" +%Y-%m-%dT%H:%M:%S 2>/dev/null)
    fi
fi

# ---- detect log format from first non-empty line ----
# ISO8601 starts with YYYY-MM-DD — use fast string comparison
# Classic syslog "Mon DD HH:MM:SS" — use epoch-based awk
detect_format() {
    head -20 "$FILE" | grep -v '^$' | head -1
}

# ---- build input pipeline ----
if [ -n "$SINCE_ISO" ]; then
    FIRST_LINE=$(detect_format)
    if echo "$FIRST_LINE" | grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}[T ]'; then
        # ISO8601 format: fast string comparison on first 19 chars
        INPUT_CMD="awk -v c=\"$SINCE_ISO\" 'substr(\$0,1,19) >= c || substr(\$0,1,1) != \"2\"' \"$FILE\""
    else
        # Classic syslog "Apr  9 10:23:45" — epoch-based awk with precomputed tables
        CURRENT_YEAR=$(date +%Y)
        INPUT_CMD="awk -v cutoff=$SINCE_EPOCH -v cur_year=$CURRENT_YEAR '
        BEGIN {
            d = 0
            for (y = 1970; y <= cur_year+1; y++) {
                year_start[y] = d
                leap = (y%4==0 && y%100!=0) || y%400==0
                d += leap ? 366 : 365
            }
            mo_off[1]=0;   mo_off[2]=31;  mo_off[3]=59;  mo_off[4]=90
            mo_off[5]=120; mo_off[6]=151; mo_off[7]=181; mo_off[8]=212
            mo_off[9]=243; mo_off[10]=273; mo_off[11]=304; mo_off[12]=334
            split(\"Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec\", mnames)
            for (i=1; i<=12; i++) mnum[mnames[i]] = i
        }
        function is_leap(y) { return (y%4==0 && y%100!=0) || y%400==0 }
        function to_epoch(yr, mo, dy, hr, mn, sc) {
            extra = (mo > 2 && is_leap(yr)) ? 1 : 0
            d = year_start[yr] + mo_off[mo] + extra + dy - 1
            return d * 86400 + hr * 3600 + mn * 60 + sc
        }
        {
            ts = 0
            if (match(\$0, /^[A-Z][a-z]{2} +[0-9]{1,2} [0-9]{2}:[0-9]{2}:[0-9]{2}/)) {
                s = substr(\$0, RSTART, RLENGTH)
                mn_name = substr(s, 1, 3)
                sub(/^[A-Za-z]+ +/, \"\", s)
                split(s, a, \" \")
                dy = a[1]+0
                split(a[2], t, \":\")
                ts = to_epoch(cur_year+0, mnum[mn_name], dy, t[1]+0, t[2]+0, t[3]+0)
            }
            if (ts == 0 || ts >= cutoff) print
        }' \"$FILE\""
    fi
else
    INPUT_CMD="cat \"$FILE\""
fi

# ---- build grep options ----
GREP_OPTS="-E"
if [ "$CTX_LINES" -gt 0 ] 2>/dev/null; then
    GREP_OPTS="$GREP_OPTS -C $CTX_LINES"
fi

# ---- execute: count then display with limit ----
TOTAL=$(eval "$INPUT_CMD" | grep $GREP_OPTS -- "$PATTERN" 2>/dev/null | wc -l)

if [ "$TOTAL" -eq 0 ]; then
    echo "No matches found for pattern: $PATTERN"
    [ -n "$SINCE" ] && echo "(time filter: --since $SINCE)"
    exit 0
fi

# Print up to LIMIT lines
eval "$INPUT_CMD" | grep $GREP_OPTS -- "$PATTERN" 2>/dev/null | head -n "$LIMIT"

# Show truncation notice if needed
if [ "$TOTAL" -gt "$LIMIT" ]; then
    REMAINING=$(( TOTAL - LIMIT ))
    echo ""
    echo "... $REMAINING more line(s) not shown (total: $TOTAL, limit: $LIMIT)"
    echo "    Use --limit N to see more"
fi

echo ""
echo "--- grep summary: pattern='$PATTERN' file='$FILE' matched=$TOTAL shown=$(( TOTAL < LIMIT ? TOTAL : LIMIT )) ---"
