#!/bin/bash
# review-incidents.sh — AIRS Incident Review for Prompt Engineer
# Aggregates incidents, shows trends, top violations, recommendations
# Usage: review-incidents.sh [--days 7] [--rule V165] [--top 10]
# Issue: #230

set +e

REDIS_DB=2
REPORTS_DIR="/root/workspaces/tools/acc1-scripts/agent-reports"
DAYS=7
RULE_FILTER=""
TOP_N=10

# Parse args
while [ $# -gt 0 ]; do
    case "$1" in
        --days)  DAYS="$2"; shift 2 ;;
        --rule)  RULE_FILTER="$2"; shift 2 ;;
        --top)   TOP_N="$2"; shift 2 ;;
        --help|-h) echo "Usage: review-incidents.sh [--days N] [--rule VXXX] [--top N]"; exit 0 ;;
        *) shift ;;
    esac
done

rcli() {
    redis-cli -n $REDIS_DB "$@" 2>/dev/null
}

echo "╔══════════════════════════════════════════════════════════╗"
echo "║          AIRS — Incident Review (${DAYS} days)               ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""

# ── COLLECT INCIDENTS FROM REDIS ──
declare -A RULE_COUNTS
declare -A RULE_NAMES
TOTAL_INCIDENTS=0

for i in $(seq 0 $((DAYS - 1))); do
    D=$(date -d "-${i} days" '+%Y-%m-%d' 2>/dev/null || date '+%Y-%m-%d')
    ENTRIES=$(rcli LRANGE "acs:incidents:${D}" 0 -1)
    while IFS= read -r entry; do
        [ -z "$entry" ] && continue
        RULE=$(echo "$entry" | cut -d'|' -f2)
        [ -n "$RULE_FILTER" ] && [ "$RULE" != "$RULE_FILTER" ] && continue
        RULE_COUNTS[$RULE]=$(( ${RULE_COUNTS[$RULE]:-0} + 1 ))
        TOTAL_INCIDENTS=$((TOTAL_INCIDENTS + 1))
    done <<< "$ENTRIES"
done

# Also check incident-count keys for rules not in incidents list
for i in $(seq 0 $((DAYS - 1))); do
    D=$(date -d "-${i} days" '+%Y-%m-%d' 2>/dev/null || date '+%Y-%m-%d')
    while IFS= read -r key; do
        [ -z "$key" ] && continue
        RULE=$(echo "$key" | sed "s/acs:incident-count://; s/:${D}//")
        [ -n "$RULE_FILTER" ] && [ "$RULE" != "$RULE_FILTER" ] && continue
        CNT=$(rcli GET "$key")
        [ -z "$CNT" ] && continue
        if [ "${RULE_COUNTS[$RULE]:-0}" -lt "$CNT" ]; then
            RULE_COUNTS[$RULE]=$CNT
            TOTAL_INCIDENTS=$((TOTAL_INCIDENTS - ${RULE_COUNTS[$RULE]:-0} + CNT))
        fi
    done < <(rcli --scan --pattern "acs:incident-count:*:${D}")
done

# ── RULE NAME LOOKUP ──
get_rule_name() {
    case "$1" in
        V020) echo "File Sharing" ;;
        V025) echo "Directory Limits" ;;
        V101) echo "PM2 Protection" ;;
        V102) echo "Opus Delegation" ;;
        V109) echo "Zero Questions" ;;
        V113) echo "Infrastructure" ;;
        V120) echo "Data Falsification" ;;
        V160) echo "PE Code Ban" ;;
        V162) echo "Anti-Fabrication" ;;
        V165) echo "Sonnet Delegation" ;;
        V168) echo "Rules Access" ;;
        V169) echo "Anti-Bypass" ;;
        V173) echo "Consequence Guard" ;;
        V180) echo "Methodology Required" ;;
        V185) echo "Secrets Path" ;;
        V189) echo "Task Queue" ;;
        V191) echo "Hierarchical Plans" ;;
        *) echo "Unknown" ;;
    esac
}

# ── TREND CALCULATION ──
get_trend() {
    local rule="$1"
    local this_week=0 prev_week=0
    for i in $(seq 0 6); do
        D=$(date -d "-${i} days" '+%Y-%m-%d' 2>/dev/null || date '+%Y-%m-%d')
        CNT=$(rcli GET "acs:incident-count:${rule}:${D}" 2>/dev/null || echo "0")
        [ -z "$CNT" ] && CNT=0
        this_week=$((this_week + CNT))
    done
    for i in $(seq 7 13); do
        D=$(date -d "-${i} days" '+%Y-%m-%d' 2>/dev/null || date '+%Y-%m-%d')
        CNT=$(rcli GET "acs:incident-count:${rule}:${D}" 2>/dev/null || echo "0")
        [ -z "$CNT" ] && CNT=0
        prev_week=$((prev_week + CNT))
    done
    if [ "$this_week" -gt "$((prev_week + 3))" ]; then
        echo "GROWING"
    elif [ "$this_week" -lt "$((prev_week - 3))" ]; then
        echo "DECLINING"
    else
        echo "STABLE"
    fi
}

# ── TOP VIOLATIONS TABLE ──
echo "TOP VIOLATIONS (${DAYS} days):"
echo "────────────────────────────────────────────────────────"
printf "  %-6s  %-22s  %5s  %-10s\n" "RULE" "NAME" "COUNT" "TREND"
echo "────────────────────────────────────────────────────────"

