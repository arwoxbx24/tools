#!/bin/bash
# PDF Export using puppeteer (headless Chrome)
# Source: /root/claude-projects/kp-generate

INPUT_HTML="$1"
OUTPUT_PDF="${2:-output.pdf}"

if [ -z "$INPUT_HTML" ]; then
  echo "Usage: export-pdf.sh <input.html> [output.pdf]"
  exit 1
fi

# Resolve absolute path
INPUT_HTML=$(realpath "$INPUT_HTML")
OUTPUT_PDF=$(realpath "$OUTPUT_PDF" 2>/dev/null || echo "$OUTPUT_PDF")

cd /root/claude-projects/kp-generate/kp-landing/landing 2>/dev/null || cd /tmp

node -e "
const puppeteer = require('puppeteer');
(async () => {
  const browser = await puppeteer.launch({
    headless: 'new',
    args: ['--no-sandbox', '--disable-setuid-sandbox']
  });
  const page = await browser.newPage();
  await page.goto('file://$INPUT_HTML', {waitUntil: 'networkidle0'});
  await page.pdf({path: '$OUTPUT_PDF', format: 'A4', printBackground: true});
  await browser.close();
  console.log('PDF created: $OUTPUT_PDF');
})();
"
