#!/usr/bin/env bash
# Stage 1: Security Pattern Scanner
# Grep-based detection of common security anti-patterns in changed C#/Razor files.
# Exit 0 = PASS, Exit 1 = FAIL (findings on stdout as JSON lines)
set -euo pipefail

REPO_PATH="${1:?Usage: stage1-security.sh <repo-path> [base-branch]}"
BASE_BRANCH="${2:-main}"

cd "$REPO_PATH"

# Get changed file contents via git diff
CHANGED_FILES=$(git diff "$BASE_BRANCH"...HEAD --name-only --diff-filter=ACMR | grep -E '\.(cs|razor)$' || true)
if [ -z "$CHANGED_FILES" ]; then
    echo '{"stage":"security","status":"PASS","message":"No C#/Razor files changed"}'
    exit 0
fi

FINDINGS=""
FOUND=0

check_pattern() {
    local pattern="$1"
    local severity="$2"
    local rule_id="$3"
    local description="$4"

    while IFS= read -r file; do
        MATCHES=$(git diff "$BASE_BRANCH"...HEAD -- "$file" | grep -n "^+" | grep -E "$pattern" || true)
        if [ -n "$MATCHES" ]; then
            FOUND=1
            while IFS= read -r match; do
                FINDINGS="${FINDINGS}{\"stage\":\"security\",\"severity\":\"${severity}\",\"rule\":\"${rule_id}\",\"file\":\"${file}\",\"description\":\"${description}\",\"match\":$(echo "$match" | jq -Rs .)}\n"
            done <<< "$MATCHES"
        fi
    done <<< "$CHANGED_FILES"
}

# --- BLOCK-level patterns (must fix before merge) ---

# SQL injection via string concatenation
check_pattern '(SqlCommand|ExecuteNonQuery|ExecuteReader|ExecuteScalar|FromSqlRaw)\s*\(' "BLOCK" "SEC001" \
    "Potential SQL injection — use parameterized queries"

# Raw SQL string concatenation
check_pattern '"\s*SELECT\s.*"\s*\+|"\s*INSERT\s.*"\s*\+|"\s*UPDATE\s.*"\s*\+|"\s*DELETE\s.*"\s*\+' "BLOCK" "SEC002" \
    "SQL string concatenation — use parameterized queries or ORM"

# Hardcoded secrets
check_pattern '(password|secret|apikey|api_key|token|connectionstring)\s*=\s*"[^"]{8,}"' "BLOCK" "SEC003" \
    "Possible hardcoded secret — use configuration/secrets manager"

# Disable SSL validation
check_pattern 'ServerCertificateValidationCallback\s*=|ServicePointManager\.ServerCertificateCustomValidationCallback' "BLOCK" "SEC004" \
    "SSL certificate validation override — verify this is intentional"

# Command injection
check_pattern 'Process\.Start\s*\(|ProcessStartInfo' "WARNING" "SEC005" \
    "Process execution — verify inputs are sanitized"

# --- WARNING-level patterns ---

# XSS in Blazor (MarkupString from user input)
check_pattern 'new\s+MarkupString\s*\(|MarkupString\(' "WARNING" "SEC006" \
    "MarkupString renders raw HTML — ensure input is sanitized"

# Deserialization of untrusted data
check_pattern 'BinaryFormatter|JsonSerializer\.Deserialize.*HttpContext|JsonConvert\.DeserializeObject.*Request' "WARNING" "SEC007" \
    "Deserialization from untrusted source — validate input type"

# Open redirect
check_parameter 'Redirect\s*\(.*Request|RedirectToAction.*url.*Request' "WARNING" "SEC008" \
    "Potential open redirect — validate redirect URL" 2>/dev/null || true

# Missing authorization
check_pattern '\[AllowAnonymous\]' "WARNING" "SEC009" \
    "AllowAnonymous endpoint — verify this should be public"

# CORS wildcard
check_pattern 'AllowAnyOrigin|WithOrigins\s*\(\s*"\*"' "WARNING" "SEC010" \
    "Permissive CORS policy — verify origin restrictions"

if [ $FOUND -eq 1 ]; then
    echo -e "$FINDINGS"
    exit 1
fi

echo '{"stage":"security","status":"PASS","message":"No security anti-patterns detected"}'
exit 0
