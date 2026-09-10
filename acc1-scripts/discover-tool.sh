#!/bin/bash
# discover-tool.sh — Check if a tool/program is available
# Usage: discover-tool.sh <name>
# Returns: path + version OR "NOT_FOUND: install suggestion"
set +e

NAME="${1:?Usage: discover-tool.sh <name>}"

# 1. Check binary in PATH
BIN=$(command -v "$NAME" 2>/dev/null)
if [ -n "$BIN" ]; then
    VERSION=$("$NAME" --version 2>/dev/null | head -1 || echo "unknown")
    echo "FOUND: $BIN ($VERSION)"
    exit 0
fi

# 2. Check pip package
PIP_INFO=$(pip3 show "$NAME" 2>/dev/null | grep -E "^(Name|Version|Location)" || true)
if [ -n "$PIP_INFO" ]; then
    echo "FOUND (pip): $PIP_INFO"
    exit 0
fi

# 3. Check npm global
NPM_INFO=$(npm list -g "$NAME" 2>/dev/null | grep "$NAME" || true)
if [ -n "$NPM_INFO" ]; then
    echo "FOUND (npm): $NPM_INFO"
    exit 0
fi

# 4. Check docker container
DOCKER_INFO=$(docker ps --format "{{.Names}}" 2>/dev/null | grep -i "$NAME" || true)
if [ -n "$DOCKER_INFO" ]; then
    echo "FOUND (docker): $DOCKER_INFO"
    exit 0
fi

# 5. Check PM2 process
PM2_INFO=$(pm2 jlist 2>/dev/null | jq -r ".[] | select(.name | test(\"$NAME\"; \"i\")) | .name + \" (\" + .pm2_env.status + \")\"" 2>/dev/null || true)
if [ -n "$PM2_INFO" ]; then
    echo "FOUND (pm2): $PM2_INFO"
    exit 0
fi

# 6. Check dpkg
DPKG_INFO=$(dpkg -l 2>/dev/null | grep -i "$NAME" | head -1 || true)
if [ -n "$DPKG_INFO" ]; then
    echo "FOUND (dpkg): $DPKG_INFO"
    exit 0
fi

# Not found
echo "NOT_FOUND: $NAME"
echo "Install options:"
echo "  apt: sudo apt install $NAME"
echo "  pip: pip3 install $NAME"
echo "  npm: npm install -g $NAME"
echo "  snap: snap install $NAME"
exit 1
