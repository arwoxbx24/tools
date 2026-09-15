#!/usr/bin/env bash
set -euo pipefail

if (( $# != 2 )); then
  printf 'Usage: %s SRC NAME\n' "$0" >&2
  exit 1
fi

SRC=$1
NAME=$2
DST=/root/workspaces/secrets/$NAME

if [[ $SRC != /* || ! -f $SRC || -L $SRC ]]; then
  printf 'Source must be an absolute regular non-symlink file: %s\n' "$SRC" >&2
  exit 1
fi

if [[ -z $NAME || $NAME == */* || $NAME == . || $NAME == .. ]]; then
  printf 'NAME must be a file name without slashes: %s\n' "$NAME" >&2
  exit 1
fi

if [[ -e $DST || -L $DST ]]; then
  printf 'Refusing to overwrite existing file: %s\n' "$DST" >&2
  exit 2
fi

mv -- "$SRC" "$DST"
chmod 600 -- "$DST"
ln -s -- "$DST" "$SRC"

if [[ $(readlink -f -- "$SRC") != "$DST" ]]; then
  printf 'Symlink verification failed: %s\n' "$SRC" >&2
  exit 1
fi

printf '%s\n%s\n%s\n' "$SRC" "$DST" "$(stat -c %s -- "$DST")"
