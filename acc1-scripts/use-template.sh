#!/bin/bash
#
# use-template.sh - Template expansion utility
# Usage:
#   use-template.sh list                    - Show available templates
#   use-template.sh <name>                  - Display template content
#   use-template.sh <name> <params...>      - Expand template with params
#

set -euo pipefail

TEMPLATES_DIR="/root/workspaces/tools/acc1-scripts/templates"

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Function to print colored output
print_color() {
    local color="$1"
    shift
    echo -e "${color}$*${NC}"
}

# Function to list all templates
list_templates() {
    print_color "$CYAN" "=== Available Templates ==="
    echo

    local count=0
    for template in "$TEMPLATES_DIR"/*.md; do
        if [[ -f "$template" ]]; then
            local name=$(basename "$template" .md)
            local title=$(grep -m1 "^# " "$template" | sed 's/^# //')
            local template_id=$(grep "^Template ID:" "$template" | cut -d: -f2 | xargs)
            local version=$(grep "^Version:" "$template" | cut -d: -f2 | xargs)

            print_color "$GREEN" "[$name]"
            echo "  Title: $title"
            [[ -n "$template_id" ]] && echo "  ID: $template_id"
            [[ -n "$version" ]] && echo "  Version: $version"

            # Extract short command
            local short_cmd=$(sed -n '/^## Short Command/,/^##/{/^`/p}' "$template" | head -1)
            if [[ -n "$short_cmd" ]]; then
                echo "  Command: $short_cmd"
            fi
            echo
            ((count++))
        fi
    done

    if [[ $count -eq 0 ]]; then
        print_color "$YELLOW" "No templates found in $TEMPLATES_DIR"
        return 1
    fi

    print_color "$BLUE" "Total: $count templates"
    echo
    print_color "$CYAN" "Usage:"
    echo "  use-template.sh <name>              - View template"
    echo "  use-template.sh <name> <params...>  - Expand with params"
}

# Function to display template content
display_template() {
    local name="$1"
    local template_file="$TEMPLATES_DIR/${name}.md"

    if [[ ! -f "$template_file" ]]; then
        print_color "$RED" "Error: Template '$name' not found"
        echo
        print_color "$YELLOW" "Available templates:"
        list_templates
        return 1
    fi

    print_color "$CYAN" "=== Template: $name ==="
    echo
    cat "$template_file"
}

# Function to expand template with parameters
expand_template() {
    local name="$1"
    shift
    local params=("$@")

    local template_file="$TEMPLATES_DIR/${name}.md"

    if [[ ! -f "$template_file" ]]; then
        print_color "$RED" "Error: Template '$name' not found"
        return 1
    fi

    print_color "$CYAN" "=== Expanding Template: $name ==="
    echo

    # Extract short command format
    local short_cmd=$(sed -n '/^## Short Command/,/^##/{/^`/p}' "$template_file" | head -1 | tr -d '`')

    if [[ -z "$short_cmd" ]]; then
        print_color "$YELLOW" "Warning: No short command format found"
        display_template "$name"
        return 0
    fi

    print_color "$GREEN" "Short Command Format:"
    echo "  $short_cmd"
    echo

    # Parse command format and extract placeholders
    # Example: "search <pattern> [path]" -> pattern, path (optional)
    local required_params=()
    local optional_params=()

    # Extract parameters from format
    while read -r param; do
        if [[ "$param" =~ ^\<(.+)\>$ ]]; then
            required_params+=("${BASH_REMATCH[1]}")
        elif [[ "$param" =~ ^\[(.+)\]$ ]]; then
            optional_params+=("${BASH_REMATCH[1]}")
        fi
    done < <(echo "$short_cmd" | grep -oE '<[^>]+>|\[[^]]+\]')

    local total_required=${#required_params[@]}
    local provided=${#params[@]}

    if [[ $provided -lt $total_required ]]; then
        print_color "$RED" "Error: Insufficient parameters"
        echo
        print_color "$YELLOW" "Required: ${required_params[*]}"
        [[ ${#optional_params[@]} -gt 0 ]] && echo "Optional: ${optional_params[*]}"
        echo
        echo "Usage: use-template.sh $name ${required_params[*]} [${optional_params[*]}]"
        return 1
    fi

    print_color "$GREEN" "Parameters:"
    for i in "${!required_params[@]}"; do
        echo "  ${required_params[$i]}: ${params[$i]}"
    done

    # Handle optional params
    local opt_idx=$total_required
    for opt_param in "${optional_params[@]}"; do
        if [[ $opt_idx -lt $provided ]]; then
            echo "  $opt_param: ${params[$opt_idx]}"
            ((opt_idx++))
        else
            echo "  $opt_param: (default)"
        fi
    done

    echo
    print_color "$CYAN" "=== Expanded Query ==="
    echo

    # Extract and display expanded query section
    sed -n '/^## Expanded Query$/,/^## [^E]/{ /^## Expanded Query$/d; /^## [^E]/d; p; }' "$template_file"

    echo
    print_color "$CYAN" "=== Implementation ==="
    echo

    # Extract implementation section if exists
    sed -n '/^## Implementation$/,/^## /{ /^## Implementation$/d; /^## [^I]/d; p; }' "$template_file"

    echo
    print_color "$BLUE" "See full template with: use-template.sh $name"
}

# Main logic
main() {
    if [[ $# -eq 0 ]]; then
        print_color "$YELLOW" "Usage: use-template.sh <command> [args...]"
        echo
        echo "Commands:"
        echo "  list              - List all available templates"
        echo "  <name>            - Display template content"
        echo "  <name> <params>   - Expand template with parameters"
        exit 1
    fi

    local command="$1"
    shift || true

    case "$command" in
        list|ls|-l)
            list_templates
            ;;
        help|-h|--help)
            print_color "$CYAN" "use-template.sh - Template expansion utility"
            echo
            echo "Usage:"
            echo "  use-template.sh list                    - Show available templates"
            echo "  use-template.sh <name>                  - Display template content"
            echo "  use-template.sh <name> <params...>      - Expand template with params"
            echo
            echo "Examples:"
            echo "  use-template.sh list"
            echo "  use-template.sh search-code"
            echo "  use-template.sh search-code 'def authenticate' src/"
            ;;
        *)
            if [[ $# -eq 0 ]]; then
                display_template "$command"
            else
                expand_template "$command" "$@"
            fi
            ;;
    esac
}

main "$@"
