#!/bin/bash
# CASTLE - Code Analytics Statistics Tokens Lines Economics
# Main report script for daily productivity stats

TODAY=${1:-$(date +%Y-%m-%d)}

echo "╔═══════════════════════════════════════════════════════════════════╗"
echo "║              CASTLE — Code Analytics Statistics                    ║"
echo "║              Tokens Lines Economics Report                         ║"
echo "║                    $TODAY                                     ║"
echo "╠═══════════════════════════════════════════════════════════════════╣"

# Helper to handle nil values
get_val() {
    local val=$(redis-cli -n $1 HGET "$2" "$3" 2>/dev/null)
    [ -z "$val" ] || [ "$val" = "(nil)" ] && val=0
    echo "$val"
}

# Lines (DB 4)
LINES=$(get_val 4 "castle:lines:$TODAY" "total")
FILES=$(get_val 4 "castle:files:$TODAY" "count")
PY=$(get_val 4 "castle:lines:$TODAY" "py")
JS=$(get_val 4 "castle:lines:$TODAY" "js")
TS=$(get_val 4 "castle:lines:$TODAY" "ts")
PHP=$(get_val 4 "castle:lines:$TODAY" "php")
SH=$(get_val 4 "castle:lines:$TODAY" "sh")
GO=$(get_val 4 "castle:lines:$TODAY" "go")
RS=$(get_val 4 "castle:lines:$TODAY" "rs")
HTML=$(get_val 4 "castle:lines:$TODAY" "html")
CSS=$(get_val 4 "castle:lines:$TODAY" "css")

echo ""
echo "📝 СТРОКИ КОДА (Lines of Code)"
echo "───────────────────────────────────────────────────────────────"
printf "   Всего:          %'10d строк\n" "$LINES"
printf "   Файлов:         %'10d\n" "$FILES"
echo ""
echo "   По языкам:"
[ "$PY" -gt 0 ] && printf "     Python:       %'10d\n" "$PY"
[ "$JS" -gt 0 ] && printf "     JavaScript:   %'10d\n" "$JS"
[ "$TS" -gt 0 ] && printf "     TypeScript:   %'10d\n" "$TS"
[ "$PHP" -gt 0 ] && printf "     PHP:          %'10d\n" "$PHP"
[ "$SH" -gt 0 ] && printf "     Shell:        %'10d\n" "$SH"
[ "$GO" -gt 0 ] && printf "     Go:           %'10d\n" "$GO"
[ "$RS" -gt 0 ] && printf "     Rust:         %'10d\n" "$RS"
[ "$HTML" -gt 0 ] && printf "     HTML:         %'10d\n" "$HTML"
[ "$CSS" -gt 0 ] && printf "     CSS:          %'10d\n" "$CSS"

# Tokens (DB 5)
TOKENS_IN=$(get_val 5 "castle:tokens:$TODAY" "input")
TOKENS_OUT=$(get_val 5 "castle:tokens:$TODAY" "output")
CACHE=$(get_val 5 "castle:tokens:$TODAY" "cache")
TOKENS_TOTAL=$((TOKENS_IN + TOKENS_OUT))

echo ""
echo "🔤 ТОКЕНЫ (API Usage)"
echo "───────────────────────────────────────────────────────────────"
printf "   Input:          %'10d tokens\n" "$TOKENS_IN"
printf "   Output:         %'10d tokens\n" "$TOKENS_OUT"
printf "   Cache Read:     %'10d tokens (сэкономлено)\n" "$CACHE"
printf "   Всего:          %'10d tokens\n" "$TOKENS_TOTAL"

# Cost calculation (Opus pricing: $15/M input, $75/M output)
# With cache savings
COST_RAW=$(echo "scale=4; ($TOKENS_IN * 0.015 + $TOKENS_OUT * 0.075) / 1000" | bc 2>/dev/null || echo "0")
COST_SAVED=$(echo "scale=4; ($CACHE * 0.015 * 0.9) / 1000" | bc 2>/dev/null || echo "0")

echo ""
echo "💰 СТОИМОСТЬ (Cost Estimate - Opus 4.5)"
echo "───────────────────────────────────────────────────────────────"
printf "   Сегодня:        \$%'.2f\n" "$COST_RAW"
printf "   Сэкономлено:    \$%'.2f (cache)\n" "$COST_SAVED"

# Efficiency metrics
if [ "$LINES" -gt 0 ] && [ "$TOKENS_OUT" -gt 0 ]; then
    EFFICIENCY=$(echo "scale=2; $LINES * 1000 / $TOKENS_OUT" | bc 2>/dev/null || echo "0")
    echo ""
    echo "📊 ЭФФЕКТИВНОСТЬ"
    echo "───────────────────────────────────────────────────────────────"
    printf "   Строк/1K токенов: %'.1f\n" "$EFFICIENCY"
fi

# AI Summary (optional)
GROQ_SCRIPT="/root/workspaces/tools/acc1-scripts/scripts/castle-groq-analyze.sh"
if [ -x "$GROQ_SCRIPT" ] && [ "$LINES" -gt 100 ]; then
    echo ""
    echo "🤖 AI SUMMARY (Groq)"
    echo "───────────────────────────────────────────────────────────────"
    "$GROQ_SCRIPT" 2>/dev/null | head -5
fi

echo ""
echo "╚═══════════════════════════════════════════════════════════════════╝"
echo "Generated: $(date '+%Y-%m-%d %H:%M:%S MSK')"
