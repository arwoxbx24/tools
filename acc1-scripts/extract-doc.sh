#!/bin/bash
# Universal Document Extractor (MarkItDown-based)
# Usage: extract-doc.sh <file> [--ocr] [--extract-images]
set -euo pipefail

show_help() {
    cat << 'EOF'
Usage: extract-doc.sh <file> [options]

Options:
  --ocr             Enable OCR for scanned documents
  --extract-images  Extract images to folder
  --llm             Use Groq LLM for content enhancement
  --help            Show this help

Supported: PDF, DOCX, DOC, XLSX, PPTX, CSV, HTML, images
EOF
}

INPUT=""
OCR=false
EXTRACT_IMAGES=false
LLM=false

for arg in "$@"; do
    case "$arg" in
        --ocr) OCR=true ;;
        --extract-images) EXTRACT_IMAGES=true ;;
        --llm) LLM=true ;;
        --help) show_help; exit 0 ;;
        -*) echo "Unknown option: $arg" >&2; exit 1 ;;
        *) INPUT="$arg" ;;
    esac
done

if [[ -z "$INPUT" ]]; then
    echo "Error: No input file specified" >&2
    show_help
    exit 1
fi

if [[ ! -f "$INPUT" ]]; then
    echo "Error: File not found: $INPUT" >&2
    exit 1
fi

EXT="${INPUT##*.}"
EXT="${EXT,,}"  # lowercase

# Extract images if requested
if [[ "$EXTRACT_IMAGES" == true && "$EXT" == "pdf" ]]; then
    IMGDIR="${INPUT%.*}_images"
    mkdir -p "$IMGDIR"
    pdfimages -all "$INPUT" "$IMGDIR/img" 2>/dev/null || true
    echo "Images extracted to: $IMGDIR" >&2
fi

# Primary: MarkItDown
RESULT=$(markitdown "$INPUT" 2>/dev/null) || RESULT=""

# Fallback for empty PDF results
if [[ -z "$RESULT" && "$EXT" == "pdf" ]]; then
    RESULT=$(pdftotext -layout "$INPUT" - 2>/dev/null) || RESULT=""
fi

# OCR fallback for scanned documents
if [[ -z "$RESULT" && "$OCR" == true ]]; then
    if [[ "$EXT" == "pdf" ]]; then
        # Convert PDF to images and OCR
        TMPDIR=$(mktemp -d)
        pdftoppm -png "$INPUT" "$TMPDIR/page" 2>/dev/null || true
        for img in "$TMPDIR"/*.png; do
            [[ -f "$img" ]] && tesseract "$img" stdout 2>/dev/null
        done > "$TMPDIR/ocr.txt"
        RESULT=$(cat "$TMPDIR/ocr.txt")
        rm -rf "$TMPDIR"
    else
        # Direct OCR for images
        RESULT=$(tesseract "$INPUT" stdout 2>/dev/null) || RESULT=""
    fi
fi

if [[ -z "$RESULT" ]]; then
    echo "Error: Could not extract content from $INPUT" >&2
    exit 1
fi

# Apply LLM enhancement if requested
if [[ "$LLM" == true ]]; then
    GROQ_CLIENT="/root/workspaces/tools/acc1-scripts/scripts/groq-client.sh"
    if [[ -x "$GROQ_CLIENT" ]]; then
        SYSTEM_PROMPT="Analyze and structure this document. Extract key information, headings, and main points. Format as clean markdown. Answer in the same language as the document."

        # Limit text to ~8000 chars (~2000 tokens) for Groq API
        LLM_INPUT="$RESULT"
        if [[ ${#LLM_INPUT} -gt 8000 ]]; then
            LLM_INPUT="${LLM_INPUT:0:8000}..."
            echo "Note: Text truncated to 8000 chars for LLM processing" >&2
        fi

        GROQ_RESULT=$(echo "$LLM_INPUT" | "$GROQ_CLIENT" --stdin "$SYSTEM_PROMPT" 2>&1) || GROQ_RESULT="FALLBACK_MODE"

        if [[ "$GROQ_RESULT" != "FALLBACK_MODE" && -n "$GROQ_RESULT" ]]; then
            RESULT="$GROQ_RESULT"
        else
            echo "Note: Groq LLM unavailable, using raw extraction" >&2
        fi
    else
        echo "Warning: groq-client.sh not found, ignoring --llm flag" >&2
    fi
fi

echo "$RESULT"
