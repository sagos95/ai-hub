#!/bin/bash
# Time (Mattermost) Message operations — Layer 2
# Usage: ./time-messages.sh [--as bot|me] <action> [args...]
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TIME="$SCRIPT_DIR/time.sh"
SIGNATURE_FILE="$SCRIPT_DIR/../.time-signature"

# Load message signature (appended to every outgoing message)
TIME_SIGNATURE=""
if [[ -f "$SIGNATURE_FILE" ]]; then
    TIME_SIGNATURE=$(cat "$SIGNATURE_FILE")
fi

# Pass through --as flag
AS_ARGS=()
if [[ "$1" == "--as" ]]; then
    AS_ARGS=("--as" "$2")
    shift 2
fi

action="${1}"

case "$action" in
    posts)
        # Get posts in channel (newest first)
        # Usage: ./time-messages.sh posts <channel_id> [page] [per_page]
        CHANNEL_ID="${2:?Channel ID required}"
        PAGE="${3:-0}"
        PER_PAGE="${4:-30}"
        "$TIME" "${AS_ARGS[@]}" GET "/api/v4/channels/${CHANNEL_ID}/posts?page=${PAGE}&per_page=${PER_PAGE}"
        ;;

    get)
        # Get single post by ID
        # Usage: ./time-messages.sh get <post_id>
        POST_ID="${2:?Post ID required}"
        "$TIME" "${AS_ARGS[@]}" GET "/api/v4/posts/${POST_ID}"
        ;;

    thread)
        # Get thread by root post ID
        # Usage: ./time-messages.sh thread <post_id>
        POST_ID="${2:?Post ID required}"
        "$TIME" "${AS_ARGS[@]}" GET "/api/v4/posts/${POST_ID}/thread"
        ;;

    send)
        # Send message to channel
        # Usage: ./time-messages.sh send <channel_id> <message> [root_id]
        CHANNEL_ID="${2:?Channel ID required}"
        MESSAGE="${3:?Message required}"
        ROOT_ID="${4}"
        MESSAGE="${MESSAGE}${TIME_SIGNATURE}"

        ESCAPED_MESSAGE=$(echo "$MESSAGE" | python3 -c 'import sys,json; print(json.dumps(sys.stdin.read().strip())[1:-1])')

        if [[ -n "$ROOT_ID" ]]; then
            BODY="{\"channel_id\":\"$CHANNEL_ID\",\"message\":\"$ESCAPED_MESSAGE\",\"root_id\":\"$ROOT_ID\"}"
        else
            BODY="{\"channel_id\":\"$CHANNEL_ID\",\"message\":\"$ESCAPED_MESSAGE\"}"
        fi

        "$TIME" "${AS_ARGS[@]}" POST "/api/v4/posts" "$BODY"
        ;;

    search)
        # Search messages in team
        # Usage: ./time-messages.sh search <team_id> <terms> [is_or_search]
        TEAM_ID="${2:?Team ID required}"
        TERMS="${3:?Search terms required}"
        IS_OR="${4:-false}"

        ESCAPED_TERMS=$(echo "$TERMS" | python3 -c 'import sys,json; print(json.dumps(sys.stdin.read().strip())[1:-1])')

        "$TIME" "${AS_ARGS[@]}" POST "/api/v4/teams/${TEAM_ID}/posts/search" "{\"terms\":\"$ESCAPED_TERMS\",\"is_or_search\":$IS_OR}"
        ;;

    user)
        # Get user info by ID (for resolving usernames)
        # Usage: ./time-messages.sh user <user_id>
        USER_ID="${2:?User ID required}"
        "$TIME" "${AS_ARGS[@]}" GET "/api/v4/users/${USER_ID}"
        ;;

    my-posts)
        # List posts authored by current user in a channel (auto-paginates)
        # Usage: ./time-messages.sh my-posts <channel_id> [max_posts]
        CHANNEL_ID="${2:?Channel ID required}"
        MAX_POSTS="${3:-800}"
        PER_PAGE=200

        MY_ID=$("$TIME" "${AS_ARGS[@]}" GET "/api/v4/users/me" | jq -r '.id')
        if [[ -z "$MY_ID" || "$MY_ID" == "null" ]]; then
            echo "Failed to resolve current user id" >&2
            exit 1
        fi

        page=0
        scanned=0
        results="[]"
        while (( scanned < MAX_POSTS )); do
            batch=$("$TIME" "${AS_ARGS[@]}" GET "/api/v4/channels/${CHANNEL_ID}/posts?page=${page}&per_page=${PER_PAGE}")
            count=$(echo "$batch" | jq '.order | length')
            if [[ "$count" == "0" ]]; then break; fi

            mine=$(echo "$batch" | jq --arg me "$MY_ID" '[.order[] as $id | .posts[$id] | select(.user_id == $me) | {id, create_at, root_id, message}]')
            results=$(jq -s '.[0] + .[1]' <(echo "$results") <(echo "$mine"))

            scanned=$(( scanned + count ))
            page=$(( page + 1 ))
            if (( count < PER_PAGE )); then break; fi
        done

        echo "$results" | jq 'sort_by(.create_at)'
        ;;

    *)
        echo "Usage: $0 [--as bot|me] <action> [args...]" >&2
        echo "Actions: posts, get, thread, send, search, user, my-posts" >&2
        exit 1
        ;;
esac
