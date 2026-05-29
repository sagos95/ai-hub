---
description: "Read a Buildin.ai page via Official Bot API (by URL, page_id, or search query)"
argument-hint: "<page URL, UUID, or search query>"
---

# Buildin Bot API — Read Page

Read a Buildin.ai page using the Official Bot API (`api.buildin.ai/v1/`).

**Important:** The bot can only access pages that have been explicitly shared with the bot integration. If you get a 403 error, ask the user to share the page with the bot in Buildin settings.

## Auth check

```bash
$INTEGRATION_DIR/../buildin-bot-api/scripts/buildin-bot.sh GET /v1/users/me
```

If token is missing, ask the user to:
1. Go to Buildin → Settings → Integrations → Create bot integration
2. Copy the generated token
3. Run: `bash integrations/sagos95-ai-hub/integrations/hub-meta/scripts/env-manager.sh set BUILDIN_BOT_TOKEN <token>`

## Input handling

The user provides `$ARGUMENTS` — it can be:
- **URL** like `https://buildin.ai/.../page-uuid` → extract UUID
- **UUID** like `2a904afe-42e9-4ebd-a94e-f6fe0cbacf58` → use directly
- **Search query** like `"RFC template"` → search first, then read the best match

## Execution

### If URL or UUID detected:

```bash
$INTEGRATION_DIR/../buildin-bot-api/scripts/buildin-bot-pages.sh read "$PAGE_ID"
```

### If search query:

```bash
$INTEGRATION_DIR/../buildin-bot-api/scripts/buildin-bot-pages.sh search "$ARGUMENTS" 5
```

Show the user the results and ask which page to read. Then:

```bash
$INTEGRATION_DIR/../buildin-bot-api/scripts/buildin-bot-pages.sh read "$SELECTED_PAGE_ID"
```

## Output

Return the markdown content to the user. If the page has child pages, mention them so the user can navigate deeper.
