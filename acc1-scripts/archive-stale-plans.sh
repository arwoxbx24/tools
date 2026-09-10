#!/bin/bash
# archive-stale-plans.sh — Archive old/stale plans from plans/ directory
# Usage: ./archive-stale-plans.sh [--dry-run] [--force]
set +e

PLANS_DIR="/root/workspaces/tools/acc1-scripts/plans"
ARCHIVE_DIR="$PLANS_DIR/archive"
LEGACY_DIR="$ARCHIVE_DIR/legacy"

DRY_RUN=0
FORCE=0

for arg in "$@"; do
    case "$arg" in
        --dry-run) DRY_RUN=1 ;;
        --force)   FORCE=1 ;;
    esac
done

mkdir -p "$ARCHIVE_DIR" "$LEGACY_DIR"

COUNT_ARCHIVED=0
COUNT_LEGACY=0
COUNT_SKIPPED=0

NOW=$(date +%s)

for FILE in "$PLANS_DIR"/*.md; do
    # Skip if no files match
    [[ ! -f "$FILE" ]] && continue

    BASENAME=$(basename "$FILE")

    # Extract STATUS and UPDATED_AT from PLAN_META
    STATUS=$(grep -m1 'STATUS:' "$FILE" 2>/dev/null | awk '{print $2}' | tr -d '[:space:]')
    UPDATED_AT=$(grep -m1 'UPDATED_AT:' "$FILE" 2>/dev/null | awk '{print $2}' | tr -d '[:space:]')

    # ── No PLAN_META: move to legacy ──
    if [[ -z "$STATUS" ]]; then
        if [[ "$DRY_RUN" -eq 1 ]]; then
            echo "[DRY-RUN] Would move to legacy/: $BASENAME (no PLAN_META)"
        else
            mv "$FILE" "$LEGACY_DIR/$BASENAME"
            echo "Moved to legacy/: $BASENAME (no PLAN_META)"
        fi
        COUNT_LEGACY=$(( COUNT_LEGACY + 1 ))
        continue
    fi

    # ── Immediately archive: abandoned or stale ──
    if [[ "$STATUS" == "abandoned" || "$STATUS" == "stale" ]]; then
        if [[ "$DRY_RUN" -eq 1 ]]; then
            echo "[DRY-RUN] Would archive: $BASENAME (STATUS=$STATUS)"
        else
            mv "$FILE" "$ARCHIVE_DIR/$BASENAME"
            echo "Archived: $BASENAME (STATUS=$STATUS)"
        fi
        COUNT_ARCHIVED=$(( COUNT_ARCHIVED + 1 ))
        continue
    fi

    # ── Archive completed: check age or --force ──
    if [[ "$STATUS" == "completed" ]]; then
        SHOULD_ARCHIVE=0

        if [[ "$FORCE" -eq 1 ]]; then
            SHOULD_ARCHIVE=1
        elif [[ -n "$UPDATED_AT" ]]; then
            # Parse UPDATED_AT (ISO format: 2026-03-01T18:49:36)
            FILE_EPOCH=$(date -d "$UPDATED_AT" +%s 2>/dev/null)
            if [[ -n "$FILE_EPOCH" && "$FILE_EPOCH" -gt 0 ]]; then
                AGE_SECONDS=$(( NOW - FILE_EPOCH ))
                THRESHOLD=$(( 48 * 3600 ))
                if [[ "$AGE_SECONDS" -gt "$THRESHOLD" ]]; then
                    SHOULD_ARCHIVE=1
                fi
            else
                # Cannot parse date — archive to be safe
                SHOULD_ARCHIVE=1
            fi
        else
            # No UPDATED_AT — archive to be safe
            SHOULD_ARCHIVE=1
        fi

        if [[ "$SHOULD_ARCHIVE" -eq 1 ]]; then
            if [[ "$DRY_RUN" -eq 1 ]]; then
                echo "[DRY-RUN] Would archive: $BASENAME (STATUS=completed, UPDATED_AT=$UPDATED_AT)"
            else
                mv "$FILE" "$ARCHIVE_DIR/$BASENAME"
                echo "Archived: $BASENAME (STATUS=completed)"
            fi
            COUNT_ARCHIVED=$(( COUNT_ARCHIVED + 1 ))
        else
            AGE_HOURS=$(( AGE_SECONDS / 3600 ))
            echo "Skipped: $BASENAME (STATUS=completed, age=${AGE_HOURS}h < 48h)"
            COUNT_SKIPPED=$(( COUNT_SKIPPED + 1 ))
        fi
        continue
    fi

    # ── All other statuses (active, in_progress, etc.): skip ──
    COUNT_SKIPPED=$(( COUNT_SKIPPED + 1 ))
done

echo ""
echo "Summary: Archived $COUNT_ARCHIVED plans, Legacy $COUNT_LEGACY plans, Skipped $COUNT_SKIPPED plans"
