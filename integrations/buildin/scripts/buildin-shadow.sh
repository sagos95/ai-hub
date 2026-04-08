#!/bin/bash
# Buildin Shadow Index — локальный кеш структуры и саммари страниц
# Usage: ./buildin-shadow.sh <command> [args...]
#
# Commands:
#   search <query>                       — поиск по title и summary в локальном индексе
#   get <page_id>                        — получить запись из индекса
#   update <page_id> <title> <summary> [parent_id] — добавить/обновить запись
#   add-children <page_id> <child_ids>   — записать список children (JSON array)
#   tree [page_id]                       — дерево из индекса (мгновенно, без API)
#   dump                                 — вывести весь индекс для LLM-анализа
#   stats                                — статистика индекса
#   stale [days]                         — показать записи старше N дней (default: 30)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INDEX_FILE="$SCRIPT_DIR/../shadow-index.json"

# Проверить наличие индекса
ensure_index() {
    if [[ ! -f "$INDEX_FILE" ]]; then
        echo '{"meta":{"description":"Shadow index","root_page_id":"2a904afe-42e9-4ebd-a94e-f6fe0cbacf58"},"pages":{}}' > "$INDEX_FILE"
    fi
}

COMMAND="${1:-help}"
shift 2>/dev/null || true

case "$COMMAND" in
    search)
        QUERY="$1"
        [[ -z "$QUERY" ]] && { echo "Usage: search <query>" >&2; exit 1; }
        ensure_index
        python3 -c "
import json, sys

query = sys.argv[1].lower()
with open(sys.argv[2]) as f:
    index = json.load(f)

results = []
for pid, page in index.get('pages', {}).items():
    title = page.get('title', '').lower()
    summary = page.get('summary', '').lower()
    score = 0
    if query == title:
        score = 100
    elif query in title:
        score = 50
    elif query in summary:
        score = 20
    if score > 0:
        results.append((score, pid, page))

results.sort(key=lambda x: -x[0])
if not results:
    print('Не найдено в shadow-индексе.')
    sys.exit(1)

for score, pid, page in results[:10]:
    stale = page.get('synced_at', '?')
    print(f'★ {page[\"title\"]}  [{pid}]')
    print(f'  {page.get(\"summary\", \"\")}')
    print(f'  URL: {page.get(\"url\", \"\")}  (synced: {stale})')
    print()
" "$QUERY" "$INDEX_FILE"
        ;;

    get)
        PAGE_ID="$1"
        [[ -z "$PAGE_ID" ]] && { echo "Usage: get <page_id>" >&2; exit 1; }
        ensure_index
        python3 -c "
import json, sys
with open(sys.argv[2]) as f:
    index = json.load(f)
page = index.get('pages', {}).get(sys.argv[1])
if page:
    print(json.dumps(page, ensure_ascii=False, indent=2))
else:
    print('Не найдено в индексе.')
" "$PAGE_ID" "$INDEX_FILE"
        ;;

    update)
        PAGE_ID="$1"
        TITLE="$2"
        SUMMARY="$3"
        PARENT_ID="${4:-}"
        [[ -z "$PAGE_ID" || -z "$TITLE" || -z "$SUMMARY" ]] && {
            echo "Usage: update <page_id> <title> <summary> [parent_id]" >&2; exit 1
        }
        ensure_index
        python3 -c "
import json, sys
from datetime import date

page_id = sys.argv[1]
title = sys.argv[2]
summary = sys.argv[3]
parent_id = sys.argv[4]
index_file = sys.argv[5]

with open(index_file) as f:
    index = json.load(f)

pages = index.setdefault('pages', {})
existing = pages.get(page_id, {})
pages[page_id] = {
    'title': title,
    'parent_id': parent_id or existing.get('parent_id'),
    'summary': summary,
    'url': f'https://buildin.ai/docs/{page_id}',
    'synced_at': str(date.today()),
    **({'children': existing['children']} if 'children' in existing else {})
}

with open(index_file, 'w') as f:
    json.dump(index, f, ensure_ascii=False, indent=2)

print(f'✓ Updated: {title} [{page_id}]')
" "$PAGE_ID" "$TITLE" "$SUMMARY" "$PARENT_ID" "$INDEX_FILE"
        ;;

    add-children)
        PAGE_ID="$1"
        CHILDREN_JSON="$2"
        [[ -z "$PAGE_ID" || -z "$CHILDREN_JSON" ]] && {
            echo "Usage: add-children <page_id> <json_array_of_child_ids>" >&2; exit 1
        }
        ensure_index
        python3 -c "
import json, sys
from datetime import date

page_id = sys.argv[1]
children_json = sys.argv[2]
index_file = sys.argv[3]

with open(index_file) as f:
    index = json.load(f)

