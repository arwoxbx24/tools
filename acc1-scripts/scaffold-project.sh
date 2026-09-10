#!/bin/bash
# =============================================================================
# scaffold-project.sh — Create project structure from YAML scaffold templates
# =============================================================================
# Usage: scaffold-project.sh <project-name> <scaffold-type> [description]
#        scaffold-project.sh --list
#        scaffold-project.sh --info <scaffold-type>
# =============================================================================

set +e

SCAFFOLDS_DIR="/root/workspaces/tools/acc1-scripts/scaffolds"
PROJECTS_DIR="/root/claude-projects"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# =====================================================================
# SHOW LIST OF AVAILABLE SCAFFOLDS
# =====================================================================
show_list() {
    local registry="$SCAFFOLDS_DIR/registry.yaml"

    if [[ ! -f "$registry" ]]; then
        echo -e "${RED}ERROR: registry.yaml not found${NC}"
        exit 1
    fi

    echo -e "${GREEN}Available scaffolds:${NC}"
    echo ""

    local current_name=""
    while IFS= read -r line; do
        # Extract name
        if [[ "$line" =~ ^[[:space:]]*-[[:space:]]*name:[[:space:]]*(.+)$ ]]; then
            current_name="${BASH_REMATCH[1]}"
        fi

        # Extract description
        if [[ "$line" =~ ^[[:space:]]*description:[[:space:]]*(.+)$ ]] && [[ -n "$current_name" ]]; then
            local desc="${BASH_REMATCH[1]}"
            printf "  ${BLUE}%-18s${NC} — %s\n" "$current_name" "$desc"
            current_name=""
        fi
    done < "$registry"

    echo ""
}

# =====================================================================
# SHOW INFO ABOUT SPECIFIC SCAFFOLD
# =====================================================================
show_info() {
    local scaffold_type="$1"
    local scaffold_file="$SCAFFOLDS_DIR/${scaffold_type}.yaml"

    if [[ ! -f "$scaffold_file" ]]; then
        echo -e "${RED}ERROR: Scaffold '$scaffold_type' not found${NC}"
        echo ""
        show_list
        exit 1
    fi

    echo -e "${GREEN}Scaffold: ${BLUE}$scaffold_type${NC}"
    echo ""

    # Parse and show basic info
    local name="" language="" framework="" description=""

    while IFS= read -r line; do
        if [[ "$line" =~ ^name:[[:space:]]*(.+)$ ]]; then
            name="${BASH_REMATCH[1]}"
        elif [[ "$line" =~ ^language:[[:space:]]*(.+)$ ]]; then
            language="${BASH_REMATCH[1]}"
        elif [[ "$line" =~ ^framework:[[:space:]]*(.+)$ ]]; then
            framework="${BASH_REMATCH[1]}"
        elif [[ "$line" =~ ^description:[[:space:]]*(.+)$ ]]; then
            description="${BASH_REMATCH[1]}"
        fi
    done < "$scaffold_file"

    echo "Name:        $name"
    echo "Language:    $language"
    echo "Framework:   $framework"
    echo "Description: $description"
    echo ""

    # Show structure preview
    echo -e "${YELLOW}Directory structure:${NC}"
    grep -E "^  - " "$scaffold_file" | grep -v "path:" | head -20
    echo ""

    echo -e "${YELLOW}Files:${NC}"
    grep -E "^  - path:" "$scaffold_file" | sed 's/  - path: /  /' | head -20
    echo ""
}

