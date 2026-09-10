#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_PATH="${BASE_DIR}/config/github-ids.json"

die() {
  echo "error: $*" >&2
  exit 1
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "missing command: $1"
}

require_config() {
  [[ -f "$CONFIG_PATH" ]] || die "missing config: $CONFIG_PATH"
}

cfg() {
  jq -r "$1" "$CONFIG_PATH"
}

cfg_required() {
  local value
  value="$(cfg "$1")"
  [[ -n "$value" && "$value" != "null" ]] || die "missing config value: $2"
  echo "$value"
}

usage() {
  cat <<'EOF'
Usage:
  gh-util.sh issue create --title <title> --type <bug|feature|improvement> [--body <text>] [--status <status>] [--repo <owner/name>]
  gh-util.sh issue status --issue <number|url> --status <backlog|in-progress|done> [--repo <owner/name>]
  gh-util.sh issue type --issue <number|url> --type <bug|feature|improvement> [--repo <owner/name>]
  gh-util.sh issue close --issue <number|url> [--repo <owner/name>]
EOF
}

parse_issue_ref() {
  local ref="$1"
  local repo_from_url=""
  local number=""
  if [[ "$ref" =~ ^[0-9]+$ ]]; then
    number="$ref"
  elif [[ "$ref" =~ github.com/([^/]+)/([^/]+)/issues/([0-9]+) ]]; then
    repo_from_url="${BASH_REMATCH[1]}/${BASH_REMATCH[2]}"
    number="${BASH_REMATCH[3]}"
  elif [[ "$ref" =~ \#([0-9]+)$ ]]; then
    number="${BASH_REMATCH[1]}"
  else
    die "invalid issue reference: $ref"
  fi
  echo "${repo_from_url}|${number}"
}

strip_git_suffix() {
  local name="$1"
  echo "${name%.git}"
}

resolve_repo_from_origin() {
  local origin
  origin="$(git config --get remote.origin.url 2>/dev/null || true)"
  if [[ -z "$origin" ]]; then
    return 1
  fi
  if [[ "$origin" =~ ^git@github.com:([^/]+)/([^/]+)$ ]]; then
    echo "${BASH_REMATCH[1]}/$(strip_git_suffix "${BASH_REMATCH[2]}")"
    return 0
  fi
  if [[ "$origin" =~ ^https://github.com/([^/]+)/([^/]+)$ ]]; then
    echo "${BASH_REMATCH[1]}/$(strip_git_suffix "${BASH_REMATCH[2]}")"
    return 0
  fi
  return 1
}

resolve_repo() {
  local repo_arg="$1"
  local repo_from_url="$2"
  local repo=""
  if [[ -n "$repo_arg" ]]; then
    repo="$repo_arg"
  elif [[ -n "$repo_from_url" ]]; then
    repo="$repo_from_url"
  else
    repo="$(resolve_repo_from_origin || true)"
  fi
  [[ -n "$repo" ]] || die "repo not set; pass --repo owner/name or run inside a git repo"
  echo "$repo"
}

repo_owner() {
  echo "${1%%/*}"
}

repo_name() {
  echo "${1#*/}"
}

fetch_repo_data() {
  local owner="$1"
  local name="$2"
  local query
  query='query($owner:String!, $name:String!){ repository(owner:$owner, name:$name){ id issueTypes(first:100){ nodes { id name } } } }'
  gh api graphql -f query="$query" -f owner="$owner" -f name="$name"
}

get_issue_type_name() {
  case "$1" in
    bug) echo "Bug" ;;
    feature) echo "Feature" ;;
    improvement) echo "Improvement" ;;
    *) die "unknown type: $1" ;;
  esac
}

resolve_issue_type_id() {
  local repo_data="$1"
  local type_key="$2"
  local type_name
  type_name="$(get_issue_type_name "$type_key")"
  local config_id=""
  if [[ -f "$CONFIG_PATH" ]]; then
    config_id="$(cfg ".issue_types[\"$type_key\"]" 2>/dev/null || true)"
  fi
  if [[ -n "$config_id" && "$config_id" != "null" ]]; then
    echo "$config_id"
    return 0
  fi
  local issue_type_id
  issue_type_id="$(echo "$repo_data" | jq -r --arg name "$type_name" '.data.repository.issueTypes.nodes[]? | select(.name | ascii_downcase == ($name | ascii_downcase)) | .id' | head -n1)"
  [[ -n "$issue_type_id" && "$issue_type_id" != "null" ]] || die "native issue type not found: $type_name"
  echo "$issue_type_id"
}

