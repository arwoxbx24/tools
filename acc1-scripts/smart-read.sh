#!/bin/bash
# SMART-READ: Безопасное чтение файлов с защитой токенов
# Использование: smart-read.sh <file> [filter] [lines]

FILE="$1"
FILTER="${2:-}"
LINES="${3:-50}"
MAX_LINES=500
MAX_SIZE_KB=50

# Цвета
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "╔══════════════════════════════════════════════════════════════╗"
echo "║           SMART-READ — Token Protection System               ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

# Проверка файла
if [ -z "$FILE" ]; then
    echo -e "${RED}❌ Usage: smart-read.sh <file> [filter] [lines]${NC}"
    echo ""
    echo "Examples:"
    echo "  smart-read.sh app.log              # Последние 50 строк"
    echo "  smart-read.sh app.log error        # Строки с 'error'"
    echo "  smart-read.sh app.log error 100    # 100 строк с 'error'"
    exit 1
fi

if [ ! -f "$FILE" ]; then
    echo -e "${RED}❌ File not found: $FILE${NC}"
    exit 1
fi

# Анализ файла
FILE_LINES=$(wc -l < "$FILE" 2>/dev/null || echo "0")
FILE_SIZE=$(du -k "$FILE" 2>/dev/null | cut -f1)
FILE_TYPE=$(file -b "$FILE" | cut -d',' -f1)

echo "📁 File: $FILE"
echo "📊 Lines: $FILE_LINES"
echo "📦 Size: ${FILE_SIZE}KB"
echo "📄 Type: $FILE_TYPE"
echo ""

# Оценка токенов
ESTIMATED_TOKENS=$((FILE_LINES * 10))  # ~10 токенов на строку
echo "💰 Estimated tokens (full read): ~$ESTIMATED_TOKENS"

# Предупреждения
if [ "$FILE_LINES" -gt 10000 ]; then
    echo -e "${RED}🚨 DANGER: File has $FILE_LINES lines!${NC}"
    echo -e "${RED}   Full read would consume ~$ESTIMATED_TOKENS tokens (CONTEXT DEATH!)${NC}"
elif [ "$FILE_LINES" -gt 1000 ]; then
    echo -e "${YELLOW}⚠️ WARNING: Large file ($FILE_LINES lines)${NC}"
elif [ "$FILE_LINES" -gt 500 ]; then
    echo -e "${YELLOW}⚠️ CAUTION: Medium file ($FILE_LINES lines)${NC}"
else
    echo -e "${GREEN}✅ Safe file size${NC}"
fi

echo ""
echo "═══════════════════════════════════════════════════════════════"

# Безопасное чтение
if [ "$FILE_LINES" -gt "$MAX_LINES" ]; then
    echo -e "${YELLOW}📖 Applying smart filtering (max $LINES lines)...${NC}"
    echo ""

    if [ -n "$FILTER" ]; then
        echo "🔍 Filter: '$FILTER'"
        echo "───────────────────────────────────────────────────────────────"
        grep -i "$FILTER" "$FILE" | tail -n "$LINES"
        RESULT_LINES=$(grep -c -i "$FILTER" "$FILE" 2>/dev/null || echo "0")
        echo "───────────────────────────────────────────────────────────────"
        echo "📊 Matched: $RESULT_LINES lines (showing last $LINES)"
    else
        echo "📖 Last $LINES lines:"
        echo "───────────────────────────────────────────────────────────────"
        tail -n "$LINES" "$FILE"
        echo "───────────────────────────────────────────────────────────────"
    fi

    SAVED_TOKENS=$(( (FILE_LINES - LINES) * 10 ))
    echo ""
    echo -e "${GREEN}💰 Tokens saved: ~$SAVED_TOKENS${NC}"
else
    echo -e "${GREEN}📖 File is small, reading fully...${NC}"
    echo "───────────────────────────────────────────────────────────────"
    cat "$FILE"
    echo "───────────────────────────────────────────────────────────────"
fi

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo ""
echo "💡 Tips:"
echo "   smart-read.sh $FILE error      # Filter by 'error'"
echo "   smart-read.sh $FILE exception  # Filter by 'exception'"
echo "   smart-read.sh $FILE '' 100     # Last 100 lines"