# =====================================================================
# VALIDATE PROJECT NAME
# =====================================================================
validate_project_name() {
    local name="$1"

    # Check format: alphanumeric, hyphens, underscores
    if [[ ! "$name" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        echo -e "${RED}ERROR: Invalid project name '$name'${NC}"
        echo "Format: alphanumeric characters, hyphens, underscores only"
        exit 1
    fi

    # Check if exists
    if [[ -d "$PROJECTS_DIR/$name" ]]; then
        echo -e "${RED}ERROR: Project '$name' already exists${NC}"
        exit 1
    fi
}

# =====================================================================
# PARSE YAML WITH STATE MACHINE
# =====================================================================
parse_yaml() {
    local yaml_file="$1"
    local project_name="$2"
    local description="$3"

    # Initialize state
    local state="INIT"
    local current_file_path=""
    local current_file_content=""
    local claude_md_content=""

    # Storage arrays (simulate with temp files)
    local temp_dir="/tmp/scaffold-$$"
    mkdir -p "$temp_dir"/{dirs,files,vars}

    local dir_count=0
    local file_count=0

    # Read line by line
    while IFS= read -r line; do
        # State transitions
        if [[ "$line" =~ ^directories: ]]; then
            state="DIRS"
            continue
        elif [[ "$line" =~ ^files: ]]; then
            state="FILES"
            continue
        elif [[ "$line" =~ ^claude_md:[[:space:]]*\| ]]; then
            state="CLAUDE_MD"
            claude_md_content=""
            continue
        elif [[ "$line" =~ ^variables: ]]; then
            state="VARS"
            continue
        fi

        # Process based on state
        case "$state" in
            INIT)
                # Store metadata
                if [[ "$line" =~ ^name:[[:space:]]*(.+)$ ]]; then
                    echo "${BASH_REMATCH[1]}" > "$temp_dir/meta_name"
                elif [[ "$line" =~ ^language:[[:space:]]*(.+)$ ]]; then
                    echo "${BASH_REMATCH[1]}" > "$temp_dir/meta_language"
                elif [[ "$line" =~ ^framework:[[:space:]]*(.+)$ ]]; then
                    echo "${BASH_REMATCH[1]}" > "$temp_dir/meta_framework"
                fi
                ;;

            DIRS)
                # Directory list: lines starting with "  - "
                if [[ "$line" =~ ^[[:space:]]{2}-[[:space:]]+(.+)$ ]]; then
                    local dir="${BASH_REMATCH[1]}"
                    echo "$dir" > "$temp_dir/dirs/dir_${dir_count}"
                    ((dir_count++)) || true
                elif [[ "$line" =~ ^[a-z] ]]; then
                    # New section started
                    state="INIT"
                fi
                ;;

            FILES)
                # File entries: "  - path: xxx" followed by "    content: |"
                if [[ "$line" =~ ^[[:space:]]{2}-[[:space:]]+path:[[:space:]]+(.+)$ ]]; then
                    # Save previous file if exists
                    if [[ -n "$current_file_path" ]]; then
                        echo "$current_file_content" > "$temp_dir/files/file_${file_count}"
                        echo "$current_file_path" > "$temp_dir/files/path_${file_count}"
                        ((file_count++)) || true
                    fi

                    current_file_path="${BASH_REMATCH[1]}"
                    current_file_content=""
                    state="FILE_PATH"
                elif [[ "$line" =~ ^[a-z] ]]; then
                    # Save last file and exit FILES state
                    if [[ -n "$current_file_path" ]]; then
                        echo "$current_file_content" > "$temp_dir/files/file_${file_count}"
                        echo "$current_file_path" > "$temp_dir/files/path_${file_count}"
                        ((file_count++)) || true
                        current_file_path=""
                        current_file_content=""
                    fi
                    state="INIT"
                fi
                ;;

            FILE_PATH)
                # Look for "    content: |" (multiline) or "    content: "..." (inline)
                if [[ "$line" =~ ^[[:space:]]{4}content:[[:space:]]*\| ]]; then
                    state="FILE_CONTENT"
                elif [[ "$line" =~ ^[[:space:]]{4}content:[[:space:]]*\"(.*)\"$ ]]; then
                    # Inline content (e.g. content: "" or content: "text")
                    current_file_content="${BASH_REMATCH[1]}"
                    echo "$current_file_content" > "$temp_dir/files/file_${file_count}"
                    echo "$current_file_path" > "$temp_dir/files/path_${file_count}"
                    ((file_count++)) || true
                    current_file_path=""
                    current_file_content=""
                    state="FILES"
                elif [[ "$line" =~ ^[[:space:]]{2}-[[:space:]]+path:[[:space:]]+(.+)$ ]]; then
                    # Next file without content for previous — save empty file
                    echo "" > "$temp_dir/files/file_${file_count}"
                    echo "$current_file_path" > "$temp_dir/files/path_${file_count}"
                    ((file_count++)) || true
                    current_file_path="${BASH_REMATCH[1]}"
                    current_file_content=""
                    state="FILE_PATH"
                fi
                ;;

            FILE_CONTENT)
                # Collect indented lines (content)
                if [[ "$line" =~ ^[[:space:]]{6}(.*)$ ]]; then
                    local content_line="${BASH_REMATCH[1]}"
                    current_file_content+="$content_line"$'\n'
                elif [[ "$line" =~ ^[[:space:]]{2}-[[:space:]]+path: ]]; then
                    # Next file started
                    if [[ -n "$current_file_path" ]]; then
                        echo "$current_file_content" > "$temp_dir/files/file_${file_count}"
                        echo "$current_file_path" > "$temp_dir/files/path_${file_count}"
                        ((file_count++)) || true
                    fi

                    # Extract new path
                    if [[ "$line" =~ ^[[:space:]]{2}-[[:space:]]+path:[[:space:]]+(.+)$ ]]; then
                        current_file_path="${BASH_REMATCH[1]}"
                        current_file_content=""
                        state="FILE_PATH"
                    fi
                elif [[ "$line" =~ ^[a-z] ]]; then
                    # New section
                    if [[ -n "$current_file_path" ]]; then
                        echo "$current_file_content" > "$temp_dir/files/file_${file_count}"
                        echo "$current_file_path" > "$temp_dir/files/path_${file_count}"
                        ((file_count++)) || true
                        current_file_path=""
                        current_file_content=""
                    fi
                    state="INIT"
                fi
                ;;

            CLAUDE_MD)
                # Collect indented lines for CLAUDE.md
                if [[ "$line" =~ ^[[:space:]]{2}(.*)$ ]]; then
                    local md_line="${BASH_REMATCH[1]}"
                    claude_md_content+="$md_line"$'\n'
                elif [[ "$line" =~ ^[a-z] ]]; then
                    # Save and exit
                    echo "$claude_md_content" > "$temp_dir/claude_md"
                    state="INIT"
                fi
                ;;

            VARS)
                # Variables: "  key: value"
                if [[ "$line" =~ ^[[:space:]]{2}([a-zA-Z0-9_]+):[[:space:]]*(.+)$ ]]; then
                    local var_name="${BASH_REMATCH[1]}"
                    local var_value="${BASH_REMATCH[2]}"
                    echo "$var_value" > "$temp_dir/vars/$var_name"
                elif [[ "$line" =~ ^[a-z] ]]; then
                    state="INIT"
                fi
                ;;
        esac
    done < "$yaml_file"

    # Save last file if pending
    if [[ -n "$current_file_path" ]]; then
        echo "$current_file_content" > "$temp_dir/files/file_${file_count}"
        echo "$current_file_path" > "$temp_dir/files/path_${file_count}"
        ((file_count++)) || true
    fi

    # Save CLAUDE.md if pending
    if [[ -n "$claude_md_content" ]]; then
        echo "$claude_md_content" > "$temp_dir/claude_md"
    fi

    # Store counts
    echo "$dir_count" > "$temp_dir/dir_count"
    echo "$file_count" > "$temp_dir/file_count"

    # Return temp dir path
    echo "$temp_dir"
}

