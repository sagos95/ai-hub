#!/bin/bash
# Buildin Login — проверка/сохранение UI-токена
#
# Usage: ./buildin-login.sh check        — проверить существующий токен
#        ./buildin-login.sh save <token>  — проверить и сохранить токен
#        ./buildin-login.sh clipboard     — прочитать токен из буфера обмена
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../../.." && pwd)"
ENV_FILE="$ROOT_DIR/.env"
BUILDIN_BASE_URL="https://buildin.ai"

# Load existing env
if [[ -f "$ENV_FILE" ]]; then
    set -a
    source "$ENV_FILE"
    set +a
fi

verify_token() {
    local TOKEN="$1"
    VERIFY=$(curl -s -w "\n%{http_code}" \
        -H "Authorization: Bearer $TOKEN" \
        -H "x-platform: web-cookie" \
        -H "x-app-origin: web" \
        -H "x-product: buildin" \
        "${BUILDIN_BASE_URL}/api/users/me")

    HTTP_CODE=$(echo "$VERIFY" | tail -1)
    USER_INFO=$(echo "$VERIFY" | sed '$d')

    if [[ "$HTTP_CODE" != "200" ]]; then
        return 1
    fi

    # Check API-level code
    API_CODE=$(echo "$USER_INFO" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("code",0))' 2>/dev/null)
    if [[ "$API_CODE" != "200" ]]; then
        return 1
    fi

    echo "$USER_INFO"
    return 0
}

extract_user_info() {
    local USER_INFO="$1"
    NICKNAME=$(echo "$USER_INFO" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("data",{}).get("nickname",""))' 2>/dev/null)
    EMAIL=$(echo "$USER_INFO" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("data",{}).get("email",""))' 2>/dev/null)
}

save_token_to_env() {
    local TOKEN="$1"
    touch "$ENV_FILE"

    if grep -q '^BUILDIN_UI_TOKEN=' "$ENV_FILE" 2>/dev/null; then
        sed -i '' "s|^BUILDIN_UI_TOKEN=.*|BUILDIN_UI_TOKEN=${TOKEN}|" "$ENV_FILE"
    else
        echo "" >> "$ENV_FILE"
        echo "# Buildin UI token (JWT from next_auth cookie, 30-day expiry)" >> "$ENV_FILE"
        echo "BUILDIN_UI_TOKEN=${TOKEN}" >> "$ENV_FILE"
    fi
}

# --- Main ---
MODE="${1:-}"

case "$MODE" in
    check)
        TOKEN="${BUILDIN_UI_TOKEN:-}"
        if [[ -z "$TOKEN" ]]; then
            echo "error:no_token"
            exit 1
        fi
        USER_INFO=$(verify_token "$TOKEN") || {
            echo "error:token_expired"
            exit 1
        }
        extract_user_info "$USER_INFO"
        echo "ok ${NICKNAME} (${EMAIL})"
        ;;

    save)
        TOKEN="${2:-}"
        if [[ -z "$TOKEN" ]]; then
            echo "error:no_token_argument" >&2
            exit 1
        fi
        TOKEN=$(echo "$TOKEN" | tr -d '[:space:]')

        USER_INFO=$(verify_token "$TOKEN") || {
            echo "error:validation_failed" >&2
            exit 1
        }
        extract_user_info "$USER_INFO"
        save_token_to_env "$TOKEN"
        echo "ok ${NICKNAME} (${EMAIL})"
        ;;

    clipboard)
        TOKEN=$(pbpaste 2>/dev/null | tr -d '[:space:]')
        if [[ -z "$TOKEN" ]]; then
            echo "error:clipboard_empty" >&2
            exit 1
        fi
        if [[ ${#TOKEN} -lt 50 ]]; then
            echo "error:not_a_jwt (too short: ${#TOKEN} chars)" >&2
            exit 1
        fi

        USER_INFO=$(verify_token "$TOKEN") || {
            echo "error:validation_failed" >&2
            exit 1
        }
        extract_user_info "$USER_INFO"
        save_token_to_env "$TOKEN"

        # Clear clipboard
        echo -n "" | pbcopy
        echo "ok ${NICKNAME} (${EMAIL})"
        ;;

    *)
        echo "Usage: $0 [check|save <token>|clipboard]" >&2
        exit 1
        ;;
esac
