#!/bin/bash
# Buildin Pages — операции со страницами и блоками через UI API
# Usage: ./buildin-pages.sh <command> [args...]
#
# Принимает page_id как UUID или URL:
#   ./buildin-pages.sh read 2a904afe-42e9-4ebd-a94e-f6fe0cbacf58
#   ./buildin-pages.sh read https://buildin.ai/241db73f.../2a904afe...
#
# Commands:
#   get <page_id>                          — получить страницу (JSON, все блоки)
#   title <page_id>                        — получить заголовок страницы
#   read <page_id>                         — прочитать страницу как markdown
#   create <parent_page_id> <title>        — создать дочернюю страницу
#   update <page_id> <title>               — обновить заголовок страницы
#   archive <page_id>                      — архивировать страницу (status: -1)
#   get-blocks <page_id>                   — получить блоки страницы (JSON)
#   append-blocks <page_id> <json_blocks>  — добавить блоки на страницу (transaction)
#   append-text <page_id> <text>           — добавить текстовый параграф
#   delete-block <block_id> <parent_id>    — удалить блок

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../../.." && pwd)"

buildin() {
    "$SCRIPT_DIR/buildin.sh" "$@"
}

# Извлечь UUID из URL или вернуть как есть
parse_id() {
    local input="$1"
    local uuid_re='[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}'
    local uuid
    uuid=$(echo "$input" | grep -oE "$uuid_re" | tail -1 || true)
    echo "${uuid:-$input}"
}

# Получить spaceId для страницы
get_space_id() {
    local PAGE_ID="$1"
    buildin GET "/api/blocks/$PAGE_ID" | python3 -c "
import sys, json
data = json.load(sys.stdin)
print(data.get('data', {}).get('spaceId', ''))
" 2>/dev/null
}

# Сгенерировать UUID v4
gen_uuid() {
    python3 -c "import uuid; print(str(uuid.uuid4()))"
}

# Выполнить транзакцию
transaction() {
    local SPACE_ID="$1"
    local OPERATIONS="$2"
    local REQ_ID
    REQ_ID=$(gen_uuid)
    local TX_ID
    TX_ID=$(gen_uuid)

    local body
    body=$(python3 -c "
import json, sys
ops = json.loads(sys.argv[1])
print(json.dumps({
    'requestId': sys.argv[2],
    'transactions': [{
        'id': sys.argv[3],
        'spaceId': sys.argv[4],
        'operations': ops
    }]
}))
" "$OPERATIONS" "$REQ_ID" "$TX_ID" "$SPACE_ID")

    buildin POST "/api/records/transactions" "$body"
}

COMMAND="${1:-help}"
shift 2>/dev/null || true

case "$COMMAND" in
    get)
        PAGE_ID=$(parse_id "$1")
        [[ -z "$PAGE_ID" ]] && { echo "Usage: get <page_id|url>" >&2; exit 1; }
        buildin GET "/api/docs/$PAGE_ID"
        ;;

    title)
        PAGE_ID=$(parse_id "$1")
        [[ -z "$PAGE_ID" ]] && { echo "Usage: title <page_id|url>" >&2; exit 1; }
        buildin GET "/api/docs/$PAGE_ID" | python3 -c "
