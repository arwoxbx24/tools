#!/usr/bin/env python3
"""Insert V162_KP into claude-main.yaml critical_rules and quick_card sections."""

YAML_PATH = '/root/workspaces/tools/acc1-scripts/rules-data/claude-main.yaml'

with open(YAML_PATH, 'r') as f:
    content = f.read()

# 1. Insert V162_KP after V_DIAG block in critical_rules
old_v_diag = (
    '  - code: "V_DIAG"\n'
    '    title: "Auto-Diagnose on Error"\n'
    '    short: "On bash error → auto-suggest diagnostic layer and command. SURE methodology"\n'
    '    level: "CRITICAL"\n'
    '    enforced_by: "auto-diagnose-on-error.sh"\n'
    '    in_claude_md: true\n'
    '\n'
    '# Token Economy rules (V183)'
)

new_v_diag = (
    '  - code: "V_DIAG"\n'
    '    title: "Auto-Diagnose on Error"\n'
    '    short: "On bash error → auto-suggest diagnostic layer and command. SURE methodology"\n'
    '    level: "CRITICAL"\n'
    '    enforced_by: "auto-diagnose-on-error.sh"\n'
    '    in_claude_md: true\n'
    '\n'
    '  - code: "V162_KP"\n'
    '    title: "KP Data Source Enforcement"\n'
    '    short: "\u041a\u041f/estimate \u0441 \u0446\u0435\u043d\u0430\u043c\u0438 = \u041e\u0411\u042f\u0417\u0410\u0422\u0415\u041b\u042c\u041d\u041e \u0447\u0438\u0442\u0430\u0442\u044c bitrix/arwox-price/ \u0438 clients/CLIENT/ \u041f\u0415\u0420\u0415\u0414 \u0437\u0430\u043f\u0438\u0441\u044c\u044e. \u0412\u044b\u0434\u0443\u043c\u0430\u043d\u043d\u044b\u0435 \u0446\u0435\u043d\u044b = CRITICAL V162. \u041a\u043e\u0440\u043e\u0431\u043e\u0447\u043d\u044b\u0439 \u0411\u0432\u0431\u0434 \u2260 \u041e\u0431\u043b\u0430\u0447\u043d\u044b\u0439"\n'
    '    level: "CRITICAL"\n'
    '    enforced_by: "enforce-kp-data-source.sh"\n'
    '    in_claude_md: true\n'
    '\n'
    '# Token Economy rules (V183)'
)

if old_v_diag in content:
    content = content.replace(old_v_diag, new_v_diag, 1)
    print('V162_KP inserted into critical_rules OK')
else:
    print('ERROR: V_DIAG anchor not found')

# 2. Insert Client KP quick_card entry
old_git = (
    '  - want: "Destructive git during crisis"\n'
    '    wrong: "git checkout -- ."\n'
    '    right: "git add -A && git commit -m \'wip: crisis snapshot\' first"\n'
    '    rule: "V280"\n'
    '\n'
    '# Additional behavioral IF-blocks'
)

new_git = (
    '  - want: "Destructive git during crisis"\n'
    '    wrong: "git checkout -- ."\n'
    '    right: "git add -A && git commit -m \'wip: crisis snapshot\' first"\n'
    '    rule: "V280"\n'
    '  - want: "Client \u041a\u041f"\n'
    '    wrong: "Invent prices from memory"\n'
    '    right: "Read arwox-price/ catalog \u2192 real tariffs \u2192 then write"\n'
    '    rule: "V162_KP"\n'
    '\n'
    '# Additional behavioral IF-blocks'
)

if old_git in content:
    content = content.replace(old_git, new_git, 1)
    print('Client KP quick_card entry inserted OK')
else:
    print('ERROR: Destructive git anchor not found')

with open(YAML_PATH, 'w') as f:
    f.write(content)

count = content.count('V162_KP')
print(f'V162_KP occurrences in file: {count}')
