#!/bin/bash
# Shared helper to load .env for all integration scripts.
#
# Behavior:
#   1. Unsets known secrets from inherited shell environment, so .env
#      is the only authoritative source. Without this, a stale token in
#      ~/.zshrc could silently override the per-repo .env file.
#   2. Walks UP from the caller's SCRIPT_DIR to find the nearest .env
#      file. This is overlay-aware: when scripts live inside a git-subtree
#      (e.g. som-ai-hub/integrations/sagos95-ai-hub/...), the team-overlay's
#      .env at the repo root takes precedence over any .env inside the
#      subtree itself.
#
# Usage:
#   SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
#   source "$SCRIPT_DIR/../../hub-meta/scripts/load-env.sh"
#   hub_load_env "$SCRIPT_DIR"
#
# After hub_load_env returns successfully, $HUB_ENV_FILE holds the
# absolute path of the file that was sourced.

# Known secret variable names. Add new tokens here so they are stripped
# from inherited shell environment before sourcing .env.
#
# Team-local wrappers may extend this list before calling hub_load_env, e.g.:
#   source "$SCRIPT_DIR/../../sagos95-ai-hub/.../load-env.sh"
#   HUB_KNOWN_SECRETS+=(MY_CUSTOM_TOKEN)
#   hub_load_env "$SCRIPT_DIR"
HUB_KNOWN_SECRETS=(
    KAITEN_TOKEN
    BUILDIN_UI_TOKEN
    BUILDIN_API_TOKEN
    TIME_TOKEN
    TIME_BOT_TOKEN
    GENIE_TOKEN
    KUSTO_TOKEN
    TESTOPS_TOKEN
)

hub_load_env() {
    local start="${1:-$PWD}"

    local _k
    for _k in "${HUB_KNOWN_SECRETS[@]}"; do
        unset "$_k"
    done

    local dir="$start"
    while [[ "$dir" != "/" && -n "$dir" ]]; do
        if [[ -f "$dir/.env" ]]; then
            set -a
            # shellcheck disable=SC1090,SC1091
            source "$dir/.env"
            set +a
            export HUB_ENV_FILE="$dir/.env"
            export HUB_OVERLAY_ROOT="$dir"
            return 0
        fi
        dir="$(dirname "$dir")"
    done

    return 1
}

# Resolve the team overlay root: the directory whose .env was sourced by
# hub_load_env. Scripts use this to find shared assets like team-config.json
# that live at the overlay root, not inside the subtree.
#
# If hub_load_env wasn't called or no .env was found, prints nothing and
# returns 1.
hub_overlay_root() {
    if [[ -n "${HUB_OVERLAY_ROOT:-}" ]]; then
        echo "$HUB_OVERLAY_ROOT"
        return 0
    fi
    return 1
}