import json, sys
page_id = sys.argv[1]
data = json.load(sys.stdin).get('data', {})
blocks = data.get('blocks', {})
block = blocks.get(page_id, next(iter(blocks.values()), {})) if blocks else data
print(block.get('title', '(untitled)'))
" "$PAGE_ID"
        ;;

    create)
        PARENT_ID=$(parse_id "$1")
        TITLE="$2"
        [[ -z "$PARENT_ID" || -z "$TITLE" ]] && { echo "Usage: create <parent_page_id|url> <title>" >&2; exit 1; }

        SPACE_ID=$(get_space_id "$PARENT_ID")
        [[ -z "$SPACE_ID" ]] && { echo "Error: cannot determine spaceId for parent $PARENT_ID" >&2; exit 1; }

        PAGE_UUID=$(gen_uuid)
        BLOCK_UUID=$(gen_uuid)
        NOW=$(python3 -c "import time; print(int(time.time()*1000))")
        USER_ID=$(buildin GET "/api/users/me" | python3 -c "import sys,json; print(json.load(sys.stdin).get('data',{}).get('uuid',''))")

        OPS=$(python3 -c "
import json, sys
page_id = sys.argv[1]
parent_id = sys.argv[2]
space_id = sys.argv[3]
block_id = sys.argv[4]
title = sys.argv[5]
now = int(sys.argv[6])
user_id = sys.argv[7]

ops = [
    # Create the page block
    {
        'id': page_id,
        'command': 'set',
        'table': 'block',
        'path': [],
        'args': {
            'uuid': page_id,
            'spaceId': space_id,
            'parentId': parent_id,
            'type': 0,
            'textColor': '',
            'backgroundColor': '',
            'status': 1,
            'permissions': [],
            'createdAt': now,
            'createdBy': user_id,
            'updatedBy': user_id,
            'updatedAt': now,
            'data': {
                'segments': [{'type': 0, 'text': title, 'enhancer': {}}],
                'pageFixedWidth': True,
                'format': {'commentAlignment': 'top'}
            }
        }
    },
    # Add page to parent's subNodes
    {
        'id': parent_id,
        'command': 'listAfter',
        'table': 'block',
        'path': ['subNodes'],
        'args': {'uuid': page_id}
    },
    # Create empty paragraph inside the page
    {
        'id': block_id,
        'command': 'set',
        'table': 'block',
        'path': [],
        'args': {
            'uuid': block_id,
            'spaceId': space_id,
            'parentId': page_id,
            'type': 1,
            'textColor': '',
            'backgroundColor': '',
            'status': 1,
            'permissions': [],
            'createdAt': now,
            'createdBy': user_id,
            'updatedBy': user_id,
            'updatedAt': now,
            'data': {
                'pageFixedWidth': True,
                'format': {'commentAlignment': 'top'}
            }
        }
    },
    # Add paragraph to page's subNodes
    {
        'id': page_id,
        'command': 'listAfter',
        'table': 'block',
        'path': ['subNodes'],
        'args': {'uuid': block_id}
    },
    # Update parent timestamps
    {
        'id': parent_id,
        'command': 'update',
        'table': 'block',
        'path': [],
        'args': {'updatedBy': user_id, 'updatedAt': now}
    }
]
print(json.dumps(ops))
" "$PAGE_UUID" "$PARENT_ID" "$SPACE_ID" "$BLOCK_UUID" "$TITLE" "$NOW" "$USER_ID")

        transaction "$SPACE_ID" "$OPS"
        echo ""
        echo "Created page: $PAGE_UUID"
        echo "URL: https://buildin.ai/$SPACE_ID/$PAGE_UUID"
        ;;

    update)
        PAGE_ID=$(parse_id "$1")
        TITLE="$2"
        [[ -z "$PAGE_ID" || -z "$TITLE" ]] && { echo "Usage: update <page_id|url> <title>" >&2; exit 1; }

        SPACE_ID=$(get_space_id "$PAGE_ID")
        NOW=$(python3 -c "import time; print(int(time.time()*1000))")
        USER_ID=$(buildin GET "/api/users/me" | python3 -c "import sys,json; print(json.load(sys.stdin).get('data',{}).get('uuid',''))")

        OPS=$(python3 -c "
import json, sys
page_id, title, now, user_id = sys.argv[1], sys.argv[2], int(sys.argv[3]), sys.argv[4]
ops = [
    {
        'id': page_id,
        'command': 'update',
        'table': 'block',
        'path': ['data'],
        'args': {'segments': [{'type': 0, 'text': title, 'enhancer': {}}]}
    },
    {
        'id': page_id,
        'command': 'update',
        'table': 'block',
        'path': [],
        'args': {'updatedBy': user_id, 'updatedAt': now}
    }
]
print(json.dumps(ops))
" "$PAGE_ID" "$TITLE" "$NOW" "$USER_ID")

        transaction "$SPACE_ID" "$OPS"
        ;;

    archive)
        PAGE_ID=$(parse_id "$1")
        [[ -z "$PAGE_ID" ]] && { echo "Usage: archive <page_id|url>" >&2; exit 1; }

        # Get parent and space info
        BLOCK_INFO=$(buildin GET "/api/blocks/$PAGE_ID")
        SPACE_ID=$(echo "$BLOCK_INFO" | python3 -c "import sys,json; print(json.load(sys.stdin).get('data',{}).get('spaceId',''))")
        PARENT_ID=$(echo "$BLOCK_INFO" | python3 -c "import sys,json; print(json.load(sys.stdin).get('data',{}).get('parentId',''))")
        NOW=$(python3 -c "import time; print(int(time.time()*1000))")
        USER_ID=$(buildin GET "/api/users/me" | python3 -c "import sys,json; print(json.load(sys.stdin).get('data',{}).get('uuid',''))")

        OPS=$(python3 -c "
import json, sys
page_id, parent_id, now, user_id = sys.argv[1], sys.argv[2], int(sys.argv[3]), sys.argv[4]
ops = [
    {'id': page_id, 'command': 'update', 'table': 'block', 'path': [],
     'args': {'status': -1, 'updatedBy': user_id, 'updatedAt': now}},
    {'id': parent_id, 'command': 'listRemove', 'table': 'block', 'path': ['subNodes'],
     'args': {'uuid': page_id}},
    {'id': page_id, 'command': 'update', 'table': 'block', 'path': [],
     'args': {'updatedBy': user_id, 'updatedAt': now}}
]
print(json.dumps(ops))
" "$PAGE_ID" "$PARENT_ID" "$NOW" "$USER_ID")

        transaction "$SPACE_ID" "$OPS"
        ;;

    get-blocks)
        PAGE_ID=$(parse_id "$1")
        [[ -z "$PAGE_ID" ]] && { echo "Usage: get-blocks <page_id|url>" >&2; exit 1; }
        buildin GET "/api/docs/$PAGE_ID" | python3 -c "
