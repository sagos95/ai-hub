#!/bin/bash
# Time (Mattermost) shared helpers
# Sourced by time-messages.sh (and bats tests). Defines functions only — no side effects.
#
# Required caller variables (set before sourcing for resolve_users/enrich_*):
#   TIME      — path to time.sh
#   AS_ARGS   — array with optional ["--as", "bot|me"]
#   SCRIPT_DIR — scripts/ directory (used to locate .cache/)

# ---------------------------------------------------------------------------
# Permalink → post_id

# Extract Mattermost post_id from a permalink URL like:
#   https://<host>/<team>/pl/<post_id>[?query][#fragment]
# Falls through unchanged if input is not a /pl/ URL (e.g. raw post_id).
extract_post_id() {
    local input="$1"
    if [[ "$input" =~ /pl/([a-z0-9]+) ]]; then
        echo "${BASH_REMATCH[1]}"
    else
        echo "$input"
    fi
}

# ---------------------------------------------------------------------------
# User resolution: batch fetch + file cache

USERS_CACHE_TTL=604800  # 7 days

_users_cache_path() {
    echo "${SCRIPT_DIR}/../.cache/users.json"
}

# Returns JSON object of fresh cached users: {user_id: {id, username, ...}}
_users_cache_fresh() {
    local now="$1"
    local cache_file
    cache_file=$(_users_cache_path)
    [[ -f "$cache_file" ]] || { echo '{}'; return; }
    jq --argjson now "$now" --argjson ttl "$USERS_CACHE_TTL" \
        '[to_entries[] | select(.value.fetched_at != null and ($now - .value.fetched_at) < $ttl) | {(.key): .value.user}] | add // {}' \
        "$cache_file" 2>/dev/null || echo '{}'
}

# Resolve list of user_ids → JSON object {id: {id, username, nickname, first_name, last_name}}
# On HTTP error, returns whatever is in the fresh cache and warns to stderr.
resolve_users() {
    local ids_json="$1"  # JSON array, e.g. ["abc","def"]
    local cache_file
    cache_file=$(_users_cache_path)
    mkdir -p "$(dirname "$cache_file")"
    [[ -f "$cache_file" ]] || echo '{}' > "$cache_file"

    local now
    now=$(date +%s)

    local cached
    cached=$(_users_cache_fresh "$now")

    local missing
    missing=$(echo "$ids_json" | jq --argjson cached "$cached" '[.[] | select($cached[.] == null)] | unique')

    local missing_count
    missing_count=$(echo "$missing" | jq 'length')

    local fetched='[]'
    if (( missing_count > 0 )); then
        if ! fetched=$("$TIME" "${AS_ARGS[@]}" POST "/api/v4/users/ids" "$missing" 2>/dev/null); then
            echo "time: failed to resolve users via /users/ids — returning unresolved" >&2
            fetched='[]'
        fi
        # Defensive: API may return error object; ensure array
        if ! echo "$fetched" | jq -e 'type == "array"' >/dev/null 2>&1; then
            echo "time: /users/ids returned non-array — skipping cache update" >&2
            fetched='[]'
        fi
    fi

    # Merge fetched into cache, write atomically
    local tmp="${cache_file}.tmp"
    if jq --argjson now "$now" --argjson fetched "$fetched" \
        'reduce $fetched[] as $u (.; .[$u.id] = {fetched_at: $now, user: ($u | {id, username, nickname, first_name, last_name})})' \
        "$cache_file" > "$tmp" 2>/dev/null; then
        mv "$tmp" "$cache_file"
    else
        rm -f "$tmp"
    fi

    # Return merged map for caller (cached + just fetched)
    jq -n --argjson cached "$cached" --argjson fetched "$fetched" \
        '$cached + ([$fetched[] | {(.id): {id, username, nickname, first_name, last_name}}] | add // {})'
}

# Enrich Mattermost {order, posts: {id: post}} dict — adds `.posts[*].user` next to .user_id.
enrich_posts_dict() {
    local posts_json="$1"
    local ids
    ids=$(echo "$posts_json" | jq '[.posts // {} | to_entries[] | .value.user_id] | unique')
    local count
    count=$(echo "$ids" | jq 'length')
    if (( count == 0 )); then
        echo "$posts_json"
        return 0
    fi
    local users
    users=$(resolve_users "$ids")
    echo "$posts_json" | jq --argjson users "$users" \
        '.posts |= with_entries(.value.user = ($users[.value.user_id] // null))'
}

# Enrich a flat array of posts: [{user_id, ...}, ...] — adds `.user` to each item.
enrich_post_array() {
    local arr_json="$1"
    local ids
    ids=$(echo "$arr_json" | jq '[.[] | .user_id // empty] | unique')
    local count
    count=$(echo "$ids" | jq 'length')
    if (( count == 0 )); then
        echo "$arr_json"
        return 0
    fi
    local users
    users=$(resolve_users "$ids")
    echo "$arr_json" | jq --argjson users "$users" \
        'map(. + {user: ($users[.user_id] // null)})'
}

# Enrich a single post object: {id, user_id, ...} — adds .user.
enrich_single_post() {
    local post_json="$1"
    local uid
    uid=$(echo "$post_json" | jq -r '.user_id // empty')
    if [[ -z "$uid" ]]; then
        echo "$post_json"
        return 0
    fi
    local users
    users=$(resolve_users "[\"$uid\"]")
    echo "$post_json" | jq --argjson users "$users" \
        '. + {user: ($users[.user_id] // null)}'
}
