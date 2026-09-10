#!/usr/bin/env bash
set +e

# Portainer API helper script
# Usage:
#   portainer-api.sh auth                     — get JWT token (prints token)
#   portainer-api.sh endpoints                — list endpoints
#   portainer-api.sh containers [endpoint_id] — list containers
#   portainer-api.sh start <endpoint_id> <container_id>  — start container
#   portainer-api.sh stop <endpoint_id> <container_id>   — stop container
#   portainer-api.sh stacks [endpoint_id]     — list stacks
#   portainer-api.sh create-stack <endpoint_id> <stack_file> — deploy stack from compose file
#   portainer-api.sh raw <method> <path> [data] — raw API call

SECRETS_FILE="/root/workspaces/secrets/services/portainer.env"

if [ ! -f "$SECRETS_FILE" ]; then
  echo "ERROR: Portainer credentials not found at $SECRETS_FILE" >&2
  exit 2
fi

source "$SECRETS_FILE"

ACTION="$1"
shift

# Get JWT token
get_token() {
  local token
  token=$(curl -sk "$PORTAINER_URL/api/auth" \
    -H "Content-Type: application/json" \
    -d "{\"username\":\"$PORTAINER_USER\",\"password\":\"$PORTAINER_PASS\"}" \
    2>/dev/null | jq -r '.jwt // empty')

  if [ -z "$token" ]; then
    echo "ERROR: Authentication failed" >&2
    return 1
  fi
  echo "$token"
}

# API call with auth
api_call() {
  local method="$1"
  local path="$2"
  local data="$3"
  local token
  token=$(get_token) || return 1

  if [ -n "$data" ]; then
    curl -sk -X "$method" \
      -H "Authorization: Bearer $token" \
      -H "Content-Type: application/json" \
      -d "$data" \
      "$PORTAINER_URL/api$path" 2>/dev/null
  else
    curl -sk -X "$method" \
      -H "Authorization: Bearer $token" \
      "$PORTAINER_URL/api$path" 2>/dev/null
  fi
}

case "$ACTION" in
  auth)
    token=$(get_token) || exit 1
    echo "$token"
    ;;

  endpoints)
    api_call GET "/endpoints" | jq '.[].Id, .[].Name'
    ;;

  containers)
    endpoint_id="${1:-1}"
    api_call GET "/endpoints/$endpoint_id/docker/containers/json?all=true" | \
      jq -r '.[] | "\(.Id[:12]) \(.State) \(.Names[0]) \(.Image)"'
    ;;

  images)
    endpoint_id="${1:-1}"
    api_call GET "/endpoints/$endpoint_id/docker/images/json" | \
      jq -r '.[] | "\(.Id[:19]) \(.RepoTags[0] // "none")"'
    ;;

  start)
    endpoint_id="$1"
    container_id="$2"
    if [ -z "$endpoint_id" ] || [ -z "$container_id" ]; then
      echo "Usage: portainer-api.sh start <endpoint_id> <container_id>" >&2
      exit 2
    fi
    api_call POST "/endpoints/$endpoint_id/docker/containers/$container_id/start"
    echo "Started: $container_id"
    ;;

  stop)
    endpoint_id="$1"
    container_id="$2"
    if [ -z "$endpoint_id" ] || [ -z "$container_id" ]; then
      echo "Usage: portainer-api.sh stop <endpoint_id> <container_id>" >&2
      exit 2
    fi
    api_call POST "/endpoints/$endpoint_id/docker/containers/$container_id/stop"
    echo "Stopped: $container_id"
    ;;

  stacks)
    endpoint_id="${1:-}"
    if [ -n "$endpoint_id" ]; then
      api_call GET "/stacks" | jq -r ".[] | select(.EndpointId == $endpoint_id) | \"\(.Id) \(.Name) \(.Status)\""
    else
      api_call GET "/stacks" | jq -r '.[] | "\(.Id) \(.Name) \(.Status) endpoint=\(.EndpointId)"'
    fi
    ;;

  create-stack)
    endpoint_id="$1"
    stack_file="$2"
    if [ -z "$endpoint_id" ] || [ -z "$stack_file" ]; then
      echo "Usage: portainer-api.sh create-stack <endpoint_id> <compose_file>" >&2
      exit 2
    fi
    if [ ! -f "$stack_file" ]; then
      echo "ERROR: Stack file not found: $stack_file" >&2
      exit 2
    fi
    compose_content
    compose_content=$(cat "$stack_file" | jq -Rs .)
    stack_name
    stack_name=$(basename "$stack_file" .yml | sed 's/docker-compose-//')
    api_call POST "/stacks/create/standalone/string?type=2&method=string&endpointId=$endpoint_id" \
      "{\"name\":\"$stack_name\",\"stackFileContent\":$compose_content}"
    ;;

  raw)
    raw_method="$1"
    raw_path="$2"
    raw_data="$3"
    api_call "$raw_method" "$raw_path" "$raw_data"
    ;;

  *)
    echo "Portainer API Helper"
    echo ""
    echo "Usage: portainer-api.sh <command> [args]"
    echo ""
    echo "Commands:"
    echo "  auth                          — get JWT token"
    echo "  endpoints                     — list endpoints"
    echo "  containers [endpoint_id]      — list all containers"
    echo "  images [endpoint_id]          — list images"
    echo "  start <endpoint_id> <id>      — start container"
    echo "  stop <endpoint_id> <id>       — stop container"
    echo "  stacks [endpoint_id]          — list stacks"
    echo "  create-stack <eid> <file>     — deploy compose stack"
    echo "  raw <method> <path> [data]    — raw API call"
    ;;
esac
