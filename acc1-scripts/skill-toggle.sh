#!/bin/bash
set +e

SKILLS_DIR="/root/claude-projects/.claude/skills"

# All output to stderr
exec 1>&2

# Python script for manipulating YAML frontmatter
manipulate_frontmatter() {
    local file="$1"
    local action="$2"  # "add" or "remove"

    python3 - "$file" "$action" << 'PYTHON_EOF'
import sys
import re

file_path = sys.argv[1]
action = sys.argv[2]

with open(file_path, 'r') as f:
    content = f.read()

# Extract frontmatter
frontmatter_match = re.match(r'^---\n(.*?)\n---\n(.*)$', content, re.DOTALL)
if not frontmatter_match:
    print(f"ERROR: No valid YAML frontmatter found in {file_path}")
    sys.exit(0)

frontmatter = frontmatter_match.group(1)
body = frontmatter_match.group(2)

if action == "add":
    # Check if disable-model-invocation already exists
    if 'disable-model-invocation:' in frontmatter:
        # Already disabled, no change needed
        sys.exit(0)

    # Add after the name: line
    lines = frontmatter.split('\n')
    new_lines = []
    for line in lines:
        new_lines.append(line)
        if line.startswith('name:'):
            new_lines.append('disable-model-invocation: true')

    new_frontmatter = '\n'.join(new_lines)
    new_content = f"---\n{new_frontmatter}\n---\n{body}"

    with open(file_path, 'w') as f:
        f.write(new_content)

elif action == "remove":
    # Remove the disable-model-invocation line
    if 'disable-model-invocation:' not in frontmatter:
        # Already enabled, no change needed
        sys.exit(0)

    lines = frontmatter.split('\n')
    new_lines = [line for line in lines if not line.strip().startswith('disable-model-invocation:')]

    new_frontmatter = '\n'.join(new_lines)
    new_content = f"---\n{new_frontmatter}\n---\n{body}"

    with open(file_path, 'w') as f:
        f.write(new_content)

PYTHON_EOF
}

# Get all skill directories
get_all_skills() {
    find "$SKILLS_DIR" -mindepth 1 -maxdepth 1 -type d -exec basename {} \;
}

# Check if skill is disabled
is_disabled() {
    local skill_file="$1"
    grep -q "disable-model-invocation: *true" "$skill_file" 2>/dev/null
    return $?
}

# Command: enable
cmd_enable() {
    if [ $# -eq 0 ]; then
        echo "ERROR: skill-toggle.sh enable requires at least one skill name"
        exit 0
    fi

    for skill_name in "$@"; do
        skill_md="$SKILLS_DIR/$skill_name/SKILL.md"

        if [ ! -f "$skill_md" ]; then
            echo "WARNING: Skill '$skill_name' not found at $skill_md"
            continue
        fi

        manipulate_frontmatter "$skill_md" "remove"
        echo "Enabled skill: $skill_name"
    done
}

# Command: disable
cmd_disable() {
    if [ $# -eq 0 ]; then
        echo "ERROR: skill-toggle.sh disable requires at least one skill name"
        exit 0
    fi

    for skill_name in "$@"; do
        skill_md="$SKILLS_DIR/$skill_name/SKILL.md"

        if [ ! -f "$skill_md" ]; then
            echo "WARNING: Skill '$skill_name' not found at $skill_md"
            continue
        fi

        manipulate_frontmatter "$skill_md" "add"
        echo "Disabled skill: $skill_name"
    done
}

# Command: disable-all
cmd_disable_all() {
    while IFS= read -r skill_name; do
        skill_md="$SKILLS_DIR/$skill_name/SKILL.md"

        if [ ! -f "$skill_md" ]; then
            continue
        fi

        manipulate_frontmatter "$skill_md" "add"
        echo "Disabled skill: $skill_name"
    done < <(get_all_skills)
}

# Command: status
cmd_status() {
    echo ""
    echo "Skill Status"
    echo "============================================"
    printf "%-30s %s\n" "Skill Name" "Status"
    echo "--------------------------------------------"

    while IFS= read -r skill_name; do
        skill_md="$SKILLS_DIR/$skill_name/SKILL.md"

        if [ ! -f "$skill_md" ]; then
            continue
        fi

        if is_disabled "$skill_md"; then
            status="DISABLED"
        else
            status="ENABLED"
        fi

        printf "%-30s %s\n" "$skill_name" "$status"
    done < <(get_all_skills | sort)

    echo ""
}

# Main command dispatcher
case "$1" in
    enable)
        shift
        cmd_enable "$@"
        ;;
    disable)
        shift
        cmd_disable "$@"
        ;;
    disable-all)
        cmd_disable_all
        ;;
    status)
        cmd_status
        ;;
    *)
        echo "Usage: skill-toggle.sh {enable|disable|disable-all|status} [skill1 skill2 ...]"
        echo ""
        echo "Commands:"
        echo "  enable skill1 skill2 ...    Enable specific skills"
        echo "  disable skill1 skill2 ...   Disable specific skills"
        echo "  disable-all                 Disable all skills"
        echo "  status                      Show all skills and their status"
        exit 0
        ;;
esac

exit 0
