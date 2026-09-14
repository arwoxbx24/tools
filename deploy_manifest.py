#!/usr/bin/env python3
"""
deploy_manifest.py — манифест-деплой (E5).

Команды:
  write   — записать sha256-хэши всех .py в data/deploy_manifest.json
  verify  — сравнить текущие .py с манифестом; расхождение = exit 1

Stdlib only. Запускается из корня репо.
"""
import hashlib
import json
import sys
from pathlib import Path


PY_DIRS = ["scripts", "lib"]


def _manifest_path(repo_root: Path) -> Path:
    return repo_root / "data" / "deploy_manifest.json"


def _hash_file(path: Path) -> str:
    h = hashlib.sha256()
    h.update(path.read_bytes())
    return h.hexdigest()


def _collect(repo_root: Path) -> dict:
    result = {}
    for d in PY_DIRS:
        for f in sorted((repo_root / d).glob("*.py")):
            key = f.relative_to(repo_root).as_posix()
            result[key] = _hash_file(f)
    return result


def cmd_write(repo_root: Path) -> None:
    hashes = _collect(repo_root)
    manifest = {"files": hashes}
    mp = _manifest_path(repo_root)
    mp.parent.mkdir(parents=True, exist_ok=True)
    mp.write_text(json.dumps(manifest, indent=2, ensure_ascii=False) + "\n")
    print(f"[manifest] written {len(hashes)} files → {mp}")


def cmd_verify(repo_root: Path) -> None:
    mp = _manifest_path(repo_root)
    if not mp.exists():
        print(f"[manifest] FAIL: {mp} not found — run 'write' first")
        sys.exit(1)

    manifest = json.loads(mp.read_text())
    recorded: dict = manifest.get("files", {})
    current = _collect(repo_root)

    errors = []

    # Files present in manifest but missing or changed on disk
    for key, expected_hash in recorded.items():
        if key not in current:
            errors.append(f"MISSING: {key}")
        elif current[key] != expected_hash:
            errors.append(f"CHANGED: {key}")

    # Files on disk but not in manifest (partial deploy)
    for key in current:
        if key not in recorded:
            errors.append(f"EXTRA (partial deploy?): {key}")

    if errors:
        print("[manifest] FAIL: deploy manifest mismatch — aborting restart")
        for e in errors:
            print(f"  {e}")
        sys.exit(1)

    print(f"[manifest] OK: {len(recorded)} files match")


if __name__ == "__main__":
    if len(sys.argv) < 2 or sys.argv[1] not in ("write", "verify"):
        print("Usage: deploy_manifest.py write|verify [repo_root]")
        sys.exit(2)

    repo_root = Path(sys.argv[2]) if len(sys.argv) > 2 else Path(".")
    repo_root = repo_root.resolve()

    if sys.argv[1] == "write":
        cmd_write(repo_root)
    else:
        cmd_verify(repo_root)