# =====================================================================
# APPLY VARIABLE SUBSTITUTION
# =====================================================================
apply_variables() {
    local content="$1"
    local temp_dir="$2"
    local project_name="$3"
    local description="$4"

    # Built-in variables
    content="${content//\{PROJECT_NAME\}/$project_name}"
    content="${content//\{DESCRIPTION\}/$description}"
    content="${content//\{DATE\}/$(date +%Y-%m-%d)}"

    # Custom variables from vars/ directory
    if [[ -d "$temp_dir/vars" ]]; then
        for var_file in "$temp_dir/vars"/*; do
            if [[ -f "$var_file" ]]; then
                local var_name=$(basename "$var_file")
                local var_value=$(cat "$var_file")
                content="${content//\{$var_name\}/$var_value}"
            fi
        done
    fi

    echo "$content"
}

# =====================================================================
# CREATE PROJECT
# =====================================================================
create_project() {
    local project_name="$1"
    local scaffold_type="$2"
    local description="$3"

    local scaffold_file="$SCAFFOLDS_DIR/${scaffold_type}.yaml"

    # Check scaffold exists
    if [[ ! -f "$scaffold_file" ]]; then
        echo -e "${RED}ERROR: Scaffold '$scaffold_type' not found${NC}"
        echo ""
        show_list
        exit 1
    fi

    # Validate project name
    validate_project_name "$project_name"

    local project_dir="$PROJECTS_DIR/$project_name"

    # Parse base scaffold if extends is used
    local base_temp_dir=""
    if grep -q "^extends: _base" "$scaffold_file"; then
        local base_file="$SCAFFOLDS_DIR/_base.yaml"
        if [[ -f "$base_file" ]]; then
            base_temp_dir=$(parse_yaml "$base_file" "$project_name" "$description")
        fi
    fi

    # Parse main scaffold
    local temp_dir=$(parse_yaml "$scaffold_file" "$project_name" "$description")

    # Read metadata
    local language=$(cat "$temp_dir/meta_language" 2>/dev/null || echo "unknown")
    local framework=$(cat "$temp_dir/meta_framework" 2>/dev/null || echo "none")
    local scaffold_name=$(cat "$temp_dir/meta_name" 2>/dev/null || echo "$scaffold_type")

    echo -e "${GREEN}✓ Scaffold: ${BLUE}$scaffold_type${NC} ($language / $framework)"
    echo -e "${GREEN}✓ Project: ${BLUE}$project_name${NC}"
    echo ""

    # Create project root
    mkdir -p "$project_dir"

    # Create project.yaml metadata
    cat > "$project_dir/project.yaml" << EOF
name: $project_name
description: ${description:-$project_name}
scaffold: $scaffold_type
language: $language
framework: $framework
created: $(date +%Y-%m-%d)
EOF

    # Create directories (base + main)
    local total_dirs=0

    if [[ -n "$base_temp_dir" ]]; then
        local base_dir_count=$(cat "$base_temp_dir/dir_count" 2>/dev/null || echo 0)
        for ((i=0; i<base_dir_count; i++)); do
            local dir=$(cat "$base_temp_dir/dirs/dir_$i" 2>/dev/null)
            if [[ -n "$dir" ]]; then
                mkdir -p "$project_dir/$dir"
                ((total_dirs++)) || true
            fi
        done
    fi

    local dir_count=$(cat "$temp_dir/dir_count" 2>/dev/null || echo 0)
    for ((i=0; i<dir_count; i++)); do
        local dir=$(cat "$temp_dir/dirs/dir_$i" 2>/dev/null)
        if [[ -n "$dir" ]]; then
            mkdir -p "$project_dir/$dir"
            ((total_dirs++)) || true
        fi
    done

    # Create files (base + main)
    local total_files=0

    if [[ -n "$base_temp_dir" ]]; then
        local base_file_count=$(cat "$base_temp_dir/file_count" 2>/dev/null || echo 0)
        for ((i=0; i<base_file_count; i++)); do
            local file_path=$(cat "$base_temp_dir/files/path_$i" 2>/dev/null)
            local file_content=$(cat "$base_temp_dir/files/file_$i" 2>/dev/null)

            if [[ -n "$file_path" ]]; then
                # Apply variables
                file_content=$(apply_variables "$file_content" "$base_temp_dir" "$project_name" "$description")

                # Write file
                echo -n "$file_content" > "$project_dir/$file_path"

                # Make executable if .sh
                [[ "$file_path" == *.sh ]] && chmod +x "$project_dir/$file_path"

                ((total_files++)) || true
            fi
        done
    fi

    local file_count=$(cat "$temp_dir/file_count" 2>/dev/null || echo 0)
    for ((i=0; i<file_count; i++)); do
        local file_path=$(cat "$temp_dir/files/path_$i" 2>/dev/null)
        local file_content=$(cat "$temp_dir/files/file_$i" 2>/dev/null)

        if [[ -n "$file_path" ]]; then
            # Apply variables
            file_content=$(apply_variables "$file_content" "$temp_dir" "$project_name" "$description")

            # Write file
            echo -n "$file_content" > "$project_dir/$file_path"

            # Make executable if .sh
            [[ "$file_path" == *.sh ]] && chmod +x "$project_dir/$file_path"

            ((total_files++)) || true
        fi
    done

    # Create CLAUDE.md
    local claude_md=$(cat "$temp_dir/claude_md" 2>/dev/null)
    if [[ -z "$claude_md" && -n "$base_temp_dir" ]]; then
        claude_md=$(cat "$base_temp_dir/claude_md" 2>/dev/null)
    fi

    if [[ -n "$claude_md" ]]; then
        claude_md=$(apply_variables "$claude_md" "$temp_dir" "$project_name" "$description")
        echo -n "$claude_md" > "$project_dir/CLAUDE.md"
        ((total_files++)) || true
    fi

    # Cleanup temp dirs
    rm -rf "$temp_dir"
    [[ -n "$base_temp_dir" ]] && rm -rf "$base_temp_dir"

    # Show tree
    echo "Created structure:"
    echo "  $project_dir/"

    # Show tree with proper formatting
    (cd "$project_dir" && find . -type f -o -type d | sort | sed 's|^\./|  |' | head -50)

    echo ""
    echo -e "${GREEN}Files: $total_files | Directories: $total_dirs | Scaffold: $scaffold_type${NC}"
    echo ""
}

# =====================================================================
# MAIN
# =====================================================================
main() {
    # Parse arguments
    if [[ $# -eq 0 ]]; then
        echo "Usage: $0 <project-name> <scaffold-type> [description]"
        echo "       $0 --list"
        echo "       $0 --info <scaffold-type>"
        echo ""
        show_list
        exit 0
    fi

    case "$1" in
        --list)
            show_list
            ;;
        --info)
            if [[ -z "$2" ]]; then
                echo -e "${RED}ERROR: --info requires scaffold-type${NC}"
                exit 1
            fi
            show_info "$2"
            ;;
        *)
            local project_name="$1"
            local scaffold_type="$2"
            local description="${3:-}"

            if [[ -z "$scaffold_type" ]]; then
                echo -e "${RED}ERROR: scaffold-type required${NC}"
                echo ""
                show_list
                exit 1
            fi

            create_project "$project_name" "$scaffold_type" "$description"
            ;;
    esac
}

main "$@"

# =============================================================================
# INTEGRITY
# =============================================================================
# PARENT: /root/workspaces/tools/acc1-scripts/scaffolds/
# DOCUMENT: scaffold-project.sh
# VERSION: 20260215-v2
# GENERATED: 2026-02-15
# PURPOSE: YAML-based project scaffolding with state machine parser
# =============================================================================