# Sort by count (descending)
SORTED=""
for rule in "${!RULE_COUNTS[@]}"; do
    SORTED="${SORTED}${RULE_COUNTS[$rule]}|${rule}\n"
done

COUNT_SHOWN=0
echo -e "$SORTED" | sort -t'|' -k1 -rn | head -"$TOP_N" | while IFS='|' read -r count rule; do
    [ -z "$rule" ] && continue
    NAME=$(get_rule_name "$rule")
    TREND=$(get_trend "$rule")
    ICON=""
    case "$TREND" in
        GROWING)  ICON="!!" ;;
        DECLINING) ICON="ok" ;;
        STABLE)   ICON="--" ;;
    esac
    printf "  %-6s  %-22s  %5s  %-10s %s\n" "$rule" "$NAME" "$count" "$TREND" "$ICON"
done

echo "────────────────────────────────────────────────────────"
echo "  Total incidents: $TOTAL_INCIDENTS"
echo ""

# ── UNRESOLVED REPORTS ──
echo "UNRESOLVED REPORTS (agent-reports/):"
echo "────────────────────────────────────────────────────────"
REPORT_COUNT=0
if [ -d "$REPORTS_DIR" ]; then
    while IFS= read -r f; do
        [ -z "$f" ] && continue
        FNAME=$(basename "$f")
        [ -n "$RULE_FILTER" ] && ! echo "$FNAME" | grep -q "$RULE_FILTER" && continue
        echo "  $FNAME"
        REPORT_COUNT=$((REPORT_COUNT + 1))
        [ "$REPORT_COUNT" -ge 15 ] && echo "  ... (showing first 15)" && break
    done < <(ls -t "$REPORTS_DIR"/*.md 2>/dev/null)
fi

if [ "$REPORT_COUNT" -eq 0 ]; then
    echo "  (no unresolved reports)"
fi
echo "  Total: $REPORT_COUNT reports"
echo ""

# ── FALSE POSITIVE RATE ──
echo "CLASSIFICATION (${DAYS} days):"
echo "────────────────────────────────────────────────────────"
CLASS_TP=0; CLASS_FP=0; CLASS_UNK=0
for i in $(seq 0 $((DAYS - 1))); do
    D=$(date -d "-${i} days" '+%Y-%m-%d' 2>/dev/null || date '+%Y-%m-%d')
    TP=$(rcli GET "acs:class:true_positive:${D}" 2>/dev/null || echo "0")
    FP=$(rcli GET "acs:class:false_positive:${D}" 2>/dev/null || echo "0")
    UNK=$(rcli GET "acs:class:unknown:${D}" 2>/dev/null || echo "0")
    [ -z "$TP" ] && TP=0; [ -z "$FP" ] && FP=0; [ -z "$UNK" ] && UNK=0
    CLASS_TP=$((CLASS_TP + TP))
    CLASS_FP=$((CLASS_FP + FP))
    CLASS_UNK=$((CLASS_UNK + UNK))
done
CLASS_TOTAL=$((CLASS_TP + CLASS_FP + CLASS_UNK))
if [ "$CLASS_TOTAL" -gt 0 ]; then
    FP_RATE=$((CLASS_FP * 100 / CLASS_TOTAL))
    printf "  True Positive:  %4d  (%d%%)\n" "$CLASS_TP" "$((CLASS_TP * 100 / CLASS_TOTAL))"
    printf "  False Positive: %4d  (%d%%)\n" "$CLASS_FP" "$FP_RATE"
    printf "  Unknown:        %4d  (%d%%)\n" "$CLASS_UNK" "$((CLASS_UNK * 100 / CLASS_TOTAL))"
    echo "  ─────────────────────"
    printf "  Total classified: %d\n" "$CLASS_TOTAL"
    if [ "$FP_RATE" -gt 10 ]; then
        echo "  ⚠ FP rate ${FP_RATE}% > 10% target — hooks need tuning"
    else
        echo "  ✓ FP rate ${FP_RATE}% within 10% target"
    fi
else
    echo "  No classified incidents yet (data starts from next incident)"
fi
echo ""

# ── RECOMMENDATION ──
echo "RECOMMENDATION:"
echo "────────────────────────────────────────────────────────"
if [ ${#RULE_COUNTS[@]} -gt 0 ]; then
    # Find highest count rule
    TOP_RULE=""
    TOP_COUNT=0
    for rule in "${!RULE_COUNTS[@]}"; do
        if [ "${RULE_COUNTS[$rule]}" -gt "$TOP_COUNT" ]; then
            TOP_COUNT=${RULE_COUNTS[$rule]}
            TOP_RULE=$rule
        fi
    done
    TOP_NAME=$(get_rule_name "$TOP_RULE")
    TOP_TREND=$(get_trend "$TOP_RULE")
    echo "  Focus on $TOP_RULE ($TOP_NAME) — $TOP_COUNT incidents, trend: $TOP_TREND"
    if [ "$TOP_TREND" = "GROWING" ]; then
        echo "  Action: URGENT — violations growing, review root cause in reports"
    fi
else
    echo "  No incidents found for the period. System is clean."
fi
echo ""

exit 0
