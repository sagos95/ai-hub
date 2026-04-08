#!/usr/bin/env bash
# Collect diff context for AI review agents.
# Outputs a structured summary: changed files, diff, and project context.
set -euo pipefail

REPO_PATH="${1:?Usage: collect-diff-context.sh <repo-path> [base-branch]}"
BASE_BRANCH="${2:-main}"

cd "$REPO_PATH"

echo "=== CHANGED FILES ==="
git diff "$BASE_BRANCH"...HEAD --name-only --diff-filter=ACMR

echo ""
echo "=== DIFF STAT ==="
git diff "$BASE_BRANCH"...HEAD --stat

echo ""
echo "=== DIFF (C#/Razor only, max 3000 lines) ==="
git diff "$BASE_BRANCH"...HEAD --diff-filter=ACMR -- '*.cs' '*.razor' | head -3000

echo ""
echo "=== COMMIT MESSAGES ==="
git log "$BASE_BRANCH"..HEAD --oneline --no-merges

echo ""
echo "=== PROJECT STRUCTURE (src/) ==="
if [ -d "src" ]; then
    find src -maxdepth 3 -name "*.csproj" 2>/dev/null | sort
fi

echo ""
echo "=== RPA ARTIFACTS ==="
RPA_DIR="$REPO_PATH/reverse-project-analysis"
if [ -d "$RPA_DIR" ]; then
    echo "RPA directory found: $RPA_DIR"
    for idx in "$RPA_DIR"/*/00-index.md; do
        if [ -f "$idx" ]; then
            echo ""
            echo "--- $(dirname "$idx" | xargs basename) ---"
            head -50 "$idx"
        fi
    done
else
    echo "No RPA artifacts found at $RPA_DIR"
fi
