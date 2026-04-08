---
name: holst-export
description: "Export data from a Holst.so board (frames, stickers, texts)"
argument-hint: "<board_url> [frame_name]"
allowed-tools: ["Read", "Glob", "mcp__chrome-devtools__list_pages", "mcp__chrome-devtools__navigate_page", "mcp__chrome-devtools__evaluate_script", "mcp__chrome-devtools__take_snapshot", "mcp__chrome-devtools__wait_for"]
---

# Holst Board Export

Export data from a Holst.so whiteboard. Requires `chrome-devtools` MCP server to be connected.

## Instructions

You have access to the `chrome-devtools` MCP tools. Follow these steps:

### 1. Parse arguments

From the user argument `$ARGUMENTS`:
- Extract the **board URL** (e.g. `https://app.holst.so/board/{BOARD_ID}`)
- Extract the optional **frame name** to filter by

### 2. Check if already on the board

Use `list_pages` to see if the board is already open. If not:
- Use `navigate_page` to open the board URL
- If redirected to `/login`, ask the user to authenticate in the MCP browser, then retry

### 3. Inject the Holst API helper

Read the file `integrations/holst/scripts/holst-api.js` from the repo root, then inject it:

```
evaluate_script({ function: `() => { <CONTENTS_OF_holst-api.js> }` })
```

Note: You cannot use `fetch()` for local files — read the file with the Read tool, then pass the contents as a string to `evaluate_script`.

### 4. Initialize

```
evaluate_script({ function: "async () => await window.holst.init()" })
```

This returns: `{ boardId, backupDate, totalObjects, totalDocuments }`

### 5. Extract data

**If a frame name was specified:**
```
evaluate_script({ function: "() => window.holst.exportFrame('FRAME_NAME')" })
```

**If no frame name — list all frames:**
```
evaluate_script({ function: "() => window.holst.listFrames()" })
```

**Other available methods:**
- `holst.getStickers('frame name')` — stickers only
- `holst.search('query')` — find stickers by text across the board
- `holst.exportAll()` — all frames with their sticker texts
- `holst.getObject('object-uuid')` — raw object by ID

### 6. Present results

Format the extracted data clearly for the user. For stickers, group by color if meaningful:
- `lime6` (green) — typically completed items or checklist steps
- `gray3` — values/metrics
- `yellow4` — warnings or partial
- `red6` — blockers or important notes
- no color — notes/details
