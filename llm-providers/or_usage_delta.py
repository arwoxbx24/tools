#!/usr/bin/env python3
"""Track OpenRouter API usage with save/delta snapshot support."""

import json
import os
import sys
from urllib.request import Request, urlopen


SNAPSHOT_FILE = ".agent-work/or-usage-snapshots.json"


def get_api_key():
    key = os.environ.get("OPENROUTER_API_KEY", "").strip()
    if not key:
        sys.stderr.write("Error: OPENROUTER_API_KEY environment variable is missing or empty\n")
        sys.exit(1)
    return key


def fetch_current_usage():
    key = get_api_key()
    url = "https://openrouter.ai/api/v1/key"
    req = Request(url, headers={"Authorization": f"Bearer {key}"})
    with urlopen(req) as resp:
        data = json.load(resp)
    if "data" not in data or "usage" not in data["data"]:
        sys.stderr.write("Error: Expected data['data']['usage'] not found in response\n")
        sys.exit(1)
    return data["data"]["usage"]


def load_snapshots():
    if not os.path.exists(SNAPSHOT_FILE):
        return {}
    with open(SNAPSHOT_FILE, "r") as f:
        return json.load(f)


def save_snapshots(snapshots):
    os.makedirs(os.path.dirname(SNAPSHOT_FILE), exist_ok=True)
    with open(SNAPSHOT_FILE, "w") as f:
        json.dump(snapshots, f, indent=2)


def cmd_save(label):
    usage = fetch_current_usage()
    snapshots = load_snapshots()
    snapshots[label] = usage
    save_snapshots(snapshots)
    print(usage)


def cmd_delta(label):
    snapshots = load_snapshots()
    if label not in snapshots:
        sys.stderr.write(f"Error: Unknown label '{label}'\n")
        sys.exit(1)
    saved = snapshots[label]
    current = fetch_current_usage()
    delta = current - saved
    print(delta)


def cmd_selftest():
    snapshots = {"test_start": 1000, "test_middle": 2500}
    current = 3750
    delta = current - snapshots["test_start"]
    assert delta == 2750, f"Expected 2750, got {delta}"
    delta2 = current - snapshots["test_middle"]
    assert delta2 == 1250, f"Expected 1250, got {delta2}"
    return 0


def main():
    if len(sys.argv) < 2:
        sys.stderr.write("Usage: python3 or_usage_delta.py <save|delta|selftest> [args...]\n")
        sys.exit(1)

    cmd = sys.argv[1]

    if cmd == "save":
        if len(sys.argv) < 3:
            sys.stderr.write("Usage: python3 or_usage_delta.py save <label>\n")
            sys.exit(1)
        cmd_save(sys.argv[2])
    elif cmd == "delta":
        if len(sys.argv) < 3:
            sys.stderr.write("Usage: python3 or_usage_delta.py delta <label>\n")
            sys.exit(1)
        cmd_delta(sys.argv[2])
    elif cmd == "selftest":
        cmd_selftest()
    else:
        sys.stderr.write("Usage: python3 or_usage_delta.py <save|delta|selftest> [args...]\n")
        sys.exit(1)


if __name__ == "__main__":
    main()
