#!/bin/bash
# Kaiten API CLI - универсальный скрипт для вызова Kaiten API
# Usage: ./kaiten.sh <method> <endpoint> [json_body]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../hub-meta/scripts/load-env.sh
source "$SCRIPT_DIR/../../hub-meta/scripts/load-env.sh"
hub_load_env "$SCRIPT_DIR"

# Check required env vars
if [[ -z "$KAITEN_TOKEN" ]]; then
    echo "Error: KAITEN_TOKEN environment variable must be set" >&2
    exit 1
fi

# Use KAITEN_API if set, otherwise build from KAITEN_DOMAIN
if [[ -z "$KAITEN_API" ]]; then
    if [[ -z "$KAITEN_DOMAIN" ]]; then
        echo "Error: KAITEN_API or KAITEN_DOMAIN must be set" >&2
        exit 1
    fi
    KAITEN_API="https://${KAITEN_DOMAIN}/api/latest"
fi

METHOD="${1:-GET}"
ENDPOINT="${2:-/users/current}"
BODY="$3"

# Access control levels (cumulative):
#   1 | read                — GET/HEAD only
#   2 | read_write          — + POST/PUT/PATCH (no archive)
#   3 | read_write_archive  — + card archiving (default)
#   4 | full                — + DELETE
KAITEN_ACCESS_LEVEL="${KAITEN_ACCESS_LEVEL:-read_write_archive}"

METHOD_UPPER=$(echo "$METHOD" | tr '[:lower:]' '[:upper:]')

access_level_num() {
    case "$KAITEN_ACCESS_LEVEL" in
        1|read|READ|read_only|READ_ONLY) echo 1 ;;
        2|read_write|READ_WRITE) echo 2 ;;
        3|read_write_archive|READ_WRITE_ARCHIVE) echo 3 ;;
        4|full|FULL|read_write_archive_delete|READ_WRITE_ARCHIVE_DELETE) echo 4 ;;
        *) echo 0 ;;
    esac
}

is_card_archive_operation() {
    if [[ "$ENDPOINT" == *"/archive"* ]]; then
        return 0
    fi
    if [[ "$ENDPOINT" =~ ^/cards/[0-9]+$ ]]; then
        if [[ "$METHOD_UPPER" == "PATCH" || "$METHOD_UPPER" == "PUT" ]]; then
            if echo "$BODY" | grep -Eq '"archived"[[:space:]]*:[[:space:]]*(true|1)'; then
                return 0
            fi
        fi
    fi
    return 1
}

# Safe DELETE operations allowed at read_write_archive level:
# - Tag removal from cards: /cards/{id}/tags/{tag_id}
# - Checklist item removal: /cards/{id}/checklists/{id}/items/{id}
# - Card blocker removal: /cards/{id}/blockers/{id}
# - Member removal from cards: /cards/{id}/members/{member_id}
is_safe_delete_operation() {
    if [[ "$ENDPOINT" =~ ^/cards/[0-9]+/tags/[0-9]+$ ]]; then
        return 0
    fi
    if [[ "$ENDPOINT" =~ ^/cards/[0-9]+/checklists/[0-9]+/items/[0-9]+$ ]]; then
        return 0
    fi
    if [[ "$ENDPOINT" =~ ^/cards/[0-9]+/blockers/[0-9]+$ ]]; then
        return 0
    fi
    if [[ "$ENDPOINT" =~ ^/cards/[0-9]+/members/[0-9]+$ ]]; then
        return 0
    fi
    return 1
}

LEVEL=$(access_level_num)

if [[ "$LEVEL" -eq 0 ]]; then
    echo "Error: Unknown KAITEN_ACCESS_LEVEL='$KAITEN_ACCESS_LEVEL'. Valid: read, read_write, read_write_archive (default), full" >&2
    exit 1
fi

case "$METHOD_UPPER" in
    GET|HEAD)
        ;; # level >= 1, always allowed
    POST|PUT|PATCH)
        if [[ "$LEVEL" -lt 2 ]]; then
            echo "Error: Write access denied (KAITEN_ACCESS_LEVEL=$KAITEN_ACCESS_LEVEL). Set to read_write or higher." >&2
            exit 1
        fi
        if is_card_archive_operation && [[ "$LEVEL" -lt 3 ]]; then
            echo "Error: Archive access denied (KAITEN_ACCESS_LEVEL=$KAITEN_ACCESS_LEVEL). Set to read_write_archive or higher." >&2
            exit 1
        fi
        ;;
    DELETE)
        if [[ "$LEVEL" -ge 3 ]] && is_safe_delete_operation; then
            : # Safe deletes allowed at read_write_archive level
        elif [[ "$LEVEL" -lt 4 ]]; then
            echo "Error: Delete access denied (KAITEN_ACCESS_LEVEL=$KAITEN_ACCESS_LEVEL). Set to full to allow DELETE." >&2
            exit 1
        fi
        ;;
    *)
        echo "Error: Unsupported HTTP method: $METHOD" >&2
        exit 1
        ;;
esac

# Build curl command
CURL_ARGS=(
    -s
    -X "$METHOD_UPPER"
    -H "Authorization: Bearer $KAITEN_TOKEN"
    -H "Content-Type: application/json"
)

if [[ -n "$BODY" ]]; then
    CURL_ARGS+=(-d "$BODY")
fi

# Execute request
response=$(curl "${CURL_ARGS[@]}" -w "\n%{http_code}" "${KAITEN_API}${ENDPOINT}")

# Extract HTTP code (last line)
http_code=$(echo "$response" | tail -n1)
body=$(echo "$response" | sed '$d')

# Check for errors
if [[ "$http_code" -ge 400 ]]; then
    echo "Error: HTTP $http_code" >&2
    echo "$body" >&2
    exit 1
fi

# Pretty print JSON if jq is available
if command -v jq &> /dev/null; then
    echo "$body" | jq . 2>/dev/null || echo "$body"
else
    echo "$body"
fi
