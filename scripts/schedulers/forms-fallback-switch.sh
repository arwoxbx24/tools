#!/usr/bin/env bash
# Build and safely switch the forms fallback block through the Vibe API.
set -uo pipefail

GUARD_STATE_DIR="${GUARD_STATE_DIR:-/root/workspaces/tools/scripts/schedulers/state}"
FALLBACK_PAGE_ID="${FALLBACK_PAGE_ID:-}"
FALLBACK_BLOCK_ID="${FALLBACK_BLOCK_ID:-}"
FALLBACK_API_URL="${FALLBACK_API_URL:-${VIBE_API_URL:-}}"
FALLBACK_SNAPSHOT="${FALLBACK_SNAPSHOT:-$(dirname "${BASH_SOURCE[0]}")/forms-fallback/9116-before.json}"
SECRET_FILE="/root/workspaces/secrets/projects/vibecode.env"
NORMAL_FILE="$GUARD_STATE_DIR/fallback-normal.html"
OUTAGE_FILE="$GUARD_STATE_DIR/fallback-outage.html"

status() { printf '%s\n' "$1"; }

build() {
  local snapshot="${1:-$FALLBACK_SNAPSHOT}"
  mkdir -p "$GUARD_STATE_DIR"
  python3 - "$snapshot" "$NORMAL_FILE" "$OUTAGE_FILE" <<'PY'
import json
import re
import sys
from pathlib import Path

snapshot, normal_path, outage_path = map(Path, sys.argv[1:])
html = json.loads(snapshot.read_text())['data']['html']
outer = re.match(r'<div\b[^>]*\bid=(?:"block9116"|\'block9116\')[^>]*>', html, re.I)
if not outer or not re.search(r'</div>\s*$', html, re.I):
    raise SystemExit('fallback_invalid_snapshot')
normal = re.sub(r'</div>\s*$', '', html[outer.end():], count=1, flags=re.I)
button = re.compile(r'<button\b(?P<attrs>[^>]*\btype=(?P<quote>["\'])submit(?P=quote)[^>]*)>.*?</button>', re.I | re.S)

def replace(match):
    style = re.search(r'\sstyle=(?P<quote>["\']).*?(?P=quote)', match.group('attrs'), re.I | re.S)
    if not style:
        raise SystemExit('fallback_button_without_style')
    return ('<p>Форма работает через резервный канал</p>\n'
            '<a href="https://b24-pne9rr.bitrix24.site/crm_form_yoolu/" '
            'target="_blank" rel="noopener"%s>Оставить заявку</a>' % style.group(0))

outage, count = button.subn(replace, normal)
if count != 3 or '<script' in normal.lower():
    raise SystemExit('fallback_invalid_variant')
normal_path.write_text(normal)
outage_path.write_text(outage)
PY
}

normalise() { # source destination
  python3 - "$1" "$2" <<'PY'
import re
import sys
from pathlib import Path

source, destination = map(Path, sys.argv[1:])
html = source.read_text()
outer = re.match(r'<div\b[^>]*\bid=(?:"block9116"|\'block9116\')[^>]*>', html, re.I)
if outer and re.search(r'</div>\s*$', html, re.I):
    html = re.sub(r'</div>\s*$', '', html[outer.end():], count=1, flags=re.I)
destination.write_text(html)
PY
}

same_sha256() { # left right
  [ "$(sha256sum "$1" | awk '{print $1}')" = "$(sha256sum "$2" | awk '{print $1}')" ]
}

load_api_config() {
  if [ -z "${VIBECODE_API_KEY:-}" ] && [ -r "$SECRET_FILE" ]; then
    # The deployment supplies this file; tests provide a non-secret stub value.
    # ponytail: one fixed secret source; add an explicit secret-path parameter only for another deployment.
    # shellcheck disable=SC1090
    . "$SECRET_FILE"
  fi
  FALLBACK_API_URL="${FALLBACK_API_URL:-${VIBE_API_URL:-}}"
  [ -n "${VIBECODE_API_KEY:-}" ] || { status fallback_missing_api_key; return 1; }
  case "$VIBECODE_API_KEY" in *$'\r'*|*$'\n'*) status fallback_invalid_api_key; return 1 ;; esac
  [ -n "$FALLBACK_API_URL" ] || { status fallback_missing_api_url; return 1; }
  FALLBACK_API_URL="${FALLBACK_API_URL%/}"
}