get_issue() {
  local owner="$1"
  local name="$2"
  local number="$3"
  local query
  query='query($owner:String!, $name:String!, $number:Int!){ repository(owner:$owner, name:$name){ issue(number:$number){ id number url } } }'
  gh api graphql -f query="$query" -f owner="$owner" -f name="$name" -F number="$number"
}

add_project_item() {
  local project_id="$1"
  local content_id="$2"
  local query
  query='mutation($projectId:ID!, $contentId:ID!){ addProjectV2ItemById(input:{ projectId:$projectId, contentId:$contentId }){ item { id } } }'
  gh api graphql -f query="$query" -f projectId="$project_id" -f contentId="$content_id"
}

find_project_item_id() {
  local project_id="$1"
  local issue_id="$2"
  local query
  query='query($issueId:ID!){ node(id:$issueId){ ... on Issue { projectItems(first:50){ nodes { id project { id } } } } } }'
  gh api graphql -f query="$query" -f issueId="$issue_id"
}

ensure_project_item() {
  local project_id="$1"
  local issue_id="$2"
  local resp
  resp="$(find_project_item_id "$project_id" "$issue_id")"
  local item_id
  item_id="$(echo "$resp" | jq -r --arg project "$project_id" '.data.node.projectItems.nodes[]? | select(.project.id == $project) | .id' | head -n1)"
  if [[ -n "$item_id" && "$item_id" != "null" ]]; then
    echo "$item_id"
    return 0
  fi
  resp="$(add_project_item "$project_id" "$issue_id")"
  item_id="$(echo "$resp" | jq -r '.data.addProjectV2ItemById.item.id')"
  [[ -n "$item_id" && "$item_id" != "null" ]] || die "failed to add issue to project"
  echo "$item_id"
}

set_project_field() {
  local project_id="$1"
  local item_id="$2"
  local field_id="$3"
  local option_id="$4"
  local query
  query='mutation($projectId:ID!, $itemId:ID!, $fieldId:ID!, $optionId:String!){ updateProjectV2ItemFieldValue(input:{ projectId:$projectId, itemId:$itemId, fieldId:$fieldId, value:{ singleSelectOptionId:$optionId } }){ projectV2Item { id } } }'
  gh api graphql -f query="$query" -f projectId="$project_id" -f itemId="$item_id" -f fieldId="$field_id" -f optionId="$option_id" >/dev/null
}

update_issue_type_native() {
  local issue_id="$1"
  local issue_type_id="$2"
  local query
  query='mutation($issueId:ID!, $issueTypeId:ID!){ updateIssue(input:{ id:$issueId, issueTypeId:$issueTypeId }){ issue { id } } }'
  gh api graphql -f query="$query" -f issueId="$issue_id" -f issueTypeId="$issue_type_id" >/dev/null
}

update_issue_state_closed() {
  local issue_id="$1"
  local query
  query='mutation($issueId:ID!){ updateIssue(input:{ id:$issueId, state:CLOSED }){ issue { id } } }'
  gh api graphql -f query="$query" -f issueId="$issue_id" >/dev/null
}

