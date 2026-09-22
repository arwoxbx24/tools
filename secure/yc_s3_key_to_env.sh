#!/usr/bin/env bash
set -euo pipefail

if (( $# < 2 )); then
  printf 'Usage: %s SA_NAME BUCKET [OUT] [DESC]\n' "$0" >&2
  exit 1
fi

SA_NAME=$1
BUCKET=$2
OUT=${3:-/root/workspaces/secrets/yandex-s3.env}
DESC=${4:-"restic server-backup $(date +%F)"}
YC=/root/yandex-cloud/bin/yc

if [[ -e $OUT ]]; then
  printf 'Refusing to overwrite existing file: %s\n' "$OUT" >&2
  exit 2
fi

OUT_DIR=$(dirname "$OUT")
if [[ ! -d $OUT_DIR ]]; then
  printf 'Output directory does not exist: %s\n' "$OUT_DIR" >&2
  exit 1
fi

JSON=$("$YC" iam access-key create --service-account-name "$SA_NAME" --description "$DESC" --format json)

umask 077
TMP=$(mktemp "$OUT_DIR/.yandex-s3.env.XXXXXX")
trap 'rm -f "$TMP"' EXIT

jq -er --arg date "$(date +%F)" --arg sa "$SA_NAME" --arg bucket "$BUCKET" '
  .access_key.id as $id
  | .access_key.key_id as $key_id
  | .secret as $secret
  | "# generated \($date); service account \($sa); access key id \($id)",
    "AWS_ACCESS_KEY_ID=\($key_id)",
    "AWS_SECRET_ACCESS_KEY=\($secret)",
    "AWS_DEFAULT_REGION=ru-central1",
    "S3_ENDPOINT=https://storage.yandexcloud.net",
    "S3_BUCKET=\($bucket)",
    "RESTIC_REPOSITORY=s3:https://storage.yandexcloud.net/\($bucket)"
' <<<"$JSON" >"$TMP"

chmod 600 "$TMP"
mv "$TMP" "$OUT"
trap - EXIT

KEY_ID=$(jq -er '.access_key.key_id' <<<"$JSON")
LINE_COUNT=$(wc -l <"$OUT" | tr -d '[:space:]')
printf '%s\n%s\n%s\n' "$OUT" "$KEY_ID" "$LINE_COUNT"
