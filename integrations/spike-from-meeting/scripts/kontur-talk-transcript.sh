#!/usr/bin/env bash
# kontur-talk-transcript.sh — забирает транскрипт записи Контур.Толк через API.
# Usage: kontur-talk-transcript.sh <recording_url>
#   <recording_url> — полный URL вида https://<tenant>.ktalk.ru/recordings/<id>
#                     или https://talk.kontur.ru/recordings/<id>
#
# Источник auth (cookies из браузера, в порядке убывания приоритета):
#   1. $KTALK_SESSION_TOKEN env var (если ты явно выставил)
#   2. Cookie `sessionToken` из Chrome для домена tenant'a
#
# Tenant и API_BASE определяются АВТОМАТИЧЕСКИ из URL. Эндпоинты верифицированы
# 2026-05-12 на реальном ktalk-tenant'е; должны работать на любом *.ktalk.ru.
#
# Возвращает: транскрипт в формате `HH:MM:SS<TAB>Имя<TAB>Текст` на stdout
#             + JSON-метаданные в stderr (title, duration, video_url, participants_count)

set -euo pipefail

INPUT="${1:?Kontur.Talk recording URL required, e.g. https://<tenant>.ktalk.ru/recordings/<id>}"

# --- Шаг 1: разобрать URL ---

if [[ "$INPUT" =~ ^https?://([^/]+\.ktalk\.ru)/recordings/([A-Za-z0-9_-]+) ]]; then
  TENANT_HOST="${BASH_REMATCH[1]}"
  RECORDING_ID="${BASH_REMATCH[2]}"
elif [[ "$INPUT" =~ ^https?://([^/]+\.kontur\.ru)/.*recordings/([A-Za-z0-9_-]+) ]]; then
  TENANT_HOST="${BASH_REMATCH[1]}"
  RECORDING_ID="${BASH_REMATCH[2]}"
else
  echo "Error: could not parse Kontur.Talk recording URL: $INPUT" >&2
  echo "Expected: https://<tenant>.ktalk.ru/recordings/<id>" >&2
  exit 1
fi

API_BASE="https://${TENANT_HOST}/api"

# --- Шаг 2: получить session token ---

SESSION="${KTALK_SESSION_TOKEN:-}"

if [[ -z "$SESSION" ]]; then
  # Попробовать прочитать из Chrome cookies (macOS).
  # NB: Chrome шифрует cookies; нужен либо chromium-cookies tool, либо чтение из
  # активной DevTools-сессии. Простейший fallback — попросить пользователя.
  cat >&2 <<EOF
Error: KTALK_SESSION_TOKEN not set and no Chrome cookie reader configured.

Как получить токен:
  1. Залогинься в браузере на ${TENANT_HOST} (через Google SSO)
  2. Открой DevTools → Application → Cookies → ${TENANT_HOST}
  3. Скопируй значение cookie 'sessionToken'
  4. export KTALK_SESSION_TOKEN="<значение>"
  5. Запусти скрипт повторно.

Альтернатива — забрать через chrome-devtools MCP (для агентов в Claude Code):
  mcp__chrome-devtools__navigate_page → URL записи (Google SSO пропустит автоматом)
  mcp__chrome-devtools__evaluate_script → 'document.cookie' → распарсить sessionToken
EOF
  exit 2
fi

# --- Шаг 3: вызвать /api/recordings/v2/{id}/summary (содержит transcriptionV2) ---

TMPFILE=$(mktemp -t ktalk-summary-XXXXXX)
trap 'rm -f "$TMPFILE"' EXIT

HTTP_STATUS=$(curl -sS -o "$TMPFILE" -w "%{http_code}" \
  -H "Authorization: Session ${SESSION}" \
  -H "x-platform: web" \
  -H "Accept: application/json" \
  "${API_BASE}/recordings/v2/${RECORDING_ID}/summary" || echo "000")

if [[ "$HTTP_STATUS" != "200" ]]; then
  echo "Error: HTTP $HTTP_STATUS from ${API_BASE}/recordings/v2/${RECORDING_ID}/summary" >&2
  echo "Body: $(head -c 500 "$TMPFILE")" >&2
  exit 1
fi

# Параллельно тянем метаданные (title, duration, qualities)
META_FILE=$(mktemp -t ktalk-meta-XXXXXX)
trap 'rm -f "$TMPFILE" "$META_FILE"' EXIT
curl -sS -o "$META_FILE" \
  -H "Authorization: Session ${SESSION}" \
  -H "x-platform: web" \
  "${API_BASE}/recordings/${RECORDING_ID}" || true

# --- Шаг 4: распарсить transcriptionV2 и вывести в плоском формате ---

if ! command -v jq >/dev/null 2>&1; then
  echo "Error: jq not installed. Install: brew install jq" >&2
  exit 1
fi

# Метаданные в stderr (JSON) — чтобы caller мог распарсить
jq -n \
  --arg title "$(jq -r '.title // ""' "$META_FILE")" \
  --argjson duration "$(jq -r '.duration // 0' "$META_FILE")" \
  --arg created "$(jq -r '.createdDate // ""' "$META_FILE")" \
  --argjson participants_count "$(jq -r '.participantsCount // 0' "$META_FILE")" \
  --arg highest_quality "$(jq -r '.qualities[-1].fileUrl // ""' "$META_FILE")" \
  --arg tenant_host "$TENANT_HOST" \
  '{title: $title, duration_seconds: $duration, created: $created, participants_count: $participants_count, video_url: ("https://" + $tenant_host + $highest_quality)}' >&2

# Транскрипт в stdout
jq -r '
  .transcriptionV2.tracks
  | map(. as $t | .chunks | map({
      start: (.startTimeOffsetInMillis // 0),
      text: (.text // ""),
      speaker: (
        (($t.speaker.userInfo.firstname // "") + " " + ($t.speaker.userInfo.surname // ""))
        | gsub("^ +| +$"; "")
      )
    }))
  | flatten | sort_by(.start) | .[]
  | (((.start/1000)|floor) | (
      (./3600|floor|tostring|("0"+.)|.[-2:]) + ":" +
      ((. % 3600 / 60)|floor|tostring|("0"+.)|.[-2:]) + ":" +
      (. % 60|tostring|("0"+.)|.[-2:])
    ))
  + "\t" + .speaker + "\t" + .text
' "$TMPFILE"