import json, sys
page_id = sys.argv[1]
data = json.load(sys.stdin).get('data', {})
blocks = data.get('blocks', {})
page = blocks.get(page_id, {})
sub_nodes = page.get('subNodes', [])
result = []
for sid in sub_nodes:
    if sid in blocks:
        result.append(blocks[sid])
print(json.dumps(result, indent=2, ensure_ascii=False))
" "$PAGE_ID"
        ;;

    read)
        PAGE_ID=$(parse_id "$1")
        [[ -z "$PAGE_ID" ]] && { echo "Usage: read <page_id|url>" >&2; exit 1; }

        buildin GET "/api/docs/$PAGE_ID" | python3 -c "
import json, sys

page_id = sys.argv[1]
data = json.load(sys.stdin).get('data', {})
blocks = data.get('blocks', {})
page = blocks.get(page_id, {})
title = page.get('title', '(untitled)')
print(f'# {title}')
print()

# Block types: 0=page, 1=text(empty), 4=bulleted, 5=text, 6=heading, 7=sub-heading,
#              13=callout, 14=image, 21=bookmark, 25=code, 26=divider, 28=table-row
def rt(segments):
    parts = []
    for s in (segments or []):
        text = s.get('text', '')
        enh = s.get('enhancer', {})
        url = s.get('url', '')
        if enh.get('code'): text = f'\`{text}\`'
        elif enh.get('bold'): text = f'**{text}**'
        elif enh.get('italic'): text = f'*{text}*'
        if url:
            text = f'[{text}]({url})'
        parts.append(text)
    return ''.join(parts)

def render(node_ids, indent=0):
    pfx = '  ' * indent
    for nid in node_ids:
        b = blocks.get(nid)
        if not b: continue
        t = b.get('type', 1)
        d = b.get('data', {})
        segs = d.get('segments', [])
        text = rt(segs)
        sub = b.get('subNodes', [])
        level = d.get('level', 1)

        if t == 0:
            # Sub-page
            print(f'{pfx}> [{b.get(\"title\", text)}](https://buildin.ai/{b.get(\"spaceId\", \"\")}/{nid})')
            print()
        elif t == 1:
            # Empty paragraph / text without segments
            if text:
                print(f'{pfx}{text}')
                print()
            else:
                print()
        elif t == 5:
            print(f'{pfx}{text}')
            print()
        elif t == 4:
            print(f'{pfx}- {text}')
        elif t == 6:
            h = '#' * min(level, 3)
            print(f'{pfx}{h} {text}')
            print()
        elif t == 7:
            h = '#' * min(level + 1, 4)
            print(f'{pfx}{h} {text}')
            print()
        elif t == 13:
            icon = d.get('icon', {}).get('value', '')
            print(f'{pfx}> {icon} {text}')
            print()
        elif t == 14:
            oss = d.get('ossName', '')
            ext = d.get('extName', '')
            print(f'{pfx}![{text}]({oss})')
            print()
        elif t == 21:
            link = d.get('link', '')
            print(f'{pfx}[{text or link}]({link})')
            print()
        elif t == 25:
            lang = d.get('language', '')
            print(f'{pfx}\`\`\`{lang}')
            print(f'{pfx}{text}')
            print(f'{pfx}\`\`\`')
            print()
        elif t == 26:
            print(f'{pfx}---')
            print()
        elif text:
            print(f'{pfx}{text}')
            print()

        if sub and t != 0:
            render(sub, indent + 1)