children = json.loads(children_json)
pages = index.setdefault('pages', {})
if page_id in pages:
    pages[page_id]['children'] = children
    pages[page_id]['synced_at'] = str(date.today())

with open(index_file, 'w') as f:
    json.dump(index, f, ensure_ascii=False, indent=2)

print(f'✓ Added {len(children)} children to {page_id}')
" "$PAGE_ID" "$CHILDREN_JSON" "$INDEX_FILE"
        ;;

    tree)
        ROOT="${1:-2a904afe-42e9-4ebd-a94e-f6fe0cbacf58}"
        ensure_index
        python3 -c "
import json, sys

root = sys.argv[1]
with open(sys.argv[2]) as f:
    index = json.load(f)

pages = index.get('pages', {})

def print_tree(pid, depth=0, max_depth=10):
    page = pages.get(pid)
    if not page:
        return
    prefix = '  ' * depth
    title = page.get('title', '?')
    synced = page.get('synced_at', '?')
    summary = page.get('summary', '')
    if len(summary) > 80:
        summary = summary[:77] + '...'
    info = f' — {summary}' if summary and depth > 0 else ''
    print(f'{prefix}📄 {title}  [{pid[:8]}…]  ({synced}){info}')
    if depth < max_depth:
        for cid in page.get('children', []):
            print_tree(cid, depth + 1, max_depth)

print_tree(root)
" "$ROOT" "$INDEX_FILE"
        ;;

    dump)
        ensure_index
        python3 -c "
import json, sys

with open(sys.argv[1]) as f:
    index = json.load(f)

pages = index.get('pages', {})
print(f'# Buildin Shadow Index ({len(pages)} pages)')
print()

# Group by parent
by_parent = {}
roots = []
for pid, page in pages.items():
    parent = page.get('parent_id')
    if not parent:
        roots.append(pid)
    else:
        by_parent.setdefault(parent, []).append(pid)

def dump_tree(pid, depth=0):
    page = pages.get(pid)
    if not page:
        return
    prefix = '  ' * depth
    title = page.get('title', '?')
    summary = page.get('summary', '')
    synced = page.get('synced_at', '?')
    print(f'{prefix}- **{title}** ({synced})')
    if summary:
        print(f'{prefix}  {summary}')
    print(f'{prefix}  ID: {pid} | URL: {page.get(\"url\", \"\")}')
    for cid in by_parent.get(pid, []):
        if cid not in (page.get('children') or []):
            pass
        dump_tree(cid, depth + 1)
    for cid in page.get('children', []):
        if cid in pages and cid not in by_parent.get(pid, []):
            dump_tree(cid, depth + 1)

for rid in roots:
    dump_tree(rid)
" "$INDEX_FILE"
        ;;

    stats)
        ensure_index
        python3 -c "
import json, sys
from datetime import date, timedelta

with open(sys.argv[1]) as f:
    index = json.load(f)

pages = index.get('pages', {})
today = date.today()
total = len(pages)
with_summary = sum(1 for p in pages.values() if len(p.get('summary', '')) > 30)
with_children = sum(1 for p in pages.values() if p.get('children'))
stale_30 = sum(1 for p in pages.values()
    if p.get('synced_at') and (today - date.fromisoformat(p['synced_at'])).days > 30)

print(f'Total pages:     {total}')
print(f'With summaries:  {with_summary}')
print(f'With children:   {with_children}')
print(f'Stale (>30d):    {stale_30}')
" "$INDEX_FILE"
        ;;

    stale)
        DAYS="${1:-30}"
        ensure_index
        python3 -c "
import json, sys
from datetime import date

days = int(sys.argv[1])
with open(sys.argv[2]) as f:
    index = json.load(f)

today = date.today()
for pid, page in index.get('pages', {}).items():
    synced = page.get('synced_at', '')
    if not synced:
        print(f'⚠ {page.get(\"title\", \"?\")} [{pid[:8]}…] — never synced')
        continue
    age = (today - date.fromisoformat(synced)).days
    if age > days:
        print(f'⚠ {page.get(\"title\", \"?\")} [{pid[:8]}…] — {age}d old (synced: {synced})')
" "$DAYS" "$INDEX_FILE"
        ;;

    help|*)
        echo "Buildin Shadow Index — локальный кеш структуры и саммари страниц"
        echo ""
        echo "Commands:"
        echo "  search <query>                                  — поиск по title+summary"
        echo "  get <page_id>                                   — запись из индекса"
        echo "  update <page_id> <title> <summary> [parent_id]  — добавить/обновить"
        echo "  add-children <page_id> <json_child_ids>         — записать children"
        echo "  tree [page_id]                                  — дерево из индекса"
        echo "  dump                                            — полный дамп для LLM"
        echo "  stats                                           — статистика индекса"
        echo "  stale [days]                                    — устаревшие записи"
        ;;
esac
