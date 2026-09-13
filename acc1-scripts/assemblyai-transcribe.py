#!/usr/bin/env python3
"""Transcribe a local media file or URL with AssemblyAI."""

import argparse
import json
import os
import sys
from pathlib import Path

SECRET_FILE = Path("/root/workspaces/secrets/services/assemblyai.env")


def api_key() -> str:
    if value := os.environ.get("ASSEMBLYAI_API_KEY"):
        return value
    try:
        for line in SECRET_FILE.read_text().splitlines():
            name, separator, value = line.partition("=")
            if separator and name.strip() == "ASSEMBLYAI_API_KEY":
                return value.strip().strip("'\"")
    except OSError:
        pass
    raise RuntimeError(
        "ASSEMBLYAI_API_KEY is not set; expected environment or " + str(SECRET_FILE)
    )


def result_payload(transcript) -> dict:
    words = []
    for word in getattr(transcript, "words", None) or []:
        words.append({
            "text": word.text,
            "start_ms": word.start,
            "end_ms": word.end,
            "confidence": word.confidence,
        })
    return {"text": transcript.text or "", "words": words}


def transcribe(source: str) -> dict:
    try:
        import assemblyai as aai
    except ImportError as exc:
        raise RuntimeError("Install the pinned dependency from requirements.txt") from exc

    aai.settings.api_key = api_key()
    transcript = aai.Transcriber().transcribe(source)
    if transcript.status == aai.TranscriptStatus.error:
        raise RuntimeError(f"AssemblyAI transcription failed: {transcript.error}")
    return result_payload(transcript)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", help="local media path or http(s) URL")
    parser.add_argument("--output-dir", type=Path, default=Path.cwd())
    args = parser.parse_args()

    if not args.source.startswith(("http://", "https://")) and not Path(args.source).is_file():
        parser.error(f"input file not found: {args.source}")

    try:
        payload = transcribe(args.source)
    except RuntimeError as exc:
        print(f"Error: {exc}", file=sys.stderr)
        return 1

    args.output_dir.mkdir(parents=True, exist_ok=True)
    stem = Path(args.source).stem if not args.source.startswith(("http://", "https://")) else "transcript"
    text_path = args.output_dir / f"{stem}.txt"
    json_path = args.output_dir / f"{stem}.json"
    text_tmp = text_path.with_suffix(text_path.suffix + ".tmp")
    json_tmp = json_path.with_suffix(json_path.suffix + ".tmp")
    text_tmp.write_text(payload["text"] + "\n")
    json_tmp.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n")
    text_tmp.replace(text_path)
    json_tmp.replace(json_path)
    print(text_path)
    print(json_path)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
