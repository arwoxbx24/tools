#!/bin/bash
# tldraw-cli.sh — CLI для программного доступа к tldraw
# Использование: tldraw-cli <command> [args]

SYNC_SERVER="http://localhost:20003"

case "$1" in
  list)
    curl -s "$SYNC_SERVER/api/documents" | jq .
    ;;

  read)
    DOC_ID="${2:-default}"
    curl -s "$SYNC_SERVER/api/documents/$DOC_ID" | jq .
    ;;

  shapes)
    DOC_ID="${2:-default}"
    curl -s "$SYNC_SERVER/api/documents/$DOC_ID" | jq '.shapes'
    ;;

  add-shape)
    DOC_ID="${2:-default}"
    SHAPE_JSON="$3"
    if [ -z "$SHAPE_JSON" ]; then
      echo "Usage: tldraw-cli add-shape <doc_id> '<shape_json>'"
      exit 1
    fi
    curl -s -X POST "$SYNC_SERVER/api/documents/$DOC_ID/shapes" \
      -H "Content-Type: application/json" \
      -d "$SHAPE_JSON" | jq .
    ;;

  add-text)
    DOC_ID="${2:-default}"
    TEXT="$3"
    X="${4:-100}"
    Y="${5:-100}"
    if [ -z "$TEXT" ]; then
      echo "Usage: tldraw-cli add-text <doc_id> '<text>' [x] [y]"
      exit 1
    fi
    SHAPE=$(cat <<EOF
{
  "shapes": [{
    "type": "geo",
    "x": $X,
    "y": $Y,
    "rotation": 0,
    "props": {
      "geo": "rectangle",
      "w": 200,
      "h": 100,
      "text": "$TEXT",
      "color": "black",
      "fill": "solid",
      "size": "m"
    }
  }]
}
EOF
)
    curl -s -X POST "$SYNC_SERVER/api/documents/$DOC_ID/shapes" \
      -H "Content-Type: application/json" \
      -d "$SHAPE" | jq .
    ;;

  add-arrow)
    DOC_ID="${2:-default}"
    FROM_X="${3:-100}"
    FROM_Y="${4:-100}"
    TO_X="${5:-300}"
    TO_Y="${6:-100}"
    SHAPE=$(cat <<EOF
{
  "shapes": [{
    "type": "arrow",
    "x": $FROM_X,
    "y": $FROM_Y,
    "rotation": 0,
    "props": {
      "start": {"type": "point", "x": 0, "y": 0},
      "end": {"type": "point", "x": $(($TO_X - $FROM_X)), "y": $(($TO_Y - $FROM_Y))},
      "color": "black",
      "size": "m"
    }
  }]
}
EOF
)
    curl -s -X POST "$SYNC_SERVER/api/documents/$DOC_ID/shapes" \
      -H "Content-Type: application/json" \
      -d "$SHAPE" | jq .
    ;;

  clear)
    DOC_ID="${2:-default}"
    curl -s -X PUT "$SYNC_SERVER/api/documents/$DOC_ID" \
      -H "Content-Type: application/json" \
      -d '{"shapes":{}}' | jq .
    ;;

  export)
    DOC_ID="${2:-default}"
    FORMAT="${3:-json}"
    curl -s "$SYNC_SERVER/api/documents/$DOC_ID/export?format=$FORMAT"
    ;;

  health)
    curl -s "$SYNC_SERVER/health" | jq .
    ;;

  *)
    echo "tldraw-cli — программный доступ к tldraw"
    echo ""
    echo "Команды:"
    echo "  list                     — список документов"
    echo "  read [doc_id]            — прочитать документ"
    echo "  shapes [doc_id]          — только фигуры документа"
    echo "  add-shape <doc_id> <json>— добавить фигуру (JSON)"
    echo "  add-text <doc_id> <text> [x] [y] — добавить текстовый блок"
    echo "  add-arrow <doc_id> <x1> <y1> <x2> <y2> — добавить стрелку"
    echo "  clear [doc_id]           — очистить документ"
    echo "  export [doc_id] [format] — экспорт (json/tldraw)"
    echo "  health                   — статус сервера"
    ;;
esac