api_request() { # method path [json-file]
  local method="$1" path="$2" body="${3:-}" http api_key
  : > "$API_RESPONSE"
  api_key=${VIBECODE_API_KEY//\\/\\\\}
  api_key=${api_key//\"/\\\"}
  if [ -n "$body" ]; then
    http=$(printf 'header = "X-API-Key: %s"\n' "$api_key" | curl -sS --max-time 30 -o "$API_RESPONSE" -w '%{http_code}' -X "$method" \
      -K - -H 'Content-Type: application/json' --data-binary "@$body" "$FALLBACK_API_URL$path") || { status fallback_api_network; return 1; }
  else
    http=$(printf 'header = "X-API-Key: %s"\n' "$api_key" | curl -sS --max-time 30 -o "$API_RESPONSE" -w '%{http_code}' -X "$method" \
      -K - "$FALLBACK_API_URL$path") || { status fallback_api_network; return 1; }
  fi
  case "$http" in 2??) ;; *) status "fallback_api_http_$http"; return 1 ;; esac
}

apply() {
  local variant="$1" target previous original readback payload current
  case "$variant" in normal) target="$NORMAL_FILE" ;; outage) target="$OUTAGE_FILE" ;; *) status fallback_invalid_variant; return 2 ;; esac
  [ -n "$FALLBACK_PAGE_ID" ] && [ -n "$FALLBACK_BLOCK_ID" ] || { status fallback_disabled; return 0; }
  build || return $?
  load_api_config || return $?
  API_RESPONSE=$(mktemp "$GUARD_STATE_DIR/forms-fallback-response.XXXXXX")
  previous=$(mktemp "$GUARD_STATE_DIR/forms-fallback-previous.XXXXXX")
  original=$(mktemp "$GUARD_STATE_DIR/forms-fallback-original.XXXXXX")
  readback=$(mktemp "$GUARD_STATE_DIR/forms-fallback-readback.XXXXXX")
  current=$(mktemp "$GUARD_STATE_DIR/forms-fallback-current.XXXXXX")
  payload=$(mktemp "$GUARD_STATE_DIR/forms-fallback-payload.XXXXXX")
  trap 'rm -f "$API_RESPONSE" "$previous" "$original" "$readback" "$current" "$payload"' EXIT
  api_request GET "/v1/pages/$FALLBACK_PAGE_ID/blocks/$FALLBACK_BLOCK_ID/content" || return $?
  jq -erj '.data.html' "$API_RESPONSE" > "$previous" || { status fallback_invalid_read; return 1; }
  cp -f "$previous" "$original"
  normalise "$previous" "$current"
  if ! same_sha256 "$current" "$NORMAL_FILE" && ! same_sha256 "$current" "$OUTAGE_FILE"; then
    status fallback_foreign_draft
    return 1
  fi
  jq -n --rawfile content "$target" '{content:$content}' > "$payload"
  api_request PATCH "/v1/pages/$FALLBACK_PAGE_ID/blocks/$FALLBACK_BLOCK_ID" "$payload" || return $?
  api_request GET "/v1/pages/$FALLBACK_PAGE_ID/blocks/$FALLBACK_BLOCK_ID/content" || return $?
  jq -erj '.data.html' "$API_RESPONSE" > "$readback" || { status fallback_invalid_readback; return 1; }
  normalise "$readback" "$current"
  if ! same_sha256 "$current" "$target"; then
    jq -n --rawfile content "$original" '{content:$content}' > "$payload"
    api_request PATCH "/v1/pages/$FALLBACK_PAGE_ID/blocks/$FALLBACK_BLOCK_ID" "$payload" >/dev/null || true
    status fallback_rollback
    return 1
  fi
  api_request POST "/v1/pages/$FALLBACK_PAGE_ID/publication" || return $?
  status "fallback_applied_$variant"
}

case "${1:-}" in
  build) build "${2:-$FALLBACK_SNAPSHOT}" ;;
  apply) [ -n "${2:-}" ] || { status fallback_missing_variant; exit 2; }; apply "$2" ;;
  *) printf 'usage: %s build [snapshot] | apply normal|outage\n' "$0" >&2; exit 2 ;;
esac
