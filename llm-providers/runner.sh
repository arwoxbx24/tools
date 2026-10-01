#!/usr/bin/env bash
# Grounded one-shot OpenRouter author + independent review runner.
# Usage: runner.sh <task.md> <repo-dir> <branch>
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FAILOVER="$SCRIPT_DIR/failover.sh"
POLICY="$SCRIPT_DIR/model-policy.json"
LOG="${RUNNER_LOG:-}"
AUTHOR_SCHEMA='{"type":"object","properties":{"files":{"type":"object","additionalProperties":{"type":"string"}},"edits":{"type":"object","additionalProperties":{"type":"array","minItems":1,"items":{"type":"object","properties":{"old":{"type":"string","minLength":1},"new":{"type":"string"}},"required":["old","new"],"additionalProperties":false}}}},"required":["files","edits"],"additionalProperties":false}'
REVIEW_SCHEMA='{"type":"object","properties":{"verdict":{"type":"string","enum":["PASS","FAIL"]},"findings":{"type":"array","items":{"type":"object","properties":{"severity":{"type":"string","enum":["blocker","major","minor"]},"file":{"type":"string"},"line":{"type":"integer","minimum":0},"issue":{"type":"string"}},"required":["severity","file","line","issue"],"additionalProperties":false}},"tests":{"type":"array","items":{"type":"string"}}},"required":["verdict","findings","tests"],"additionalProperties":false}'

