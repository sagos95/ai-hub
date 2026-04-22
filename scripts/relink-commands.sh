#!/usr/bin/env bash
# Create missing symlinks for slash-commands from a subtree prefix.
#
# Safe to run repeatedly — existing correct symlinks are left alone,
# conflicting files/symlinks are reported but NOT overwritten.
#
# Usage:
#   ./relink-commands.sh [prefix] [namespace]
#
# Defaults:
#   prefix    = integrations/sagos95-ai-hub
#   namespace = ai-hub
set -euo pipefail

PREFIX="${1:-integrations/sagos95-ai-hub}"
NAMESPACE="${2:-ai-hub}"

[[ -d "$PREFIX" ]] || { echo "ERROR: Prefix '$PREFIX' not found." >&2; exit 1; }

target_dir=".claude/commands/$NAMESPACE"
up="../../../"

mkdir -p "$target_dir"

created=0 skipped=0 conflicted=0
shopt -s nullglob
for cmd_file in "$PREFIX"/integrations/*/commands/*.md; do
  base=$(basename "$cmd_file")
  link="$target_dir/$base"

  if [[ -L "$link" ]]; then
    current_target=$(readlink "$link")
    if [[ "$current_target" == "${up}${cmd_file}" ]]; then
      ((skipped++))
    else
      echo "   ! $base → $current_target (kept; points elsewhere)"
      ((conflicted++))
    fi
    continue
  fi

  if [[ -e "$link" ]]; then
    echo "   ! $base is a regular file (kept)"
    ((conflicted++))
    continue
  fi

  (cd "$target_dir" && ln -s "${up}${cmd_file}" "$base")
  echo "   + $base"
  ((created++))
done
shopt -u nullglob

echo "Symlinks in $target_dir/: $created created, $skipped already correct, $conflicted left in place"
