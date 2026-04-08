#!/bin/bash
# Databricks Genie API Configuration

# Load environment variables from .env (in repo root)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

if [ -f "$REPO_ROOT/.env" ]; then
    source "$REPO_ROOT/.env"
fi

# Databricks Genie Conversation API (official API with SQL visibility)
GENIE_HOST="${GENIE_HOST:-https://your-region.azuredatabricks.net}"
GENIE_SPACE_ID="${GENIE_SPACE_ID:-your-genie-space-id}"

# Token from environment
GENIE_TOKEN="${GENIE_TOKEN:-}"

# Validate token
if [ -z "$GENIE_TOKEN" ]; then
    echo "Error: GENIE_TOKEN is not set. Add it to .env" >&2
    exit 1
fi
