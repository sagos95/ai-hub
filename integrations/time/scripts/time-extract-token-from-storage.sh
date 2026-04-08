#!/bin/bash
# Извлекает MMAUTHTOKEN из Playwright storage-state JSON файла,
# валидирует и сохраняет в .env.
# Токен НЕ выводится в stdout — LLM видит только статус.
#
# Usage: ./time-extract-token-from-storage.sh <storage-state.json>
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../../.." && pwd)"
ENV_FILE="$ROOT_DIR/.env"
TIME_BASE_URL="${TIME_BASE_URL:-https://your-company.time-messenger.ru}"

if [[ -f "$ENV_FILE" ]]; then
    set -a
    source "$ENV_FILE"
    set +a
    TIME_BASE_URL="${TIME_BASE_URL:-https://your-company.time-messenger.ru}"
fi

STORAGE_FILE="${1}"

if [[ -z "$STORAGE_FILE" ]]; then
    echo "error:no_storage_file" >&2
    exit 1
fi

if [[ ! -f "$STORAGE_FILE" ]]; then
    echo "error:file_not_found $STORAGE_FILE" >&2
    exit 1
fi

TOKEN=$(python3 -c "
import json, sys
with open(sys.argv[1]) as f:
    data = json.load(f)
for cookie in data.get('cookies', []):
    if cookie.get('name') == 'MMAUTHTOKEN':
        print(cookie['value'])
        sys.exit(0)
sys.exit(1)
" "$STORAGE_FILE" 2>/dev/null)

if [[ -z "$TOKEN" ]]; then
    echo "error:no_mmauthtoken"
    exit 1
fi

# Validate token
VERIFY=$(curl -s -w "\n%{http_code}" \
    -H "Authorization: Bearer $TOKEN" \
    "${TIME_BASE_URL}/api/v4/users/me")

HTTP_CODE=$(echo "$VERIFY" | tail -1)
USER_INFO=$(echo "$VERIFY" | sed '$d')

if [[ "$HTTP_CODE" != "200" ]]; then
    echo "error:validation_failed (HTTP $HTTP_CODE)"
    exit 1
fi

USERNAME=$(echo "$USER_INFO" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("username",""))' 2>/dev/null)
EMAIL=$(echo "$USER_INFO" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("email",""))' 2>/dev/null)

# Save to .env
touch "$ENV_FILE"

if grep -q '^TIME_TOKEN=' "$ENV_FILE" 2>/dev/null; then
    sed -i '' "s|^TIME_TOKEN=.*|TIME_TOKEN=${TOKEN}|" "$ENV_FILE"
else
    echo "" >> "$ENV_FILE"
    echo "# Time (Mattermost) personal session token" >> "$ENV_FILE"
    echo "TIME_TOKEN=${TOKEN}" >> "$ENV_FILE"
fi

# Clean up storage state file (contains sensitive cookies)
rm -f "$STORAGE_FILE"

echo "ok @${USERNAME} (${EMAIL})"
