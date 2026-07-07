#!/usr/bin/env bash
# kontur-talk-video.sh — скачивает MP4 записи Контур.Толк через API.
# Usage: kontur-talk-video.sh <recording_url> <output.mp4> [quality]
#   quality: highest (default), 900p, 240p и т.д.
#
# Авторизация: $KTALK_SESSION_TOKEN env var (см. kontur-talk-transcript.sh)
# Эндпоинт: GET /recording-blob/{id}/{quality}
# Верифицирован 2026-05-12 на реальном ktalk-tenant'е; работает на любом *.ktalk.ru.

set -euo pipefail

INPUT="${1:?Kontur.Talk recording URL required}"
OUTPUT="${2:?output mp4 path required}"
QUALITY="${3:-highest}"

if [[ "$INPUT" =~ ^https?://([^/]+\.ktalk\.ru)/recordings/([A-Za-z0-9_-]+) ]]; then
  TENANT_HOST="${BASH_REMATCH[1]}"
  RECORDING_ID="${BASH_REMATCH[2]}"
else
  echo "Error: could not parse URL: $INPUT" >&2
  exit 1
fi

SESSION="${KTALK_SESSION_TOKEN:?KTALK_SESSION_TOKEN env var required}"

# Если quality=highest — разрешить через метаданные
if [[ "$QUALITY" == "highest" ]]; then
  QUALITY=$(curl -sS \
    -H "Authorization: Session ${SESSION}" \
    -H "x-platform: web" \
    "https://${TENANT_HOST}/api/recordings/${RECORDING_ID}" \
    | jq -r '.qualities[-1].name // "900p"')
fi

URL="https://${TENANT_HOST}/recording-blob/${RECORDING_ID}/${QUALITY}"

echo "Downloading $URL → $OUTPUT" >&2
curl -sS -L -o "$OUTPUT" \
  -H "Authorization: Session ${SESSION}" \
  -H "Cookie: sessionToken=${SESSION}" \
  "$URL"

if [[ ! -s "$OUTPUT" ]]; then
  echo "Error: downloaded file is empty" >&2
  exit 1
fi

SIZE=$(du -h "$OUTPUT" | cut -f1)
echo "Saved $SIZE → $OUTPUT" >&2
