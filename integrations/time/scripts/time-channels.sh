#!/bin/bash
# Time (Mattermost) Channel operations — Layer 2
# Usage: ./time-channels.sh [--as bot|me] <action> [args...]
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TIME="$SCRIPT_DIR/time.sh"
CACHE_DIR="$SCRIPT_DIR/../.cache"
CACHE_TTL=1800  # 30 minutes

# Check if cache file is fresh (within TTL)
cache_is_fresh() {
    local file="$1"
    [[ -f "$file" ]] || return 1
    local now
    now=$(date +%s)
    local mtime
    mtime=$(stat -f %m "$file" 2>/dev/null || stat -c %Y "$file" 2>/dev/null)
    (( now - mtime < CACHE_TTL ))
}

# Refresh channels cache for a team, returns cache file path
refresh_channels_cache() {
    local team_id="$1"
    local cache_file="$CACHE_DIR/channels-${team_id}.json"
    mkdir -p "$CACHE_DIR"
    if ! cache_is_fresh "$cache_file"; then
        "$TIME" "${AS_ARGS[@]}" GET "/api/v4/users/me/teams/${team_id}/channels?page=0&per_page=200" > "$cache_file"
    fi
    echo "$cache_file"
}

# Pass through --as flag
AS_ARGS=()
if [[ "$1" == "--as" ]]; then
    AS_ARGS=("--as" "$2")
    shift 2
fi

action="${1}"

case "$action" in
    me)
        "$TIME" "${AS_ARGS[@]}" GET "/api/v4/users/me"
        ;;

    my-teams)
        "$TIME" "${AS_ARGS[@]}" GET "/api/v4/users/me/teams"
        ;;

    my-channels)
        # Usage: ./time-channels.sh my-channels <team_id> [page] [per_page]
        TEAM_ID="${2:?Team ID required}"
        PAGE="${3:-0}"
        PER_PAGE="${4:-60}"
        "$TIME" "${AS_ARGS[@]}" GET "/api/v4/users/me/teams/${TEAM_ID}/channels?page=${PAGE}&per_page=${PER_PAGE}"
        ;;

    get)
        # Usage: ./time-channels.sh get <channel_id>
        CHANNEL_ID="${2:?Channel ID required}"
        "$TIME" "${AS_ARGS[@]}" GET "/api/v4/channels/${CHANNEL_ID}"
        ;;

    search)
        # Usage: ./time-channels.sh search <team_id> <term>
        TEAM_ID="${2:?Team ID required}"
        TERM="${3:?Search term required}"
        "$TIME" "${AS_ARGS[@]}" POST "/api/v4/teams/${TEAM_ID}/channels/search" "{\"term\":\"$TERM\"}"
        ;;

    find)
        # Find channel by name (searches cached my-channels, includes private)
        # Usage: ./time-channels.sh find <team_id> <term>
        TEAM_ID="${2:?Team ID required}"
        TERM="${3:?Search term required}"
        CACHE_FILE=$(refresh_channels_cache "$TEAM_ID")
        jq --arg term "$TERM" '[.[] | select(.name | test($term; "i")) | {id, display_name, name, type, purpose}]' "$CACHE_FILE"
        ;;

    members)
        # Usage: ./time-channels.sh members <channel_id> [page] [per_page]
        CHANNEL_ID="${2:?Channel ID required}"
        PAGE="${3:-0}"
        PER_PAGE="${4:-60}"
        "$TIME" "${AS_ARGS[@]}" GET "/api/v4/channels/${CHANNEL_ID}/members?page=${PAGE}&per_page=${PER_PAGE}"
        ;;

    cache-clear)
        # Clear channels cache
        rm -rf "$CACHE_DIR"/channels-*.json
        echo "Cache cleared" >&2
        ;;

    *)
        echo "Usage: $0 [--as bot|me] <action> [args...]" >&2
        echo "Actions: me, my-teams, my-channels, get, search, find, members, cache-clear" >&2
        exit 1
        ;;
esac
