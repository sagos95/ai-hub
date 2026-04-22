#!/usr/bin/env bash
# Install sagos95/ai-hub as a git subtree inside your overlay repository.
#
# Run this from the ROOT of your own git repo (e.g. your team overlay).
# After installation, the generic AI Hub lives under <prefix>/ and can be
# updated later with scripts/update-from-ai-hub.sh (or `make update-ai-hub`).
#
# Usage (one-liner, no local clone needed):
#   curl -sL https://raw.githubusercontent.com/sagos95/ai-hub/main/scripts/install-as-subtree.sh | bash
#   curl -sL https://raw.githubusercontent.com/sagos95/ai-hub/main/scripts/install-as-subtree.sh | bash -s integrations/sagos95-ai-hub
#
# Or, with a local clone of this repo:
#   ./scripts/install-as-subtree.sh [prefix]
#
# Default prefix: integrations/sagos95-ai-hub
set -euo pipefail

PREFIX="${1:-integrations/sagos95-ai-hub}"
REMOTE_NAME="${AI_HUB_REMOTE:-ai-hub}"
REMOTE_URL="${AI_HUB_URL:-https://github.com/sagos95/ai-hub.git}"
BRANCH="${AI_HUB_BRANCH:-main}"

die() { echo "ERROR: $*" >&2; exit 1; }

[[ -d .git ]] || die "Not a git repo root. cd to your overlay repo first."

if [[ -e "$PREFIX" ]]; then
  die "Path '$PREFIX' already exists. Choose another prefix or remove it first."
fi

if ! git diff-index --quiet HEAD -- 2>/dev/null; then
  die "Working tree has uncommitted changes. Commit or stash before subtree add."
fi

if git remote get-url "$REMOTE_NAME" &>/dev/null; then
  existing="$(git remote get-url "$REMOTE_NAME")"
  if [[ "$existing" != "$REMOTE_URL" ]]; then
    die "Remote '$REMOTE_NAME' already points to $existing (expected $REMOTE_URL)."
  fi
  echo ">>> Remote '$REMOTE_NAME' already configured."
else
  echo ">>> Adding remote '$REMOTE_NAME' → $REMOTE_URL"
  git remote add "$REMOTE_NAME" "$REMOTE_URL"
fi

echo ">>> Fetching $REMOTE_NAME/$BRANCH ..."
git fetch "$REMOTE_NAME" "$BRANCH"

echo ">>> git subtree add --prefix=$PREFIX $REMOTE_NAME $BRANCH --squash"
git subtree add --prefix="$PREFIX" "$REMOTE_NAME" "$BRANCH" --squash

cat <<EOF

================================================================
Installed sagos95/ai-hub as subtree at: $PREFIX

Next steps:
  1. Register plugin in .claude/settings.json:
       { "plugins": ["./$PREFIX", "."] }
  2. (Optional) Add a Makefile target to update later:
       update-ai-hub:
       	git subtree pull --prefix=$PREFIX $REMOTE_NAME $BRANCH --squash
  3. To update from upstream anytime:
       git subtree pull --prefix=$PREFIX $REMOTE_NAME $BRANCH --squash
================================================================
EOF
