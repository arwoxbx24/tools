#!/bin/bash
# Mover into the secrets store (spec:054).
# Usage: move-into-secrets.sh [--dry-run] <source> <relative-path>
# Root is /root/workspaces/secrets (override with SECRETS_ROOT for tests).
# Never reads or prints the file content.
set -u

ROOT=${SECRETS_ROOT:-/root/workspaces/secrets}

SRC=""
REL=""
DRY=0
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY=1 ;;
    -*)
      echo "unknown option: $arg" >&2
      exit 2
      ;;
    *)
      if [ -z "$SRC" ]; then
        SRC="$arg"
      elif [ -z "$REL" ]; then
        REL="$arg"
      else
        echo "too many arguments" >&2
        exit 2
      fi
      ;;
  esac
done

if [ -z "$SRC" ] || [ -z "$REL" ]; then
  echo "usage: $0 [--dry-run] <source> <relative-path>" >&2
  exit 2
fi

# The relative path must not be absolute.
case "$REL" in
  /*)
    echo "relative path must not be absolute: $REL" >&2
    exit 2
    ;;
esac

# Source must exist and be a regular file.
if [ ! -e "$SRC" ]; then
  echo "source not found: $SRC" >&2
  exit 2
fi
if [ ! -f "$SRC" ]; then
  echo "source is not a regular file: $SRC" >&2
  exit 2
fi

TARGET="$ROOT/$REL"

# Normalize and reject any target that escapes the root (.., absolute, symlink out).
RESOLVED_ROOT="$(realpath -m "$ROOT")"
RESOLVED_TARGET="$(realpath -m "$TARGET")"
if [ -z "$RESOLVED_TARGET" ]; then
  echo "cannot normalize target: $TARGET" >&2
  exit 2
fi
case "$RESOLVED_TARGET" in
  "$RESOLVED_ROOT"|"$RESOLVED_ROOT"/*) : ;;
  *)
    echo "target escapes secrets root: $TARGET" >&2
    exit 2
    ;;
esac

# Overwriting an existing secret is forbidden.
if [ -e "$TARGET" ]; then
  echo "target exists: $TARGET" >&2
  exit 2
fi

NAME="$(basename "$SRC")"

if [ "$DRY" -eq 1 ]; then
  echo "moved $NAME -> $TARGET (600)"
  exit 0
fi

mkdir -p "$(dirname "$TARGET")" || exit 1
chmod 700 "$(dirname "$TARGET")" || exit 1
mv "$SRC" "$TARGET" || exit 1
chmod 600 "$TARGET" || exit 1

echo "moved $NAME -> $TARGET (600)"
exit 0