[[ $# -eq 3 ]] || { echo "Usage: runner.sh <task.md> <repo-dir> <branch>" >&2; exit 1; }
TASK_FILE="$(realpath -m "$1")"
REPO_DIR="$(realpath -m "$2")"
BRANCH="$3"
[[ -f "$TASK_FILE" ]] || { echo "BLOCKED_TASK_FILE_MISSING" >&2; exit 1; }
[[ "$(git -C "$REPO_DIR" rev-parse --is-inside-work-tree 2>/dev/null || true)" == "true" ]] \
  || { echo "BLOCKED_NOT_GIT_REPOSITORY" >&2; exit 1; }
WORK_DIR="$REPO_DIR/.agent-work/runtime"
mkdir -p "$WORK_DIR" "$REPO_DIR/.agent-work/receipts"
LOG="${LOG:-$REPO_DIR/.agent-work/receipts/openrouter-runner.log}"

log() { printf '[%s] %s\n' "$(date '+%H:%M:%S')" "$*" | tee -a "$LOG" >&2; }
section() {
  awk -v h="$1" '
    $0 == "## " h { found=1; next }
    found && /^## / { exit }
    found && NF { print }
  ' "$TASK_FILE"
}

cd "$REPO_DIR"
CURRENT_BRANCH="$(git branch --show-current)"
[[ "$CURRENT_BRANCH" == "$BRANCH" ]] || {
  echo "BLOCKED_BRANCH_MISMATCH: current=$CURRENT_BRANCH expected=$BRANCH" >&2
  exit 1
}

TASK_CONTENT="$(sed -e 's/^## Файлы:$/## Files:/' -e 's/^## Проверка:$/## Verification:/' -e 's/^## Коммит:$/## Commit:/' "$TASK_FILE")"
TASK_TITLE="$(sed -n 's/^# //p' "$TASK_FILE" | head -1)"
VERIFY_CMD="$(section 'Проверка:' | head -1)"
COMMIT_MSG="$(section 'Коммит:' | head -1)"
[[ -n "$VERIFY_CMD" ]] || { echo "BLOCKED_VERIFY_REQUIRED" >&2; exit 1; }
[[ -n "$TASK_TITLE" ]] || TASK_TITLE="OpenRouter grounded patch"
[[ -n "$COMMIT_MSG" ]] || COMMIT_MSG="$TASK_TITLE"

mapfile -t CONTEXT_FILES < <(section 'Файлы:')
mapfile -t NEW_FILES < <(section 'New files:')
mapfile -t CONTEXT_RANGES < <(section 'Context ranges:')
ALL_FILES=("${CONTEXT_FILES[@]}" "${NEW_FILES[@]}")
(( ${#ALL_FILES[@]} > 0 )) || { echo "BLOCKED_SCOPE_REQUIRED" >&2; exit 1; }

git diff --cached --quiet -- "${ALL_FILES[@]}" || { echo "BLOCKED_STAGED_SCOPE" >&2; exit 1; }

check_context_path() {
  local rel="$1" lower="/${1,,}/"
  [[ ! "$lower" =~ /(archive|archives|backup|backups|copy|copies|temp|tmp|old|legacy|previous|snapshot|snapshots|dump|dumps|history|historical)(/|\.) ]] \
    || { echo "BLOCKED_HISTORICAL_CONTEXT: $rel" >&2; exit 1; }
  [[ "$rel" != "tools/llm-providers/usage.jsonl" ]] \
    || { echo "BLOCKED_HISTORICAL_CONTEXT: $rel" >&2; exit 1; }
}
for rel in "${ALL_FILES[@]}"; do
  check_context_path "$rel"
done

BASE_HEAD="$(git rev-parse HEAD)"
STAGED_TREE_BEFORE="$(git write-tree)"

check_invariants() {
  local current_head current_staged_tree
  current_head="$(git rev-parse HEAD)"
  [[ "$current_head" == "$BASE_HEAD" ]] || { echo "BLOCKED_HEAD_CHANGED" >&2; exit 1; }
  current_staged_tree="$(git write-tree)"
  [[ "$current_staged_tree" == "$STAGED_TREE_BEFORE" ]] || { echo "BLOCKED_STAGED_TREE_CHANGED" >&2; exit 1; }
}
declare -A SOURCE_HASHES
for rel in "${CONTEXT_FILES[@]}"; do
  [[ "$rel" =~ ^[A-Za-z0-9._/-]+$ && "$rel" != /* && "$rel" != *..* ]] || { echo "BLOCKED_SCOPE_PATH: $rel" >&2; exit 1; }
  abs="$(realpath -m "$REPO_DIR/$rel")"
  [[ "$abs" == "$REPO_DIR/"* && -f "$abs" ]] || { echo "BLOCKED_SCOPE_PATH: $rel" >&2; exit 1; }
  check_context_path "${abs#"$REPO_DIR/"}"
  git ls-files --error-unmatch -- "$rel" >/dev/null 2>&1 || { echo "BLOCKED_UNTRACKED_CONTEXT: $rel" >&2; exit 1; }
  git diff --quiet -- "$rel" || { echo "BLOCKED_DIRTY_SCOPE: $rel" >&2; exit 1; }
  SOURCE_HASHES["$rel"]="$(sha256sum "$abs" | cut -d' ' -f1)"
done
for rel in "${NEW_FILES[@]}"; do
  [[ "$rel" =~ ^[A-Za-z0-9._/-]+$ && "$rel" != /* && "$rel" != *..* ]] || { echo "BLOCKED_SCOPE_PATH: $rel" >&2; exit 1; }
  abs="$(realpath -m "$REPO_DIR/$rel")"
  [[ "$abs" == "$REPO_DIR/"* && ! -e "$abs" ]] || { echo "BLOCKED_NEW_FILE_EXISTS: $rel" >&2; exit 1; }
  check_context_path "${abs#"$REPO_DIR/"}"
done
SOURCE_PACKET="$(python3 - "$REPO_DIR" "${#CONTEXT_FILES[@]}" "${ALL_FILES[@]}" --ranges "${CONTEXT_RANGES[@]}" <<'PY'
import hashlib, json, pathlib, sys
root = pathlib.Path(sys.argv[1])
n_existing = int(sys.argv[2])
marker = sys.argv.index("--ranges")
paths = sys.argv[3:marker]
ranges = {}
for spec in sys.argv[marker + 1:]:
    try:
        rel, start, end = spec.rsplit(":", 2)
        start, end = int(start), int(end)
    except Exception:
        raise SystemExit("BLOCKED_CONTEXT_RANGE")
    if rel not in paths[:n_existing] or start < 1 or end < start:
        raise SystemExit("BLOCKED_CONTEXT_RANGE")
    ranges[rel] = (start, end)
packet = []
for index, rel in enumerate(paths):
    if index < n_existing:
        raw = (root / rel).read_bytes()
        text = raw.decode("utf-8")
        span = ranges.get(rel)
        if span:
            lines = text.splitlines(keepends=True)
            text = "".join(lines[span[0] - 1:span[1]])
        packet.append({"path": rel, "sha256": hashlib.sha256(raw).hexdigest(),
                       "content": text, "range": span, "absent": False})
    else:
        packet.append({"path": rel, "sha256": None, "content": None, "absent": True})
print(json.dumps(packet, ensure_ascii=True).replace("=", "\\u003d"))
PY
)"

AUTHOR_MODEL="$(python3 - "$POLICY" <<'PY'
import json, sys
p = json.load(open(sys.argv[1]))
print(p["routes"]["code"][0])
PY
)"
REVIEW_MODEL="$(python3 - "$POLICY" "$AUTHOR_MODEL" <<'PY'
import json, sys
p = json.load(open(sys.argv[1]))
author = sys.argv[2]
print(next(m for m in p["routes"]["review"] if m != author))
PY
)"
AUTHOR_PROMPT="TASK: Apply the task specification below to the exact source packet.
SCOPE: ${ALL_FILES[*]}
BASE_HEAD: $BASE_HEAD
ACCEPTANCE: Preserve unrelated behavior. Change only scoped files. Declared absent paths may be created; no other new files or deletions are allowed.
VERIFY: $VERIFY_CMD
OUTPUT: Return exactly one JSON object with both keys. For existing files use {\"edits\":{\"path\":[{\"old\":\"exact unique source\",\"new\":\"replacement\"}]}}. For declared absent files use {\"files\":{\"path\":\"complete content\"}}. Use an empty object for either key when unused. No commentary, fences, placeholders, deletions, or unrelated paths.

TASK SPECIFICATION:
$TASK_CONTENT

EXACT SOURCE PACKET (JSON; decode string escapes before use):
===SOURCE_PAYLOAD===
$SOURCE_PACKET
===END_SOURCE_PAYLOAD==="

PATCH_FILE="$(mktemp "$WORK_DIR/or-patch-XXXXXX")"
REVIEW_FILE="$(mktemp "$WORK_DIR/or-review-XXXXXX")"
PATCH_ACTIVE=0
cleanup() {
  local rc=$?
  if [ "$PATCH_ACTIVE" -eq 1 ]; then
    git apply -R "$PATCH_FILE" || { echo "BLOCKED_ROLLBACK_FAILED" >&2; rc=2; }
  fi
  rm -f "$PATCH_FILE" "$REVIEW_FILE"
  exit "$rc"
}
trap cleanup EXIT
TASK_KEY="$(printf '%s\0%s\0%s' "$BASE_HEAD" "$AUTHOR_MODEL" "$AUTHOR_PROMPT" | sha256sum | cut -d' ' -f1)"
CACHE_PATCH="$WORK_DIR/author-$TASK_KEY.patch"
AUTHOR_REUSED=0
if [[ -s "$CACHE_PATCH" ]]; then
  cp "$CACHE_PATCH" "$PATCH_FILE"
  AUTHOR_REUSED=1
  log "author cache hit key=${TASK_KEY:0:12}"
else
  log "author=$AUTHOR_MODEL head=${BASE_HEAD:0:12} files=${#ALL_FILES[@]}"
  printf '%s\n' "$AUTHOR_PROMPT" | LLM_RESPONSE_SCHEMA="$AUTHOR_SCHEMA" "$FAILOVER" --preflight-only --role generate --model "$AUTHOR_MODEL" --tokens 8000 >/dev/null
  printf '%s\n' "Offline independent reviewer route preflight. No model call." | "$FAILOVER" --preflight-only --role review --model "$REVIEW_MODEL" >/dev/null
  printf '%s\n' "$AUTHOR_PROMPT" | LLM_RESPONSE_SCHEMA="$AUTHOR_SCHEMA" "$FAILOVER" --role generate --model "$AUTHOR_MODEL" --tokens 8000 >"$PATCH_FILE"

python3 - "$PATCH_FILE" "$REPO_DIR" "${CONTEXT_FILES[@]}" --new "${NEW_FILES[@]}" <<'PY'
import difflib, json, pathlib, sys
response = pathlib.Path(sys.argv[1])
root = pathlib.Path(sys.argv[2])
marker = sys.argv.index("--new")
existing = set(sys.argv[3:marker])
new = set(sys.argv[marker + 1:])
try:
    raw = response.read_text().strip()
    fenced = __import__("re").fullmatch(r"```(?:json)?\s*\n(.*)\n```", raw, __import__("re").S)
    payload = json.loads(fenced.group(1) if fenced else raw)
    files = payload.get("files", {})
    edits = payload.get("edits", {})
except Exception as exc:
    raise SystemExit(f"BLOCKED_AUTHOR_FORMAT: {type(exc).__name__}")
if (not isinstance(files, dict) or not isinstance(edits, dict) or not new.issubset(files)
        or not set(files) <= existing | new or not set(edits) <= existing or not files and not edits):
    raise SystemExit("BLOCKED_PATCH_SCOPE")
patch = []
outputs = dict(files)
for rel, replacements in edits.items():
    if not isinstance(replacements, list) or not replacements:
        raise SystemExit("BLOCKED_EDIT_FORMAT")
    content = (root / rel).read_text()
    for edit in replacements:
        if not isinstance(edit, dict) or set(edit) != {"old", "new"}:
            raise SystemExit("BLOCKED_EDIT_FORMAT")
        old, replacement = edit["old"], edit["new"]
        if not isinstance(old, str) or not old or not isinstance(replacement, str) or content.count(old) != 1:
            raise SystemExit("BLOCKED_EDIT_ANCHOR")
        content = content.replace(old, replacement, 1)
    outputs[rel] = content
for rel, content in outputs.items():
    if not isinstance(content, str):
        raise SystemExit("BLOCKED_FILE_CONTENT")
    if not content.endswith("\n"):
        content += "\n"
    old = "" if rel in new else (root / rel).read_text()
    if content == old:
        continue
    patch.append(f"diff --git a/{rel} b/{rel}\n")
    if rel in new:
        patch.append("new file mode 100644\n")
    patch.extend(difflib.unified_diff(
        old.splitlines(keepends=True), content.splitlines(keepends=True),
        fromfile="/dev/null" if rel in new else f"a/{rel}", tofile=f"b/{rel}",
    ))
if not patch:
    raise SystemExit("BLOCKED_PATCH_EMPTY")
response.write_text("".join(patch))
PY
fi

PATCH_PATHS="$(python3 - "$PATCH_FILE" "${CONTEXT_FILES[@]}" --new "${NEW_FILES[@]}" <<'PY'
import re, sys
raw = open(sys.argv[1], errors="replace").read()
marker = sys.argv.index("--new")
existing = set(sys.argv[2:marker])
new = set(sys.argv[marker + 1:])
allowed = existing | new
wrapped = re.fullmatch(r"```(?:diff)?\n(.*)\n```\s*", raw, re.S)
if wrapped:
    raw = wrapped.group(1).rstrip() + "\n"
    open(sys.argv[1], "w").write(raw)
if "```" in raw:
    raise SystemExit("BLOCKED_PATCH_FORMAT")
pairs = re.findall(r"^diff --git a/([^\n]+) b/([^\n]+)$", raw, re.M)
if not pairs:
    pairs = re.findall(r"^--- a/([^\n]+)\n\+\+\+ b/([^\n]+)$", raw, re.M)
    pairs += [(path, path) for path in re.findall(r"^--- /dev/null\n\+\+\+ b/([^\n]+)$", raw, re.M)]
if not pairs or any(a != b or a not in allowed for a, b in pairs):
    raise SystemExit("BLOCKED_PATCH_SCOPE")
if "deleted file mode" in raw or re.search(r"^\+\+\+ /dev/null$", raw, re.M):
    raise SystemExit("BLOCKED_PATCH_DELETE")
for path in new:
    block = re.search(rf"(?ms)^diff --git a/{re.escape(path)} b/{re.escape(path)}\n(.*?)(?=^diff --git |\Z)", raw)
    text = block.group(1) if block else raw
    if not re.search(rf"(?m)^--- /dev/null\n\+\+\+ b/{re.escape(path)}$", text):
        raise SystemExit("BLOCKED_NEW_FILE_FORMAT")
if re.search(r"(?im)^\+.*(?:<[^>]*\.\.\.[^>]*>|\bplaceholder\b)", raw):
    raise SystemExit("BLOCKED_PATCH_PLACEHOLDER")
for path in dict.fromkeys(a for a, _ in pairs):
    print(path)
PY
)" || exit $?
[[ -n "$PATCH_PATHS" ]] || { echo "BLOCKED_PATCH_EMPTY" >&2; exit 1; }
mapfile -t PATCH_FILES <<<"$PATCH_PATHS"

# Formatting-only repair: model-generated blank additions often contain spaces.
sed -i -E '/^\+\+\+/! s/^(\+.*[^[:space:]])[[:space:]]+$/\1/; /^\+[[:space:]]+$/s/[[:space:]]+$//' "$PATCH_FILE"
python3 - "$PATCH_FILE" <<'PY'
import re, sys
path = sys.argv[1]
lines = open(path).read().splitlines(keepends=True)
for i, line in enumerate(lines):
    match = re.match(r"(@@ -(\d+)(?:,\d+)? \+(\d+)(?:,\d+)? @@.*)$", line.rstrip("\n"))
    if not match:
        continue
    old = new = 0
    for body in lines[i + 1:]:
        if body.startswith(("@@ ", "diff --git ")):
            break
        if body.startswith("\\"):
            continue
        old += body.startswith((" ", "-"))
        new += body.startswith((" ", "+"))
    suffix = match.group(1).split("@@", 2)[-1]
    lines[i] = f"@@ -{match.group(2)},{old} +{match.group(3)},{new} @@{suffix}\n"
open(path, "w").writelines(lines)
PY

for rel in "${CONTEXT_FILES[@]}"; do
  current="$(sha256sum "$REPO_DIR/$rel" | cut -d' ' -f1)"
  [[ "$current" == "${SOURCE_HASHES[$rel]}" ]] || { echo "BLOCKED_STALE_SOURCE: $rel" >&2; exit 1; }
done
check_invariants
git apply --check --whitespace=error-all "$PATCH_FILE"
if (( AUTHOR_REUSED == 0 )); then
  cp "$PATCH_FILE" "$CACHE_PATCH"
  chmod 600 "$CACHE_PATCH"
fi

git apply "$PATCH_FILE"
PATCH_ACTIVE=1
VERIFY_RC=0
bash -lc "$VERIFY_CMD" >> "$LOG" 2>&1 || VERIFY_RC=$?
if [ "$VERIFY_RC" -ne 0 ]; then
  echo "BLOCKED_VERIFY_FAILED: rc=$VERIFY_RC" >&2
  exit 1
fi
check_invariants

REVIEW_PACKET="$(python3 - "$PATCH_FILE" "$SOURCE_PACKET" "$TASK_CONTENT" <<'PY'
import json, sys
payload = {"task": sys.argv[3], "patch": open(sys.argv[1]).read(),
           "source_packet": json.loads(sys.argv[2])}
print(json.dumps(payload, ensure_ascii=True).replace("=", "\\u003d"))
PY
)"
REVIEW_PROMPT="AUTHOR_MODEL: $AUTHOR_MODEL
Review the exact patch against the supplied source read-only. Reject scope drift, invented identifiers, missing validation, unsafe rollback, retries, prompt/body logging, or behavior not requested. Return exactly one JSON object and no fences:
{\"verdict\":\"PASS|FAIL\",\"findings\":[{\"severity\":\"blocker|major|minor\",\"file\":\"path\",\"line\":0,\"issue\":\"text\"}],\"tests\":[\"command or evidence\"]}
EXACT REVIEW PACKET (JSON; decode string escapes before use):
===SOURCE_PAYLOAD===
$REVIEW_PACKET
===END_SOURCE_PAYLOAD==="
printf '%s\n' "$REVIEW_PROMPT" | LLM_RESPONSE_SCHEMA="$REVIEW_SCHEMA" "$FAILOVER" --preflight-only --role review --model "$REVIEW_MODEL" >/dev/null
printf '%s\n' "$REVIEW_PROMPT" | LLM_RESPONSE_SCHEMA="$REVIEW_SCHEMA" "$FAILOVER" --role review --model "$REVIEW_MODEL" >"$REVIEW_FILE"
validate_review() {
python3 - "$REVIEW_FILE" "$LOG" <<'PY'
import json, sys
raw = open(sys.argv[1]).read().strip()
try:
    result = json.loads(raw)
except Exception as exc:
    print(f"BLOCKED_REVIEW_FORMAT: {type(exc).__name__}", file=sys.stderr)
    raise SystemExit(2)
if result.get("verdict") != "PASS" or result.get("findings"):
    receipt = json.dumps({"verdict": result.get("verdict"), "findings": result.get("findings", [])},
                         ensure_ascii=True)
    print(receipt, file=sys.stderr)
    with open(sys.argv[2], "a") as log:
        log.write(f"REVIEW_FAIL {receipt}\n")
    raise SystemExit(1)
PY
}
validate_review
check_invariants

PATCH_ACTIVE=0
check_invariants
PATCH_SHA="$(sha256sum "$PATCH_FILE" | cut -d' ' -f1)"
log "SUCCESS patch_applied=${PATCH_SHA:0:12} author=$AUTHOR_MODEL reviewer=$REVIEW_MODEL"
printf 'SUCCESS PATCH_APPLIED %s\n' "$PATCH_SHA"
