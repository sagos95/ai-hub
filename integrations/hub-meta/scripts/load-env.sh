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

    # Walk up collecting all .env files. Source them outermost-LAST so the
    # outer .env (overlay root) wins over any inner .env (e.g. one shipped
    # inside a vendored subtree). This gives team-overlay installs the
    # expected behavior — team .env at the repo root overrides any leftover
    # values inside integrations/sagos95-ai-hub/.env, while still picking
    # up subtree-only keys (e.g. KUSTO_CLUSTER, TIME_BASE_URL) when the
    # overlay doesn't redefine them.
    local found=()
    local dir="$start"
    while [[ "$dir" != "/" && -n "$dir" ]]; do
        if [[ -f "$dir/.env" ]]; then
            found=("$dir/.env" "${found[@]}")
        fi
        dir="$(dirname "$dir")"
    done

    if [[ ${#found[@]} -eq 0 ]]; then
        return 1
    fi

    # Source innermost first, outermost last → outermost wins.
    local _f
    for _f in "${found[@]}"; do
        set -a
        # shellcheck disable=SC1090,SC1091
        source "$_f"
        set +a
    done

    # Overlay root = directory of the OUTERMOST .env (last in `found`).
    local outermost="${found[-1]}"
    export HUB_ENV_FILE="$outermost"
    export HUB_OVERLAY_ROOT="${outermost%/.env}"
    return 0
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
