#!/usr/bin/env python3
"""UI vision review: sends screenshots to OpenAI vision model, returns structured verdict.

Usage:
    python3 tools/ui_vision_review.py <png> [<png> ...] [--url URL] [--json]

Exit codes:
    0 - pass (no defects)
    1 - fail (defects found)
    2 - network/API error or bad arguments
"""
from __future__ import annotations

import argparse
import base64
import json
import os
import re
import sys
import time
from pathlib import Path

TIMEOUT = 60.0
RETRY_DELAY = 5.0
MODEL = os.environ.get("VISION_MODEL", "gpt-4o")

# Канонический источник ключа — secrets/projects/openai.env (как в lib/llm.py key_of).
# env-переменная OPENAI_API_KEY — только запасной вариант.
_SECRETS_FILE = Path(__file__).resolve().parent.parent.parent / "secrets" / "projects" / "openai.env"


def _get_openai_key() -> str:
    """Ключ из secrets/projects/openai.env, затем из env. Возвращает пустую строку при отсутствии."""
    if _SECRETS_FILE.exists():
        m = re.search(r"OPENAI_API_KEY\s*=\s*(\S+)", _SECRETS_FILE.read_text(encoding="utf-8"))
        if m:
            return m.group(1).strip("'\"")
    return os.environ.get("OPENAI_API_KEY", "")

SYSTEM_PROMPT = """You are a senior frontend QA engineer reviewing UI screenshots.
Analyze each screenshot for visual defects:
- Overlapping or overflowing blocks (elements clipping each other)
- Clipped or truncated text (text cut off by container boundary)
- Horizontal scrollbar or content wider than viewport
- Poor contrast (text unreadable against background)
- Broken grid or misaligned layout (columns out of line, broken flex/grid)
- Label/legend mismatch (chart legend does not match actual data labels)
- Missing or broken images/icons

Respond ONLY with valid JSON in this exact schema:
{
  "verdict": "pass",
  "defects": []
}
or
{
  "verdict": "fail",
  "defects": [
    {
      "location": "<area of screen, e.g. 'top header', 'card row 3 right column'>",
      "severity": "critical | major | minor",
      "description": "<what is wrong and why it matters>"
    }
  ]
}
Return verdict "pass" and empty defects array when no issues are found.
"""


def _encode_png(path: Path) -> str:
    return base64.b64encode(path.read_bytes()).decode()


def _call_api(images: list[Path], url: str | None) -> dict:
    from openai import OpenAI  # lazy import — keeps startup fast when testing

    client = OpenAI(api_key=_get_openai_key(), timeout=TIMEOUT)

    content: list[dict] = []
    if url:
        content.append({"type": "text", "text": f"Page URL: {url}"})
    for img in images:
        content.append({"type": "text", "text": f"Screenshot ({img.name}):"})
        content.append({
            "type": "image_url",
            "image_url": {
                "url": f"data:image/png;base64,{_encode_png(img)}",
                "detail": "high",
            },
        })
    content.append({
        "type": "text",
        "text": "Review all screenshots and return the JSON verdict.",
    })

    resp = client.chat.completions.create(
        model=MODEL,
        messages=[
            {"role": "system", "content": SYSTEM_PROMPT},
            {"role": "user", "content": content},
        ],
        response_format={"type": "json_object"},
        max_tokens=1024,
    )
    text = resp.choices[0].message.content or "{}"
    return json.loads(text)


def review(images: list[Path], url: str | None, as_json: bool) -> int:
    """Run review. Returns exit code."""
    last_exc: Exception | None = None
    for attempt in range(2):
        try:
            result = _call_api(images, url)
            last_exc = None
            break
        except Exception as exc:
            last_exc = exc
            if attempt == 0:
                print(f"[vision] API error ({type(exc).__name__}), retrying in {RETRY_DELAY}s…",
                      file=sys.stderr)
                time.sleep(RETRY_DELAY)

    if last_exc is not None:
        msg = f"network/api error: {type(last_exc).__name__}: {last_exc}"
        if as_json:
            print(json.dumps({"error": msg}))
        else:
            print(f"ERROR: {msg}", file=sys.stderr)
        return 2

    verdict = result.get("verdict", "fail")
    defects: list[dict] = result.get("defects", [])

    if as_json:
        print(json.dumps({"verdict": verdict, "defects": defects}, ensure_ascii=False, indent=2))
    else:
        label = "PASS" if verdict == "pass" else "FAIL"
        print(f"Verdict: {label}")
        if defects:
            print(f"\nDefects ({len(defects)}):")
            for d in defects:
                sev = d.get("severity", "?").upper()
                loc = d.get("location", "unknown")
                desc = d.get("description", "")
                print(f"  [{sev}] {loc}: {desc}")
        else:
            print("No defects found.")

    return 0 if verdict == "pass" else 1


def main() -> int:
    parser = argparse.ArgumentParser(
        description="UI vision review: send PNG screenshots to OpenAI vision, get pass/fail verdict"
    )
    parser.add_argument("images", nargs="+", type=Path, help="PNG screenshot file(s)")
    parser.add_argument("--url", default=None, help="Page URL (informational, not fetched)")
    parser.add_argument("--json", action="store_true", dest="as_json",
                        help="Output machine-readable JSON")
    args = parser.parse_args()

    if not _get_openai_key():
        msg = "OPENAI_API_KEY environment variable is not set"
        if args.as_json:
            print(json.dumps({"error": msg}))
        else:
            print(f"ERROR: {msg}", file=sys.stderr)
        return 2

    missing = [p for p in args.images if not p.exists()]
    if missing:
        msg = f"files not found: {', '.join(str(p) for p in missing)}"
        if args.as_json:
            print(json.dumps({"error": msg}))
        else:
            print(f"ERROR: {msg}", file=sys.stderr)
        return 2

    return review(args.images, args.url, args.as_json)


if __name__ == "__main__":
    sys.exit(main())
