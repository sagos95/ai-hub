#!/bin/bash
# env-manager.sh — safe .env file management (never outputs actual values)
#
# Usage: ./env-manager.sh <command> [args...]
#   check              — report set/missing status for all known vars
#   set KEY VALUE      — add or update a key in .env (no duplicates)
#   has KEY            — exit 0 if KEY is set and non-empty, 1 otherwise
#   migrate            — rename .env.local → .env if applicable
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../../.." && pwd)"
ENV_FILE="$ROOT_DIR/.env"
ENV_LOCAL_FILE="$ROOT_DIR/.env.local"

# Known variable groups
COMPANY_CONFIG=(KAITEN_DOMAIN TIME_BASE_URL BUILDIN_SPACE_ID)
COMPANY_OPTIONAL=(GENIE_HOST GENIE_SPACE_ID)
PERSONAL_TOKENS=(KAITEN_TOKEN BUILDIN_UI_TOKEN TIME_TOKEN)
PERSONAL_OPTIONAL=(GENIE_TOKEN TIME_BOT_TOKEN)

load_env() {
    if [[ -f "$ENV_FILE" ]]; then
        set -a
        source "$ENV_FILE"
        set +a
    fi
}

check_var() {
    local key="$1"
    local val="${!key}"
    if [[ -n "$val" && "$val" != your_* && "$val" != your-* && "$val" != YOUR_* ]]; then
        echo "$key=set"
    else
        echo "$key=missing"
    fi
}

cmd_check() {
    load_env

    echo "=== Company Config ==="
    for key in "${COMPANY_CONFIG[@]}"; do
        check_var "$key"
    done

    echo ""
    echo "=== Company Config (optional) ==="
    for key in "${COMPANY_OPTIONAL[@]}"; do
        check_var "$key"
    done

    echo ""
    echo "=== Personal Tokens ==="
    for key in "${PERSONAL_TOKENS[@]}"; do
        check_var "$key"
    done

    echo ""
    echo "=== Personal Tokens (optional) ==="
    for key in "${PERSONAL_OPTIONAL[@]}"; do
        check_var "$key"
    done
}

cmd_set() {
    local key="$1"
    local value="$2"

    if [[ -z "$key" || -z "$value" ]]; then
        echo "Usage: env-manager.sh set KEY VALUE" >&2
        exit 1
    fi

    # Validate key format
    if [[ ! "$key" =~ ^[A-Z_][A-Z0-9_]*$ ]]; then
        echo "Error: invalid key format (expected UPPER_SNAKE_CASE)" >&2
        exit 1
    fi

    touch "$ENV_FILE"

    if grep -q "^${key}=" "$ENV_FILE" 2>/dev/null; then
        # Update existing key (portable sed without -i)
        sed "s|^${key}=.*|${key}=${value}|" "$ENV_FILE" > "${ENV_FILE}.tmp" \
            && mv "${ENV_FILE}.tmp" "$ENV_FILE"
        echo "updated:$key"
    else
        echo "${key}=${value}" >> "$ENV_FILE"
        echo "added:$key"
    fi
}

cmd_has() {
    local key="$1"

    if [[ -z "$key" ]]; then
        echo "Usage: env-manager.sh has KEY" >&2
        exit 1
    fi

    load_env
    local val="${!key}"
    if [[ -n "$val" && "$val" != your_* && "$val" != your-* && "$val" != YOUR_* ]]; then
        exit 0
    else
        exit 1
    fi
}

cmd_migrate() {
    if [[ -f "$ENV_LOCAL_FILE" && ! -f "$ENV_FILE" ]]; then
        mv "$ENV_LOCAL_FILE" "$ENV_FILE"
        echo "migrated:.env.local -> .env"
    elif [[ -f "$ENV_LOCAL_FILE" && -f "$ENV_FILE" ]]; then
        echo "warning:both .env and .env.local exist — merge manually" >&2
        exit 1
    else
        echo "ok:nothing to migrate"
    fi
}

# --- Main ---
COMMAND="${1:-help}"
shift 2>/dev/null || true

case "$COMMAND" in
    check)   cmd_check ;;
    set)     cmd_set "$1" "$2" ;;
    has)     cmd_has "$1" ;;
    migrate) cmd_migrate ;;
    help|*)
        echo "env-manager.sh — safe .env management (never outputs values)"
        echo ""
        echo "Commands:"
        echo "  check              — report set/missing status for all known vars"
        echo "  set KEY VALUE      — add or update a key in .env"
        echo "  has KEY            — exit 0 if set, 1 if missing"
        echo "  migrate            — rename .env.local -> .env if applicable"
        ;;
esac
