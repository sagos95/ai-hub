#!/bin/bash
# Buildin UI API CLI — HTTP-клиент для UI API (buildin.ai/api/)
#
# Usage: ./buildin.sh <METHOD> <ENDPOINT> [JSON_BODY]
# Example: ./buildin.sh GET /api/users/me
#          ./buildin.sh GET /api/docs/<page_id>
#          ./buildin.sh POST /api/records/transactions '{"requestId":"...","transactions":[...]}'
#
# Auth: Bearer JWT via BUILDIN_UI_TOKEN in .env
# Login: /ai-hub:buildin-login
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../hub-meta/scripts/load-env.sh
source "$SCRIPT_DIR/../../hub-meta/scripts/load-env.sh"
hub_load_env "$SCRIPT_DIR"

BUILDIN_BASE_URL="https://buildin.ai"

# Check token
if [[ -z "$BUILDIN_UI_TOKEN" ]]; then
    echo "Error: BUILDIN_UI_TOKEN not set. Run /ai-hub:buildin-login first." >&2
    exit 1
fi

METHOD="${1:-GET}"
ENDPOINT="${2}"
BODY="$3"

if [[ -z "$ENDPOINT" ]]; then
    echo "Usage: ./buildin.sh <METHOD> <ENDPOINT> [JSON_BODY]" >&2
    echo "Example: ./buildin.sh GET /api/users/me" >&2
    echo "         ./buildin.sh GET /api/docs/<page_id>" >&2
    exit 1
fi

CURL_ARGS=(
    -s
    -X "$METHOD"
    -H "Authorization: Bearer $BUILDIN_UI_TOKEN"
    -H "Content-Type: application/json"
    -H "x-platform: web-cookie"
    -H "x-app-origin: web"
    -H "x-product: buildin"
    -H "app_version_name: 1.146.0"
)

if [[ -n "$BODY" ]]; then
    CURL_ARGS+=(-d "$BODY")
fi

response=$(curl "${CURL_ARGS[@]}" -w "\n%{http_code}" "${BUILDIN_BASE_URL}${ENDPOINT}")

http_code=$(echo "$response" | tail -n1)
body=$(echo "$response" | sed '$d')

if [[ "$http_code" == "401" ]]; then
    echo "Error: Token expired. Run /ai-hub:buildin-login to re-authenticate." >&2
    exit 1
fi

if [[ "$http_code" -ge 400 ]]; then
    echo "Error: HTTP $http_code" >&2
    echo "$body" >&2
    exit 1
fi

if command -v jq &> /dev/null; then
    echo "$body" | jq . 2>/dev/null || echo "$body"
else
    echo "$body"
fi
