---
name: holst-write
description: "Write/edit content on a Holst.so board (stickers, frames, text)"
argument-hint: "<board_url> <instructions>"
allowed-tools: ["Read", "Glob", "mcp__chrome-devtools__list_pages", "mcp__chrome-devtools__navigate_page", "mcp__chrome-devtools__evaluate_script", "mcp__chrome-devtools__take_snapshot", "mcp__chrome-devtools__take_screenshot", "mcp__chrome-devtools__wait_for"]
---

# Holst Board Write

Edit content on a Holst.so whiteboard — create frames, stickers, and set text. Requires `chrome-devtools` MCP server.

## Prerequisites

- A Slate text editor must be active on the board (user double-clicks any sticker)
- This unlocks the live Y.Doc connection through which writes are synced to the WASM engine

## Instructions

### 1. Parse arguments

From the user argument `$ARGUMENTS`:
- Extract the **board URL** (e.g. `https://app.holst.so/board/{BOARD_ID}`)
- Extract **what to do** (create frames, set sticker text, etc.)

### 2. Open the board

Use `list_pages` to check if the board is already open. If not:
- Use `navigate_page` to open the board URL
- If redirected to `/login`, ask the user to authenticate, then retry

### 3. Inject both API helpers

Read and inject the **read API** first, then the **write API**:

```
# Step 1: Read API (for init, listFrames, etc.)
Read file: integrations/holst/scripts/holst-api.js
evaluate_script({ function: `() => { <CONTENTS> }` })

# Step 2: Initialize read API
evaluate_script({ function: "async () => await window.holst.init()" })

# Step 3: Write API
Read file: integrations/holst/scripts/holst-write-api.js
evaluate_script({ function: `() => { <CONTENTS> }` })
```

### 4. Activate the Slate editor

**Ask the user to double-click any sticker on the board.** This is required — the WASM engine only accepts text changes through the Slate collaborative binding.

Then initialize the write API:
```
evaluate_script({ function: "() => window.holstWrite.init()" })
```

Returns: `{ activeDocId, activeText, totalObjects, totalDocuments }`

### 5. Perform write operations

#### Set sticker text by document ID
```javascript
holstWrite.setText('document-uuid', 'New text')
```

#### Set sticker text by object ID
```javascript
holstWrite.setStickerText('sticker-uuid', 'New text')
```

#### Batch update multiple stickers
```javascript
holstWrite.setMultipleTexts([
  { documentId: 'doc-uuid-1', text: 'Text 1' },
  { stickerId: 'obj-uuid-2', text: 'Text 2' },
])
```

#### Create a frame
```javascript
holstWrite.createFrame({
  label: 'My Frame',
  position: { x: 0, y: 0 },
  width: 5000,
  height: 4000,
  fillColor: 'white3'
})
```

#### Create a sticker with text
```javascript
holstWrite.createSticker({
  position: { x: 100, y: 100 },
  width: 192, height: 192,
  color: 'yellow4',
  parentId: 'parent-frame-uuid',
  text: 'Hello!'
})
```

### 6. Restore editor state

After all writes, restore the editor to the original sticker:
```
evaluate_script({ function: "() => window.holstWrite.restore()" })
```

### 7. Verify

Take a screenshot to confirm changes are visible:
```
take_screenshot()
```

## Important notes

- **Text writes require an active Slate editor** — user must double-click a sticker first
- **Frame/sticker creation** works via Yjs transact (no editor needed), but text inside them requires the Slate path
- **After page reload**, the write API must be re-injected and re-initialized
- **Color codes**: `yellow4`, `purple6`, `sky6`, `red6`, `jade6`, `gray6`, `lime6`, `white3`, or numeric RGB values
- Call `holstWrite.restore()` when done to leave the editor in a clean state
