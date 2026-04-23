#!/bin/bash
# Buildin Login — проверка/сохранение UI-токена
#
# Usage: ./buildin-login.sh check                     — проверить существующий токен
#        ./buildin-login.sh save <token>              — проверить и сохранить токен
#        ./buildin-login.sh clipboard                 — прочитать токен из буфера обмена (flaky на macOS)
#        ./buildin-login.sh bridge-start              — поднять одноразовый HTTP-мост на 127.0.0.1:<port>
#        ./buildin-login.sh bridge-wait [timeout_sec] — дождаться токена из моста и сохранить
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../../.." && pwd)"
ENV_FILE="$ROOT_DIR/.env"
CACHE_DIR="$ROOT_DIR/integrations/buildin/.cache"
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

# --- HTTP bridge for automated token handover from browser → .env ---
# Replaces the flaky clipboard path. Browser MCP evaluate_script fetches POST
# into 127.0.0.1:<port>, listener writes body to a file, bridge-wait saves it.

bridge_start() {
    mkdir -p "$CACHE_DIR"

    # Kill any prior listener still running
    if [[ -f "$CACHE_DIR/bridge.pid" ]]; then
        local old_pid
        old_pid=$(cat "$CACHE_DIR/bridge.pid" 2>/dev/null || echo "")
        [[ -n "$old_pid" ]] && kill "$old_pid" 2>/dev/null || true
    fi
    rm -f "$CACHE_DIR/bridge.token" "$CACHE_DIR/bridge.log" \
          "$CACHE_DIR/bridge.pid"   "$CACHE_DIR/bridge.port"

    # Pick a free port in 40000-59999
    local port
    local try
    for try in 1 2 3 4 5 6 7 8 9 10; do
        port=$((40000 + RANDOM % 20000))
        if ! lsof -iTCP:"$port" -sTCP:LISTEN >/dev/null 2>&1; then
            break
        fi
        port=""
    done
    if [[ -z "$port" ]]; then
        echo "error:no_free_port" >&2
        exit 1
    fi

    local listener="$SCRIPT_DIR/buildin-bridge-listener.py"
    if [[ ! -f "$listener" ]]; then
        echo "error:listener_missing ($listener)" >&2
        exit 1
    fi

    # Start in background, fully detached
    nohup python3 "$listener" "$port" "$CACHE_DIR/bridge.token" \
        > "$CACHE_DIR/bridge.log" 2>&1 &
    local pid=$!
    disown 2>/dev/null || true

    echo "$pid"  > "$CACHE_DIR/bridge.pid"
    echo "$port" > "$CACHE_DIR/bridge.port"

    # Wait up to ~2s for the listener to bind
    for try in 1 2 3 4 5 6 7 8 9 10; do
        if lsof -iTCP:"$port" -sTCP:LISTEN -p "$pid" >/dev/null 2>&1; then
            echo "port:$port"
            echo "pid:$pid"
            echo "ready:bridge listening at http://127.0.0.1:$port/"
            return 0
        fi
        sleep 0.2
    done

    echo "error:listener_failed_to_bind" >&2
    [[ -s "$CACHE_DIR/bridge.log" ]] && sed 's/^/listener-log: /' "$CACHE_DIR/bridge.log" >&2
    kill "$pid" 2>/dev/null || true
    exit 1
}

bridge_wait() {
    local timeout="${1:-180}"

    if [[ ! -f "$CACHE_DIR/bridge.pid" ]]; then
        echo "error:no_bridge_running" >&2
        exit 1
    fi
    local pid
    pid=$(cat "$CACHE_DIR/bridge.pid")

    # Poll for listener exit (exits after handling the one expected request)
    local elapsed=0
    while kill -0 "$pid" 2>/dev/null; do
        if (( elapsed >= timeout )); then
            kill "$pid" 2>/dev/null || true
            rm -f "$CACHE_DIR/bridge.pid" "$CACHE_DIR/bridge.port"
            echo "error:timeout (waited ${timeout}s for token)" >&2
            exit 1
        fi
        sleep 1
        elapsed=$((elapsed + 1))
    done

    local token_file="$CACHE_DIR/bridge.token"
    if [[ ! -s "$token_file" ]]; then
        rm -f "$CACHE_DIR/bridge.pid" "$CACHE_DIR/bridge.port"
        echo "error:no_token_received" >&2
        exit 1
    fi

    local TOKEN
    TOKEN=$(tr -d '[:space:]' < "$token_file")

    # Scrub ALL traces before any early return (token must not linger on disk)
    rm -f "$token_file" "$CACHE_DIR/bridge.pid" "$CACHE_DIR/bridge.port" "$CACHE_DIR/bridge.log"

    if [[ ${#TOKEN} -lt 50 ]]; then
        echo "error:not_a_jwt (too short: ${#TOKEN} chars)" >&2
        exit 1
    fi

    local USER_INFO
    USER_INFO=$(verify_token "$TOKEN") || {
        echo "error:validation_failed" >&2
        exit 1
    }

    extract_user_info "$USER_INFO"
    save_token_to_env "$TOKEN"
    echo "ok ${NICKNAME} (${EMAIL})"
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

    bridge-start)
        bridge_start
        ;;

    bridge-wait)
        bridge_wait "${2:-180}"
        ;;

    *)
        echo "Usage: $0 [check|save <token>|clipboard|bridge-start|bridge-wait [timeout_sec]]" >&2
        exit 1
        ;;
esac