render(page.get('subNodes', []))
" "$PAGE_ID"
        ;;

    append-blocks)
        PAGE_ID=$(parse_id "$1")
        BLOCKS_JSON="$2"
        [[ -z "$PAGE_ID" || -z "$BLOCKS_JSON" ]] && { echo "Usage: append-blocks <page_id|url> <json_blocks>" >&2; exit 1; }

        SPACE_ID=$(get_space_id "$PAGE_ID")
        NOW=$(python3 -c "import time; print(int(time.time()*1000))")
        USER_ID=$(buildin GET "/api/users/me" | python3 -c "import sys,json; print(json.load(sys.stdin).get('data',{}).get('uuid',''))")

        OPS=$(python3 -c "
import json, sys, uuid

page_id = sys.argv[1]
space_id = sys.argv[2]
now = int(sys.argv[3])
user_id = sys.argv[4]
blocks_json = sys.argv[5]

blocks = json.loads(blocks_json)
ops = []

for block in blocks:
    block_id = str(uuid.uuid4())
    block_type = block.get('type', 5)
    block_data = block.get('data', {})

    ops.append({
        'id': block_id,
        'command': 'set',
        'table': 'block',
        'path': [],
        'args': {
            'uuid': block_id,
            'spaceId': space_id,
            'parentId': page_id,
            'type': block_type,
            'textColor': '',
            'backgroundColor': '',
            'status': 1,
            'permissions': [],
            'createdAt': now,
            'createdBy': user_id,
            'updatedBy': user_id,
            'updatedAt': now,
            'data': {**{'pageFixedWidth': True, 'format': {'commentAlignment': 'top'}}, **block_data}
        }
    })
    ops.append({
        'id': page_id,
        'command': 'listAfter',
        'table': 'block',
        'path': ['subNodes'],
        'args': {'uuid': block_id}
    })

# Update page timestamp
ops.append({
    'id': page_id,
    'command': 'update',
    'table': 'block',
    'path': [],
    'args': {'updatedBy': user_id, 'updatedAt': now}
})

print(json.dumps(ops))
" "$PAGE_ID" "$SPACE_ID" "$NOW" "$USER_ID" "$BLOCKS_JSON")

        transaction "$SPACE_ID" "$OPS"
        ;;

    append-text)
        PAGE_ID=$(parse_id "$1")
        TEXT="$2"
        [[ -z "$PAGE_ID" || -z "$TEXT" ]] && { echo "Usage: append-text <page_id|url> <text>" >&2; exit 1; }

        BLOCKS=$(python3 -c "
import json, sys
text = sys.argv[1]
blocks = [{'type': 5, 'data': {'segments': [{'type': 0, 'text': text, 'enhancer': {}}]}}]
print(json.dumps(blocks))
" "$TEXT")

        bash "$SCRIPT_DIR/buildin-pages.sh" append-blocks "$PAGE_ID" "$BLOCKS"
        ;;

    delete-block)
        BLOCK_ID=$(parse_id "$1")
        PARENT_ID=$(parse_id "${2:-}")
        [[ -z "$BLOCK_ID" ]] && { echo "Usage: delete-block <block_id> [parent_id]" >&2; exit 1; }

        # Auto-detect parent if not provided
        if [[ -z "$PARENT_ID" ]]; then
            BLOCK_INFO=$(buildin GET "/api/blocks/$BLOCK_ID")
            PARENT_ID=$(echo "$BLOCK_INFO" | python3 -c "import sys,json; print(json.load(sys.stdin).get('data',{}).get('parentId',''))")
        fi
        [[ -z "$PARENT_ID" ]] && { echo "Error: cannot determine parentId for $BLOCK_ID" >&2; exit 1; }

        SPACE_ID=$(get_space_id "$BLOCK_ID")
        NOW=$(python3 -c "import time; print(int(time.time()*1000))")
        USER_ID=$(buildin GET "/api/users/me" | python3 -c "import sys,json; print(json.load(sys.stdin).get('data',{}).get('uuid',''))")

        OPS=$(python3 -c "
import json, sys
block_id, parent_id, now, user_id = sys.argv[1], sys.argv[2], int(sys.argv[3]), sys.argv[4]
ops = [
    {'id': block_id, 'command': 'update', 'table': 'block', 'path': [],
     'args': {'status': -1, 'updatedBy': user_id, 'updatedAt': now}},
    {'id': parent_id, 'command': 'listRemove', 'table': 'block', 'path': ['subNodes'],
     'args': {'uuid': block_id}}
]
print(json.dumps(ops))
" "$BLOCK_ID" "$PARENT_ID" "$NOW" "$USER_ID")

        transaction "$SPACE_ID" "$OPS"
        ;;

    help|*)
        echo "Buildin Pages — операции со страницами и блоками (UI API)"
        echo "Принимает page_id как UUID или URL buildin.ai"
        echo ""
        echo "Commands:"
        echo "  get <id|url>                             — получить страницу (JSON, все блоки)"
        echo "  title <id|url>                           — заголовок страницы"
        echo "  read <id|url>                            — прочитать как markdown"
        echo "  create <parent_id|url> <title>           — создать дочернюю страницу"
        echo "  update <id|url> <title>                  — обновить заголовок"
        echo "  archive <id|url>                         — архивировать (status: -1)"
        echo "  get-blocks <id|url>                      — блоки страницы (JSON)"
        echo "  append-blocks <id|url> <json_blocks>     — добавить блоки"
        echo "  append-text <id|url> <text>              — добавить текстовый параграф"
        echo "  delete-block <block_id> [parent_id]      — удалить блок"
        ;;
esac
