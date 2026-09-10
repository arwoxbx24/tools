#!/bin/bash
# Generate project-specific CLAUDE.md
PROJECT_DIR="$1"
PROJECT_TYPE="${2:-unknown}"
PROJECT_NAME=$(basename "$PROJECT_DIR")
OUTPUT="$PROJECT_DIR/CLAUDE.md"

[ -f "$OUTPUT" ] && echo "CLAUDE.md already exists" && exit 0

cat > "$OUTPUT" << TEMPLATE
# Project: $PROJECT_NAME

## ⛔ MANDATORY FIELDS (Agent MUST fill before work)

### Stack Information
- **Language:** $PROJECT_TYPE
- **Framework:** [FILL: Laravel/Django/Express/FastAPI/etc]
- **Database:** [FILL: MySQL/PostgreSQL/SQLite/Redis/none]

### Library/SDK
- **Main library:** [FILL: e.g., python-telegram-bot, axios, guzzle]
- **Why chosen:** [FILL: reasoning for this choice]
- **Version:** [FILL: exact version from package.json/requirements.txt]

### How to Run
- **Dev:** [FILL: npm run dev / python main.py / php artisan serve]
- **Prod:** [FILL: pm2 start / systemd / docker]
- **Test:** [FILL: npm test / pytest / phpunit]

### Environment Variables
- **Required:** [FILL: API_KEY, DATABASE_URL, etc]
- **Optional:** [FILL: DEBUG, LOG_LEVEL, etc]

### Port Assignment
- **Port:** [FILL: number >20000]
- **PM2 name:** [FILL: process name for pm2]

---

## Type Checking
- **Strict mode:** [FILL: enabled/disabled]
- **Config file:** [FILL: tsconfig.json / phpstan.neon / mypy.ini / none]

---

## ⛔ FORBIDDEN Patterns
- [FILL: deprecated methods, insecure patterns]

---

## Known Working Parameters
- [FILL: copy-paste ready examples]
TEMPLATE

echo "✅ Generated: $OUTPUT"