issue_create() {
  local repo=""
  local title=""
  local body=""
  local type=""
  local status=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --repo) repo="$2"; shift 2 ;;
      --title) title="$2"; shift 2 ;;
      --body) body="$2"; shift 2 ;;
      --type) type="$2"; shift 2 ;;
      --status) status="$2"; shift 2 ;;
      -h|--help) usage; exit 0 ;;
      *) die "unknown option: $1" ;;
    esac
  done

  [[ -n "$title" ]] || die "missing --title"
  [[ -n "$type" ]] || die "missing --type"

  require_config
  require_cmd gh
  require_cmd jq

  local project_id status_field type_field
  project_id="$(cfg_required '.project_id' 'project_id')"
  status_field="$(cfg_required '.status_field' 'status_field')"
  type_field="$(cfg_required '.type_field' 'type_field')"

  local repo_resolved owner name
  repo_resolved="$(resolve_repo "$repo" "")"
  owner="$(repo_owner "$repo_resolved")"
  name="$(repo_name "$repo_resolved")"

  local repo_data repo_id issue_type_id
  repo_data="$(fetch_repo_data "$owner" "$name")"
  repo_id="$(echo "$repo_data" | jq -r '.data.repository.id')"
  [[ -n "$repo_id" && "$repo_id" != "null" ]] || die "unable to resolve repository id"

  issue_type_id="$(resolve_issue_type_id "$repo_data" "$type")"

  local create_query resp issue_id issue_number issue_url
  create_query='mutation($repoId:ID!, $title:String!, $body:String!, $issueTypeId:ID!){ createIssue(input:{ repositoryId:$repoId, title:$title, body:$body, issueTypeId:$issueTypeId }){ issue { id number url } } }'
  resp="$(gh api graphql -f query="$create_query" -f repoId="$repo_id" -f title="$title" -f body="$body" -f issueTypeId="$issue_type_id")"
  issue_id="$(echo "$resp" | jq -r '.data.createIssue.issue.id')"
  issue_number="$(echo "$resp" | jq -r '.data.createIssue.issue.number')"
  issue_url="$(echo "$resp" | jq -r '.data.createIssue.issue.url')"
  [[ -n "$issue_id" && "$issue_id" != "null" ]] || die "issue creation failed"

  local item_id
  item_id="$(ensure_project_item "$project_id" "$issue_id")"

  local type_option_id
  type_option_id="$(cfg ".types[\"$type\"]")"
  [[ -n "$type_option_id" && "$type_option_id" != "null" ]] || die "unknown project type: $type"
  set_project_field "$project_id" "$item_id" "$type_field" "$type_option_id"

  if [[ -n "$status" ]]; then
    local status_option_id
    status_option_id="$(cfg ".statuses[\"$status\"]")"
    [[ -n "$status_option_id" && "$status_option_id" != "null" ]] || die "unknown status: $status"
    set_project_field "$project_id" "$item_id" "$status_field" "$status_option_id"
  fi

  echo "#${issue_number} ${issue_url}"
}

issue_status() {
  local repo=""
  local issue_ref=""
  local status=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --repo) repo="$2"; shift 2 ;;
      --issue) issue_ref="$2"; shift 2 ;;
      --status) status="$2"; shift 2 ;;
      -h|--help) usage; exit 0 ;;
      *) die "unknown option: $1" ;;
    esac
  done

  [[ -n "$issue_ref" ]] || die "missing --issue"
  [[ -n "$status" ]] || die "missing --status"

  require_config
  require_cmd gh
  require_cmd jq

  local project_id status_field
  project_id="$(cfg_required '.project_id' 'project_id')"
  status_field="$(cfg_required '.status_field' 'status_field')"

  local parsed repo_from_url number
  parsed="$(parse_issue_ref "$issue_ref")"
  repo_from_url="${parsed%%|*}"
  number="${parsed##*|}"

  local repo_resolved owner name
  repo_resolved="$(resolve_repo "$repo" "$repo_from_url")"
  owner="$(repo_owner "$repo_resolved")"
  name="$(repo_name "$repo_resolved")"

  local resp issue_id issue_url
  resp="$(get_issue "$owner" "$name" "$number")"
  issue_id="$(echo "$resp" | jq -r '.data.repository.issue.id')"
  issue_url="$(echo "$resp" | jq -r '.data.repository.issue.url')"
  [[ -n "$issue_id" && "$issue_id" != "null" ]] || die "issue not found"

  local item_id
  item_id="$(ensure_project_item "$project_id" "$issue_id")"

  local status_option_id
  status_option_id="$(cfg ".statuses[\"$status\"]")"
  [[ -n "$status_option_id" && "$status_option_id" != "null" ]] || die "unknown status: $status"
  set_project_field "$project_id" "$item_id" "$status_field" "$status_option_id"

  echo "${status} #${number} ${issue_url}"
}

