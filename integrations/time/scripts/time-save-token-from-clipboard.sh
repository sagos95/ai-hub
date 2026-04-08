#!/bin/bash
# Читает токен из буфера обмена, проверяет и сохраняет в .env
# Вызывается после того, как JS в браузере скопировал MMAUTHTOKEN в clipboard
#
# Usage: ./time-save-token-from-clipboard.sh
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../../.." && pwd)"
ENV_FILE="$ROOT_DIR/.env"
TIME_BASE_URL="${TIME_BASE_URL:-https://your-company.time-messenger.ru}"

# Load existing env (for TIME_BASE_URL override)
if [[ -f "$ENV_FILE" ]]; then
    set -a
    source "$ENV_FILE"
    set +a
    TIME_BASE_URL="${TIME_BASE_URL:-https://your-company.time-messenger.ru}"
fi

# Read token from clipboard
TOKEN=$(pbpaste 2>/dev/null | tr -d '[:space:]')

if [[ -z "$TOKEN" ]]; then
    echo "Error: буфер обмена пуст" >&2
    exit 1
fi

# Basic sanity check (Mattermost tokens are 26-char alphanumeric)
if [[ ${#TOKEN} -lt 20 ]]; then
    echo "Error: значение из буфера не похоже на токен (слишком короткое: ${#TOKEN} символов)" >&2
    exit 1
fi

# Verify token against API
VERIFY=$(curl -s -w "\n%{http_code}" \
    -H "Authorization: Bearer $TOKEN" \
    "${TIME_BASE_URL}/api/v4/users/me")

HTTP_CODE=$(echo "$VERIFY" | tail -1)
USER_INFO=$(echo "$VERIFY" | sed '$d')

if [[ "$HTTP_CODE" != "200" ]]; then
    echo "Error: токен невалидный (HTTP $HTTP_CODE)" >&2
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

# Clear clipboard
echo -n "" | pbcopy

echo "ok @${USERNAME} (${EMAIL})"
