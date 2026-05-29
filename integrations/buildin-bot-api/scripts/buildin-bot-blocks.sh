#!/bin/bash
# Buildin Bot API — Block operations (Official Bot API, api.buildin.ai/v1/)
#
# Usage: ./buildin-bot-blocks.sh <command> [args...]
#
# Commands:
#   get <block_id>                         — get block (JSON)
#   children <block_id> [page_size]        — list child blocks (paginated)
#   append <block_id> <json_children>      — append child blocks
#   append-text <block_id> <text>          — append a paragraph block
#   update <block_id> <json_data>          — update block content
#   delete <block_id>                      — delete (archive) block
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

bot() {
    "$SCRIPT_DIR/buildin-bot.sh" "$@"
}

parse_id() {
    local input="$1"
    local uuid_re='[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}'
    local uuid
    uuid=$(echo "$input" | grep -oE "$uuid_re" | tail -1 || true)
    echo "${uuid:-$input}"
}

COMMAND="${1:-help}"
shift 2>/dev/null || true

case "$COMMAND" in
    get)
        BLOCK_ID=$(parse_id "$1")
        [[ -z "$BLOCK_ID" ]] && { echo "Usage: get <block_id>" >&2; exit 1; }
        bot GET "/v1/blocks/$BLOCK_ID"
        ;;

    children)
        BLOCK_ID=$(parse_id "$1")
        PAGE_SIZE="${2:-100}"
        [[ -z "$BLOCK_ID" ]] && { echo "Usage: children <block_id> [page_size]" >&2; exit 1; }
        bot GET "/v1/blocks/${BLOCK_ID}/children?page_size=${PAGE_SIZE}"
        ;;

    append)
        BLOCK_ID=$(parse_id "$1")
        CHILDREN_JSON="$2"
        [[ -z "$BLOCK_ID" || -z "$CHILDREN_JSON" ]] && { echo "Usage: append <block_id> <json_children>" >&2; exit 1; }

        BODY=$(python3 -c "
import json, sys
children = json.loads(sys.argv[1])
print(json.dumps({'children': children}))
" "$CHILDREN_JSON")

        bot PATCH "/v1/blocks/${BLOCK_ID}/children" "$BODY"
        ;;

    append-text)
        BLOCK_ID=$(parse_id "$1")
        TEXT="$2"
        [[ -z "$BLOCK_ID" || -z "$TEXT" ]] && { echo "Usage: append-text <block_id> <text>" >&2; exit 1; }

        BODY=$(python3 -c "
import json, sys
text = sys.argv[1]
print(json.dumps({
    'children': [{
        'type': 'paragraph',
        'data': {
            'rich_text': [{'type': 'text', 'text': {'content': text}}]
        }
    }]
}))
" "$TEXT")

        bot PATCH "/v1/blocks/${BLOCK_ID}/children" "$BODY"
        ;;

    update)
        BLOCK_ID=$(parse_id "$1")
        DATA_JSON="$2"
        [[ -z "$BLOCK_ID" || -z "$DATA_JSON" ]] && { echo "Usage: update <block_id> <json_data>" >&2; exit 1; }
        bot PATCH "/v1/blocks/$BLOCK_ID" "$DATA_JSON"
        ;;

    delete)
        BLOCK_ID=$(parse_id "$1")
        [[ -z "$BLOCK_ID" ]] && { echo "Usage: delete <block_id>" >&2; exit 1; }
        bot DELETE "/v1/blocks/$BLOCK_ID"
        ;;

    help|*)
        echo "Buildin Bot API — Block operations (Official API, api.buildin.ai/v1/)"
        echo ""
        echo "Commands:"
        echo "  get <block_id>                    — get block (JSON)"
        echo "  children <block_id> [page_size]   — list child blocks"
        echo "  append <block_id> <json_children> — append child blocks"
        echo "  append-text <block_id> <text>     — append paragraph"
        echo "  update <block_id> <json_data>     — update block"
        echo "  delete <block_id>                 — delete block"
        echo ""
        echo "Block JSON format for append:"
        echo '  [{"type": "paragraph", "data": {"rich_text": [{"type": "text", "text": {"content": "Hello"}}]}}]'
        echo ""
        echo "Supported types: paragraph, heading_1, heading_2, heading_3,"
        echo "  bulleted_list_item, numbered_list_item, to_do, quote, toggle,"
        echo "  code, callout, divider, bookmark, image, embed"
        ;;
esac