issue_type() {
  local repo=""
  local issue_ref=""
  local type=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --repo) repo="$2"; shift 2 ;;
      --issue) issue_ref="$2"; shift 2 ;;
      --type) type="$2"; shift 2 ;;
      -h|--help) usage; exit 0 ;;
      *) die "unknown option: $1" ;;
    esac
  done

  [[ -n "$issue_ref" ]] || die "missing --issue"
  [[ -n "$type" ]] || die "missing --type"

  require_config
  require_cmd gh
  require_cmd jq

  local project_id type_field
  project_id="$(cfg_required '.project_id' 'project_id')"
  type_field="$(cfg_required '.type_field' 'type_field')"

  local parsed repo_from_url number
  parsed="$(parse_issue_ref "$issue_ref")"
  repo_from_url="${parsed%%|*}"
  number="${parsed##*|}"

  local repo_resolved owner name
  repo_resolved="$(resolve_repo "$repo" "$repo_from_url")"
  owner="$(repo_owner "$repo_resolved")"
  name="$(repo_name "$repo_resolved")"

  local repo_data resp issue_id issue_url issue_type_id
  repo_data="$(fetch_repo_data "$owner" "$name")"
  resp="$(get_issue "$owner" "$name" "$number")"
  issue_id="$(echo "$resp" | jq -r '.data.repository.issue.id')"
  issue_url="$(echo "$resp" | jq -r '.data.repository.issue.url')"
  [[ -n "$issue_id" && "$issue_id" != "null" ]] || die "issue not found"

  issue_type_id="$(resolve_issue_type_id "$repo_data" "$type")"
  update_issue_type_native "$issue_id" "$issue_type_id"

  local item_id
  item_id="$(ensure_project_item "$project_id" "$issue_id")"

  local type_option_id
  type_option_id="$(cfg ".types[\"$type\"]")"
  [[ -n "$type_option_id" && "$type_option_id" != "null" ]] || die "unknown project type: $type"
  set_project_field "$project_id" "$item_id" "$type_field" "$type_option_id"

  echo "${type} #${number} ${issue_url}"
}

issue_close() {
  local repo=""
  local issue_ref=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --repo) repo="$2"; shift 2 ;;
      --issue) issue_ref="$2"; shift 2 ;;
      -h|--help) usage; exit 0 ;;
      *) die "unknown option: $1" ;;
    esac
  done

  [[ -n "$issue_ref" ]] || die "missing --issue"

  require_cmd gh
  require_cmd jq

  local parsed repo_from_url number
  parsed="$(parse_issue_ref "$issue_ref")"
  repo_from_url="${parsed%%|*}"
  number="${parsed##*|}"

  local repo_resolved owner name
  repo_resolved="$(resolve_repo "$repo" "$repo_from_url")"
  owner="$(repo_owner "$repo_resolved")"
  name="$(repo_name "$repo_resolved")"

  local resp issue_id issue_url
  resp="$(get_issue "$owner" "$name" "$number")"
  issue_id="$(echo "$resp" | jq -r '.data.repository.issue.id')"
  issue_url="$(echo "$resp" | jq -r '.data.repository.issue.url')"
  [[ -n "$issue_id" && "$issue_id" != "null" ]] || die "issue not found"

  update_issue_state_closed "$issue_id"
  echo "closed #${number} ${issue_url}"
}

main() {
  local cmd="${1:-}"
  local sub="${2:-}"
  if [[ -z "$cmd" || "$cmd" == "-h" || "$cmd" == "--help" ]]; then
    usage
    exit 0
  fi
  case "$cmd" in
    issue)
      shift
      case "$sub" in
        create) shift; issue_create "$@" ;;
        status) shift; issue_status "$@" ;;
        type) shift; issue_type "$@" ;;
        close) shift; issue_close "$@" ;;
        *) die "unknown issue command: $sub" ;;
      esac
      ;;
    *) die "unknown command: $cmd" ;;
  esac
}

main "$@"
