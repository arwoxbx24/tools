#!/bin/bash
# convert-report.sh — Convert HTML report to various formats
# Usage: convert-report.sh <input.html> <format>
# Formats: pdf, docx, md, odt

set -e

INPUT="$1"
FORMAT="$2"

if [[ -z "$INPUT" || -z "$FORMAT" ]]; then
    echo "Usage: convert-report.sh <input.html> <format>"
    echo "Formats: pdf, docx, md, odt"
    exit 1
fi

if [[ ! -f "$INPUT" ]]; then
    echo "Error: File not found: $INPUT"
    exit 1
fi

OUTPUT="${INPUT%.html}.$FORMAT"

case "$FORMAT" in
    pdf)
        if command -v wkhtmltopdf &> /dev/null; then
            wkhtmltopdf --enable-local-file-access "$INPUT" "$OUTPUT"
        else
            pandoc "$INPUT" -o "$OUTPUT"
        fi
        ;;
    docx|doc)
        pandoc "$INPUT" -o "$OUTPUT"
        ;;
    md|markdown)
        pandoc "$INPUT" -t markdown -o "$OUTPUT"
        ;;
    odt)
        pandoc "$INPUT" -o "$OUTPUT"
        ;;
    *)
        echo "Unsupported format: $FORMAT"
        echo "Supported: pdf, docx, md, odt"
        exit 1
        ;;
esac

echo "✅ Created: $OUTPUT"
