import json
with open('/root/workspaces/tools/acc1-scripts/settings.json') as f:
    d = json.load(f)
hooks = d.get('hooks', {})
post = hooks.get('PostToolUse', [])
print('PostToolUse count:', len(post))
print('First entry:')
print(json.dumps(post[0], indent=2))
print('---')
for h in post:
    matcher = h.get('matcher', '')
    if 'Bash' in str(matcher):
        print('Bash PostToolUse entry:')
        print(json.dumps(h, indent=2))
        break
