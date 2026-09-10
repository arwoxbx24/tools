#!/usr/bin/env python3
"""
Generate MANIFEST.md delta — find V-codes in hooks not documented in MANIFEST.
Usage: python3 generate-manifest-delta.py [--write]
Default: dry-run (prints delta to stdout)
"""
import os
import re
import sys

HOOKS_DIR = os.path.expanduser("/root/workspaces/tools/acc1-scripts/hooks")
MANIFEST = os.path.join(HOOKS_DIR, "MANIFEST.md")

def get_manifest_vcodes():
    with open(MANIFEST) as f:
        return set(re.findall(r'V\d{3}', f.read()))

def get_hook_vcodes():
    vcodes = {}
    for fname in sorted(os.listdir(HOOKS_DIR)):
        if not fname.endswith('.sh'):
            continue
        path = os.path.join(HOOKS_DIR, fname)
        with open(path) as f:
            content = f.read()
        for match in re.finditer(r'(V\d{3})\s+BLOCKED[:\s]+([^\n"]+)', content):
            code, msg = match.group(1), match.group(2).strip()
            if code not in vcodes:
                vcodes[code] = {'hook': fname, 'message': msg[:80]}
    return vcodes

def main():
    manifest_codes = get_manifest_vcodes()
    hook_codes = get_hook_vcodes()

    missing = {k: v for k, v in hook_codes.items() if k not in manifest_codes}

    if not missing:
        print("MANIFEST is complete. No missing V-codes.")
        return

    print(f"## Missing V-codes: {len(missing)}")
    print()

    # Group by hook file
    by_hook = {}
    for code, info in sorted(missing.items()):
        hook = info['hook']
        if hook not in by_hook:
            by_hook[hook] = []
        by_hook[hook].append((code, info['message']))

    for hook, codes in sorted(by_hook.items()):
        print(f"## {hook}")
        print("| V-код | Что заблокировано | Что делать вместо |")
        print("|-------|-------------------|-------------------|")
        for code, msg in codes:
            print(f"| {code} | {msg} | [нужно заполнить] |")
        print()

    if '--write' in sys.argv:
        print("WARNING: --write mode not implemented yet. Use output above to manually append.")

if __name__ == '__main__':
    main()
