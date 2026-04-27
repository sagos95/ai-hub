#!/bin/bash
# Time (Mattermost) API HTTP client — Layer 1
# Supports dual auth: bot token (TIME_BOT_TOKEN) and personal token (TIME_TOKEN)
#
# Usage: ./time.sh [--as bot|me] <METHOD> <ENDPOINT> [BODY]
# Env:   TIME_AS=bot|me (alternative to --as flag)
#
# Auth:
#   --as bot → TIME_BOT_TOKEN
#   --as me  → TIME_TOKEN (получить через time-login.sh)
#   default  → bot if TIME_BOT_TOKEN set, otherwise TIME_TOKEN
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../hub-meta/scripts/load-env.sh
source "$SCRIPT_DIR/../../hub-meta/scripts/load-env.sh"
hub_load_env "$SCRIPT_DIR"

TIME_BASE_URL="${TIME_BASE_URL:-https://your-company.time-messenger.ru}"

# Parse --as flag
AS_MODE="${TIME_AS:-}"
if [[ "$1" == "--as" ]]; then
    AS_MODE="$2"
    shift 2
fi

# Auto-detect mode
if [[ -z "$AS_MODE" ]]; then
    if [[ -n "$TIME_BOT_TOKEN" ]]; then
        AS_MODE="bot"
    elif [[ -n "$TIME_TOKEN" ]]; then
        AS_MODE="me"
    else
        echo "Error: No auth configured." >&2
        echo "  Личный аккаунт: ./integrations/time/scripts/time-login.sh" >&2
        echo "  Bot: добавь TIME_BOT_TOKEN в .env" >&2
        exit 1
    fi
fi

# Resolve token
case "$AS_MODE" in
    bot)
        if [[ -z "$TIME_BOT_TOKEN" ]]; then
            echo "Error: TIME_BOT_TOKEN not set." >&2
            echo "Create bot: Time → Menu → Integrations → Bot Accounts → Add Bot Account" >&2
            exit 1
        fi
        AUTH_TOKEN="$TIME_BOT_TOKEN"
        ;;
    me)
        if [[ -z "$TIME_TOKEN" ]]; then
            echo "Error: TIME_TOKEN not set. Залогинься:" >&2
            echo "  ./integrations/time/scripts/time-login.sh" >&2
            exit 1
        fi
        AUTH_TOKEN="$TIME_TOKEN"
        ;;
    *)
        echo "Error: Unknown mode '$AS_MODE'. Use 'bot' or 'me'" >&2
        exit 1
        ;;
esac

# HTTP request
METHOD="${1:-GET}"
ENDPOINT="${2}"
BODY="$3"

if [[ -z "$ENDPOINT" ]]; then
    echo "Usage: $0 [--as bot|me] <METHOD> <ENDPOINT> [BODY]" >&2
    exit 1
fi

CURL_ARGS=(
    -s
    -w "\n%{http_code}"
    -X "$METHOD"
    -H "Authorization: Bearer $AUTH_TOKEN"
    -H "Content-Type: application/json"
)

[[ -n "$BODY" ]] && CURL_ARGS+=(-d "$BODY")

RESPONSE=$(curl "${CURL_ARGS[@]}" "${TIME_BASE_URL}${ENDPOINT}")

HTTP_CODE=$(echo "$RESPONSE" | tail -1)
BODY_RESPONSE=$(echo "$RESPONSE" | sed '$d')

if [[ "$HTTP_CODE" == "401" && "$AS_MODE" == "me" ]]; then
    echo "Error: Токен просрочен. Перелогинься:" >&2
    echo "  ./integrations/time/scripts/time-login.sh" >&2
    exit 1
fi

if [[ "$HTTP_CODE" -ge 400 ]]; then
    echo "Error: HTTP $HTTP_CODE (mode=$AS_MODE)" >&2
    echo "$BODY_RESPONSE" >&2
    exit 1
fi

echo "$BODY_RESPONSE"
