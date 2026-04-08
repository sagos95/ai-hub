#!/bin/bash
# Логин в Time — получает токен и сохраняет в .env
#
# Usage: ./time-login.sh          — интерактивный выбор способа
#        ./time-login.sh password  — логин по email/паролю
#        ./time-login.sh sso       — вставить токен из браузера вручную
#        /ai-hub:time-login        — автоматически через DevTools (рекомендуется для SSO)
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../../.." && pwd)"
ENV_FILE="$ROOT_DIR/.env"
TIME_BASE_URL="${TIME_BASE_URL:-https://your-company.time-messenger.ru}"

save_token() {
    local TOKEN="$1"

    # Verify token works
    VERIFY=$(curl -s -w "\n%{http_code}" \
        -H "Authorization: Bearer $TOKEN" \
        "${TIME_BASE_URL}/api/v4/users/me")

    HTTP_CODE=$(echo "$VERIFY" | tail -1)
    USER_INFO=$(echo "$VERIFY" | sed '$d')

    if [[ "$HTTP_CODE" != "200" ]]; then
        echo "Error: Токен невалидный (HTTP $HTTP_CODE)" >&2
        return 1
    fi

    USERNAME=$(echo "$USER_INFO" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("username",""))' 2>/dev/null)
    EMAIL=$(echo "$USER_INFO" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("email",""))' 2>/dev/null)

    echo "Залогинен как @${USERNAME} (${EMAIL})"
    echo ""

    # Save to .env
    touch "$ENV_FILE"

    if grep -q '^TIME_TOKEN=' "$ENV_FILE" 2>/dev/null; then
        sed -i '' "s|^TIME_TOKEN=.*|TIME_TOKEN=${TOKEN}|" "$ENV_FILE"
        echo "TIME_TOKEN обновлён в $ENV_FILE"
    else
        echo "" >> "$ENV_FILE"
        echo "# Time (Mattermost) personal session token" >> "$ENV_FILE"
        echo "TIME_TOKEN=${TOKEN}" >> "$ENV_FILE"
        echo "TIME_TOKEN добавлен в $ENV_FILE"
    fi

    echo ""
    echo "Готово! Проверка:"
    echo "  integrations/time/scripts/time-channels.sh my-teams | jq '.[].display_name'"
}

login_password() {
    read -p "Email или username: " LOGIN_ID
    read -s -p "Пароль: " PASSWORD
    echo ""

    if [[ -z "$LOGIN_ID" || -z "$PASSWORD" ]]; then
        echo "Error: email и пароль обязательны" >&2
        exit 1
    fi

    LOGIN_BODY=$(python3 -c "import json,sys; print(json.dumps({'login_id': sys.argv[1], 'password': sys.argv[2]}))" "$LOGIN_ID" "$PASSWORD")

    echo "Логинюсь в ${TIME_BASE_URL}..."

    # Try v4 login
    RESPONSE=$(curl -s -D - \
        -X POST \
        -H "Content-Type: application/json" \
        -d "$LOGIN_BODY" \
        "${TIME_BASE_URL}/api/v4/users/login" 2>&1)

    TOKEN=$(echo "$RESPONSE" | grep -i '^token:' | tr -d '[:space:]' | cut -d: -f2)

    # Fallback to v5
    if [[ -z "$TOKEN" ]]; then
        RESPONSE=$(curl -s -D - \
            -X POST \
            -H "Content-Type: application/json" \
            -d "$LOGIN_BODY" \
            "${TIME_BASE_URL}/api/v5/auth/login" 2>&1)

        TOKEN=$(echo "$RESPONSE" | grep -i 'MMAUTHTOKEN' | sed 's/.*MMAUTHTOKEN=//I' | sed 's/;.*//' | tr -d '[:space:]')
        if [[ -z "$TOKEN" ]]; then
            TOKEN=$(echo "$RESPONSE" | grep -i '^token:' | tr -d '[:space:]' | cut -d: -f2)
        fi
    fi

    if [[ -z "$TOKEN" ]]; then
        echo "Error: Логин не удался. Проверь email и пароль." >&2
        HTTP_STATUS=$(echo "$RESPONSE" | grep -i '^HTTP/' | tail -1)
        echo "HTTP: $HTTP_STATUS" >&2
        exit 1
    fi

    save_token "$TOKEN"
}

login_sso() {
    echo "Как получить токен из браузера:"
    echo ""
    echo "  1. Открой ${TIME_BASE_URL} и залогинься через Google SSO"
    echo "  2. Открой DevTools (F12 или Cmd+Option+I)"
    echo "  3. Один из способов:"
    echo ""
    echo "     Способ A — Cookie (рекомендуется):"
    echo "       DevTools → Application → Cookies → ${TIME_BASE_URL}"
    echo "       Найди MMAUTHTOKEN → скопируй Value"
    echo ""
    echo "     Способ B — Network:"
    echo "       DevTools → Network → кликни любой запрос к api/"
    echo "       Headers → Authorization: Bearer <вот этот токен>"
    echo ""
    echo "     ⚠️ document.cookie не работает — MMAUTHTOKEN это httpOnly cookie"
    echo ""

    read -p "Вставь токен: " TOKEN
    TOKEN=$(echo "$TOKEN" | tr -d '[:space:]')

    if [[ -z "$TOKEN" ]]; then
        echo "Error: токен не может быть пустым" >&2
        exit 1
    fi

    save_token "$TOKEN"
}

# --- Main ---

echo "=== Time Login ==="
echo ""

MODE="${1:-}"

if [[ -z "$MODE" ]]; then
    echo "Выбери способ логина:"
    echo "  1) Google SSO — вставить токен из браузера вручную"
    echo "  2) Email + пароль"
    echo ""
    echo "  Или используй /ai-hub:time-login для автоматического"
    echo "  извлечения токена через Chrome DevTools (рекомендуется для SSO)"
    echo ""
    read -p "Выбор [1/2]: " CHOICE

    case "$CHOICE" in
        1) MODE="sso" ;;
        2) MODE="password" ;;
        *)
            echo "Error: выбери 1 или 2" >&2
            exit 1
            ;;
    esac
fi

case "$MODE" in
    check)
        TOKEN=""
        if [[ -f "$ENV_FILE" ]]; then
            TOKEN=$(grep '^TIME_TOKEN=' "$ENV_FILE" 2>/dev/null | head -1 | cut -d= -f2-)
        fi
        if [[ -z "$TOKEN" ]]; then
            echo "error:no_token"
            exit 1
        fi
        VERIFY=$(curl -s -w "\n%{http_code}" \
            -H "Authorization: Bearer $TOKEN" \
            "${TIME_BASE_URL}/api/v4/users/me")
        HTTP_CODE=$(echo "$VERIFY" | tail -1)
        USER_INFO=$(echo "$VERIFY" | sed '$d')
        if [[ "$HTTP_CODE" != "200" ]]; then
            echo "error:token_expired (HTTP $HTTP_CODE)"
            exit 1
        fi
        USERNAME=$(echo "$USER_INFO" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("username",""))' 2>/dev/null)
        EMAIL=$(echo "$USER_INFO" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("email",""))' 2>/dev/null)
        echo "ok @${USERNAME} (${EMAIL})"
        ;;
    sso)      login_sso ;;
    password) login_password ;;
    *)
        echo "Usage: $0 [check|sso|password]" >&2
        exit 1
        ;;
esac
