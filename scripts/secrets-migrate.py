#!/usr/bin/env python3
"""Move listed workspace secret files into the shared secrets directory."""

import argparse
import os
from collections import Counter


WORKSPACE = "/root/workspaces/"
SECRETS = "/root/workspaces/secrets/"


def destination(path):
    if not os.path.isabs(path) or not path.startswith(WORKSPACE):
        return None
    relative = os.path.relpath(os.path.abspath(path), WORKSPACE)
    if relative == ".." or relative.startswith(".." + os.sep):
        return None
    return os.path.join(SECRETS, relative)


def migrate(path, dry_run):
    if os.path.islink(path):
        return "symlink", ""
    if not os.path.isfile(path):
        return "missing", ""
    dest = destination(path)
    if dest is None:
        return "skip", ""
    if os.path.exists(dest):
        return "conflict", dest
    if dry_run:
        return "plan", dest
    try:
        os.makedirs(os.path.dirname(dest), mode=0o700, exist_ok=True)
        os.replace(path, dest)
        os.chmod(dest, 0o600)
        os.symlink(dest, path)
        if os.path.realpath(path) == dest and os.path.getsize(dest) > 0:
            return "ok", dest
        return "fail", dest
    except Exception as error:
        return "denied:" + type(error).__name__, dest


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("list_file")
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()
    counts = Counter()
    try:
        with open(args.list_file, encoding="utf-8") as source:
            paths = [line.strip() for line in source]
    except Exception as error:
        print("denied:%s\t%s\t" % (type(error).__name__, args.list_file))
        counts["denied"] += 1
        paths = []
    for path in paths:
        if not path or path.startswith("#"):
            continue
        try:
            status, dest = migrate(path, args.dry_run)
        except Exception as error:
            status, dest = "denied:" + type(error).__name__, ""
        counts[status.split(":", 1)[0]] += 1
        print("%s\t%s\t%s" % (status, path, dest))
    print("summary " + " ".join("%s=%d" % item for item in sorted(counts.items())))


if __name__ == "__main__":
    main()
