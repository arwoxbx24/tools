import json
with open('/root/workspaces/tools/acc1-scripts/settings.json') as f:
    d = json.load(f)
hooks = d.get('hooks', {})
pre = hooks.get('PreToolUse', [])
for h in pre:
    matcher = h.get('matcher', '')
    if 'Write' in str(matcher):
        print('Write PreToolUse entry:')
        print(json.dumps(h, indent=2))
