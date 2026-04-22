#!/usr/bin/env bash
# Pull the latest sagos95/ai-hub into an existing subtree prefix.
#
# Run from the root of your overlay repo. If scripts/install-as-subtree.sh
# was used, pass the same prefix (or rely on the default).
#
# Usage:
#   ./scripts/update-from-ai-hub.sh [prefix]
#
# Default prefix: integrations/sagos95-ai-hub
set -euo pipefail

PREFIX="${1:-integrations/sagos95-ai-hub}"
REMOTE_NAME="${AI_HUB_REMOTE:-ai-hub}"
BRANCH="${AI_HUB_BRANCH:-main}"

die() { echo "ERROR: $*" >&2; exit 1; }

[[ -d .git ]] || die "Not a git repo root. cd to your overlay repo first."
[[ -d "$PREFIX" ]] || die "Prefix '$PREFIX' not found. Run install-as-subtree.sh first."
git remote get-url "$REMOTE_NAME" &>/dev/null || die "Remote '$REMOTE_NAME' not configured."

if ! git diff-index --quiet HEAD -- 2>/dev/null; then
  die "Working tree has uncommitted changes. Commit or stash before subtree pull."
fi

echo ">>> git subtree pull --prefix=$PREFIX $REMOTE_NAME $BRANCH --squash"
git subtree pull --prefix="$PREFIX" "$REMOTE_NAME" "$BRANCH" --squash
echo ">>> Done. Review the merge commit with: git log -1 --stat"
