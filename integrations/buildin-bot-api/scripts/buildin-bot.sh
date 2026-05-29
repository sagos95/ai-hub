#!/bin/bash
# Buildin Bot API CLI — HTTP client for Official Bot API (api.buildin.ai/v1/)
#
# Usage: ./buildin-bot.sh <METHOD> <ENDPOINT> [JSON_BODY]
# Example: ./buildin-bot.sh GET /v1/users/me
#          ./buildin-bot.sh GET /v1/pages/<page_id>
#          ./buildin-bot.sh GET /v1/blocks/<block_id>/children
#
# Auth: Bearer token via BUILDIN_BOT_TOKEN in .env
# Token: Buildin → Settings → Integrations → Create bot → Copy token
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../hub-meta/scripts/load-env.sh
source "$SCRIPT_DIR/../../hub-meta/scripts/load-env.sh"
hub_load_env "$SCRIPT_DIR"

BUILDIN_BOT_BASE_URL="${BUILDIN_BOT_BASE_URL:-https://api.buildin.ai}"

if [[ -z "$BUILDIN_BOT_TOKEN" ]]; then
    echo "Error: BUILDIN_BOT_TOKEN not set." >&2
    echo "Get token: Buildin → Settings → Integrations → Create bot → Copy token" >&2
    echo "Then: source integrations/hub-meta/scripts/load-env.sh && hub_load_env . && integrations/sagos95-ai-hub/integrations/hub-meta/scripts/env-manager.sh set BUILDIN_BOT_TOKEN <token>" >&2
    exit 1
fi

METHOD="${1:-GET}"
ENDPOINT="${2}"
BODY="$3"

if [[ -z "$ENDPOINT" ]]; then
    echo "Usage: ./buildin-bot.sh <METHOD> <ENDPOINT> [JSON_BODY]" >&2
    echo "Example: ./buildin-bot.sh GET /v1/users/me" >&2
    echo "         ./buildin-bot.sh GET /v1/pages/<page_id>" >&2
    echo "         ./buildin-bot.sh GET /v1/blocks/<block_id>/children" >&2
    exit 1
fi

CURL_ARGS=(
    -s
    -X "$METHOD"
    -H "Authorization: Bearer $BUILDIN_BOT_TOKEN"
    -H "Content-Type: application/json"
)

if [[ -n "$BODY" ]]; then
    CURL_ARGS+=(-d "$BODY")
fi

response=$(curl "${CURL_ARGS[@]}" -w "\n%{http_code}" "${BUILDIN_BOT_BASE_URL}${ENDPOINT}")

http_code=$(echo "$response" | tail -n1)
body=$(echo "$response" | sed '$d')

if [[ "$http_code" == "401" ]]; then
    echo "Error: Unauthorized. Check BUILDIN_BOT_TOKEN." >&2
    exit 1
fi

if [[ "$http_code" == "403" ]]; then
    echo "Error: Forbidden. Bot may not have access to this page. Share the page with the bot first." >&2
    echo "$body" >&2
    exit 1
fi

if [[ "$http_code" == "429" ]]; then
    echo "Error: Rate limited. Try again later." >&2
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
