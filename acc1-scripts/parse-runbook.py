#!/usr/bin/env python3
"""Parse YAML runbook template and output steps as JSON."""
import sys
import json

def parse_yaml_simple(filepath):
    """Simple YAML parser for runbook format — no PyYAML dependency."""
    steps = []
    current_step = None
    current_params = {}
    in_params = False

    with open(filepath) as f:
        for line in f:
            stripped = line.strip()
            if stripped.startswith('- name:'):
                if current_step:
                    current_step['params'] = current_params
                    steps.append(current_step)
                current_step = {'name': stripped.split(':', 1)[1].strip()}
                current_params = {}
                in_params = False
            elif current_step and stripped.startswith('action:'):
                current_step['action'] = stripped.split(':', 1)[1].strip()
                in_params = False
            elif current_step and stripped == 'params:':
                in_params = True
            elif in_params and ':' in stripped and not stripped.startswith('#'):
                key, val = stripped.split(':', 1)
                current_params[key.strip()] = val.strip().strip('"').strip("'")
            elif not stripped.startswith(' ') and not stripped.startswith('-'):
                in_params = False

    if current_step:
        current_step['params'] = current_params
        steps.append(current_step)

    return steps

if __name__ == '__main__':
    if len(sys.argv) < 2:
        print("Usage: parse-runbook.py <template.yaml>", file=sys.stderr)
        sys.exit(1)
    steps = parse_yaml_simple(sys.argv[1])
    print(json.dumps(steps))
