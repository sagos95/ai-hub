#!/usr/bin/env bash
# Stage 0: Build & Static Analyzers
# Runs dotnet build with warnings-as-errors on changed files' projects.
# Exit 0 = PASS, Exit 1 = FAIL (findings on stdout as JSON lines)
set -euo pipefail

REPO_PATH="${1:?Usage: stage0-build.sh <repo-path> [base-branch]}"
BASE_BRANCH="${2:-main}"

cd "$REPO_PATH"

# Find changed .cs / .razor files
CHANGED_FILES=$(git diff "$BASE_BRANCH"...HEAD --name-only --diff-filter=ACMR | grep -E '\.(cs|razor)$' || true)
if [ -z "$CHANGED_FILES" ]; then
    echo '{"stage":"build","status":"PASS","message":"No C#/Razor files changed"}'
    exit 0
fi

# Determine affected .csproj files
PROJECTS=()
while IFS= read -r file; do
    dir=$(dirname "$file")
    while [ "$dir" != "." ] && [ "$dir" != "/" ]; do
        csproj=$(find "$dir" -maxdepth 1 -name "*.csproj" 2>/dev/null | head -1)
        if [ -n "$csproj" ]; then
            PROJECTS+=("$csproj")
            break
        fi
        dir=$(dirname "$dir")
    done
done <<< "$CHANGED_FILES"

# Deduplicate
UNIQUE_PROJECTS=($(printf '%s\n' "${PROJECTS[@]}" | sort -u))

if [ ${#UNIQUE_PROJECTS[@]} -eq 0 ]; then
    echo '{"stage":"build","status":"PASS","message":"No projects found for changed files"}'
    exit 0
fi

# Build each project, collect errors and warnings
FINDINGS=""
BUILD_FAILED=0

for proj in "${UNIQUE_PROJECTS[@]}"; do
    OUTPUT=$(dotnet build "$proj" --no-restore --verbosity quiet 2>&1 || true)

    # Extract errors
    ERRORS=$(echo "$OUTPUT" | grep -E ': error ' || true)
    if [ -n "$ERRORS" ]; then
        BUILD_FAILED=1
        while IFS= read -r line; do
            FINDINGS="${FINDINGS}{\"stage\":\"build\",\"severity\":\"BLOCK\",\"type\":\"build-error\",\"message\":$(echo "$line" | jq -Rs .)}\n"
        done <<< "$ERRORS"
    fi

    # Extract analyzer warnings (CS*, CA*, IDE*, SA*)
    WARNINGS=$(echo "$OUTPUT" | grep -E ': warning (CS|CA|IDE|SA|BL)' || true)
    if [ -n "$WARNINGS" ]; then
        while IFS= read -r line; do
            FINDINGS="${FINDINGS}{\"stage\":\"build\",\"severity\":\"WARNING\",\"type\":\"analyzer-warning\",\"message\":$(echo "$line" | jq -Rs .)}\n"
        done <<< "$WARNINGS"
    fi
done

if [ $BUILD_FAILED -eq 1 ]; then
    echo -e "$FINDINGS"
    exit 1
fi

# Check for warnings in changed files specifically
RELEVANT_WARNINGS=""
while IFS= read -r file; do
    MATCH=$(echo -e "$FINDINGS" | grep "$file" || true)
    if [ -n "$MATCH" ]; then
        RELEVANT_WARNINGS="${RELEVANT_WARNINGS}${MATCH}\n"
    fi
done <<< "$CHANGED_FILES"

if [ -n "$RELEVANT_WARNINGS" ]; then
    echo -e "$RELEVANT_WARNINGS"
    exit 1
fi

echo '{"stage":"build","status":"PASS","message":"Build succeeded, no relevant warnings"}'
exit 0
