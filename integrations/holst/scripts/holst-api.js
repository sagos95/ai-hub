/**
 * Holst.so Board API — injectable helper for extracting board data.
 *
 * Usage (via chrome-devtools MCP evaluate_script):
 *   1. Inject:  evaluate_script({ function: await fetch('/path/to/holst-api.js').then(r => r.text()) })
 *   2. Init:    evaluate_script({ function: "async () => await window.holst.init()" })
 *   3. Use:     evaluate_script({ function: "async () => await window.holst.listFrames()" })
 *
 * Or inject inline — the whole file is a self-executing setup.
 */
(() => {
  if (window.holst) return;

  const holst = {};

  // ── Internal state ──
  let _doc = null;
  let _objects = null;
  let _documents = null;
  let _allObjects = null;
  let _backupService = null;

  // ── Find backup service in React DI tree ──
  function findBackupService() {
    const root = document.getElementById('root');
    if (!root) throw new Error('No #root element — is this a Holst board page?');

    const containerKey = Object.keys(root).find(k => k.startsWith('__reactContainer'));
    if (!containerKey) throw new Error('No React container found');

    let fiber = root[containerKey];
    let found = null;

    function walk(f, d) {
      if (!f || d > 70 || found) return;
      let state = f.memoizedState;
      let si = 0;
      while (state && si < 20) {
        try {
          const ms = state.memoizedState;
          if (ms && ms.current && ms.current._providers) {
            let container = ms.current;
            while (container) {
              for (const o of (container.objs || [])) {
                if (o && typeof o.getBackupList$ === 'function' && typeof o.fetchBackup === 'function') {
                  found = o;
                  return;
                }
              }
              container = container._parent;
            }
          }
        } catch (e) { /* skip */ }
        state = state.next;
        si++;
      }
      if (f.child) walk(f.child, d + 1);
      if (f.sibling) walk(f.sibling, d + 1);
    }

    walk(fiber, 0);
    if (!found) throw new Error('Backup service not found — board may not be fully loaded');
    return found;
  }

  // ── Get board ID from URL ──
  function getBoardId() {
    const match = location.pathname.match(/\/board\/([a-f0-9-]+)/);
    if (!match) throw new Error('Not on a board page');
    return match[1];
  }

  // ── Resolve text from documents map ──
  function resolveText(documentId) {
    if (!documentId || !_documents) return null;
    const val = _documents.get(documentId);
    if (!val) return null;
    return val.toJSON ? val.toJSON() : String(val);
  }

  // ── Public API ──

  /**
   * Initialize: load Yjs, fetch latest backup, parse the document.
   * Must be called once after navigating to a board.
   */
  holst.init = async function () {
    const boardId = getBoardId();
    _backupService = findBackupService();

    // Get backup list
    const backups = await new Promise((resolve, reject) => {
      _backupService.getBackupList$(boardId, true).subscribe({ next: resolve, error: reject });
    });

    if (!backups.length) throw new Error('No backups found for this board');

    // Fetch latest backup
    const latest = backups[0];
    const blob = await _backupService.fetchBackup(latest.id, latest.encodeVersion);
    const uint8 = new Uint8Array(await blob.arrayBuffer());

    // Load Yjs
    const Y = window.Y || await import('https://esm.sh/yjs@13.6.18');
    window.Y = Y;

    // Parse
    _doc = new Y.Doc();
    Y.applyUpdateV2(_doc, uint8);

    _objects = _doc.getMap('objects');
    _documents = _doc.getMap('documents');

    // Cache all objects
    _allObjects = [];
    _objects.forEach((val) => {
      _allObjects.push(val.toJSON ? val.toJSON() : val);
    });

    return {
      boardId,
      backupDate: latest.date,
      totalObjects: _allObjects.length,
      totalDocuments: Array.from(_documents.keys()).length
    };
  };

  /**
   * List all frames on the board.
   * Returns: [{ id, label, childCount }]
   */
  holst.listFrames = function () {
    if (!_allObjects) throw new Error('Call holst.init() first');
    return _allObjects
      .filter(o => o.type === 'frame' && o.labelText)
      .map(f => ({
        id: f.id,
        label: f.labelText,
        childCount: _allObjects.filter(o => o.parentId === f.id).length
      }))
      .sort((a, b) => a.label.localeCompare(b.label));
  };

  /**
   * Find a frame by name (partial match).
   * Returns frame object or null.
   */
  holst.findFrame = function (nameQuery) {
    if (!_allObjects) throw new Error('Call holst.init() first');
    const q = nameQuery.toLowerCase();
    return _allObjects.find(o => o.type === 'frame' && o.labelText && o.labelText.toLowerCase().includes(q)) || null;
  };

  /**
   * Get all stickers of a frame (by name or id).
   * Returns: [{ id, text, color, position }]
   */
  holst.getStickers = function (frameNameOrId) {
    if (!_allObjects) throw new Error('Call holst.init() first');
    const frame = frameNameOrId.includes('-')
      ? _allObjects.find(o => o.id === frameNameOrId)
      : holst.findFrame(frameNameOrId);

    if (!frame) throw new Error(`Frame not found: ${frameNameOrId}`);

    return _allObjects
      .filter(o => o.type === 'sticker' && o.parentId === frame.id)
      .map(s => ({
        id: s.id,
        text: resolveText(s.documentId) || '',
        color: s.fillColor?.color || null,
        position: s.position
      }))
      .sort((a, b) => (a.position?.x ?? 0) - (b.position?.x ?? 0) || (a.position?.y ?? 0) - (b.position?.y ?? 0));
  };

  /**
   * Full export of a frame: stickers, texts, arrows.
   * Returns: { frame, stickers, texts, arrows }
   */
  holst.exportFrame = function (frameNameOrId) {
    if (!_allObjects) throw new Error('Call holst.init() first');
    const frame = frameNameOrId.includes('-')
      ? _allObjects.find(o => o.id === frameNameOrId)
      : holst.findFrame(frameNameOrId);

    if (!frame) throw new Error(`Frame not found: ${frameNameOrId}`);

    const children = _allObjects.filter(o => o.parentId === frame.id);
    const result = {
      frame: frame.labelText,
      frameId: frame.id,
      stickers: [],
      texts: [],
      arrows: [],
      other: []
    };

    for (const child of children) {
      const text = resolveText(child.documentId);

      switch (child.type) {
        case 'sticker':
          result.stickers.push({ id: child.id, text: text || '', color: child.fillColor?.color || null });
          break;
        case 'simple-text':
          result.texts.push({ id: child.id, text: text || '' });
          break;
        case 'arrow':
          result.arrows.push({ from: child.start?.objectId, to: child.end?.objectId });
          break;
        default:
          result.other.push({ id: child.id, type: child.type, text });
          break;
      }
    }

    return result;
  };

  /**
   * Export ALL frames with their content (lightweight: just sticker texts).
   */
  holst.exportAll = function () {
    if (!_allObjects) throw new Error('Call holst.init() first');
    const frames = holst.listFrames();
    return frames.map(f => ({
      label: f.label,
      stickers: holst.getStickers(f.id).map(s => s.text).filter(Boolean)
    }));
  };

  /**
   * Search for stickers containing text across the entire board.
   */
  holst.search = function (query) {
    if (!_allObjects) throw new Error('Call holst.init() first');
    const q = query.toLowerCase();
    return _allObjects
      .filter(o => o.type === 'sticker' && o.documentId)
      .map(s => {
        const text = resolveText(s.documentId) || '';
        if (!text.toLowerCase().includes(q)) return null;
        const parentFrame = s.parentId ? _allObjects.find(o => o.id === s.parentId) : null;
        return { text, frame: parentFrame?.labelText || null, color: s.fillColor?.color || null };
      })
      .filter(Boolean);
  };

  /**
   * Get raw object by ID.
   */
  holst.getObject = function (id) {
    if (!_allObjects) throw new Error('Call holst.init() first');
    const obj = _allObjects.find(o => o.id === id);
    if (!obj) return null;
    return { ...obj, text: resolveText(obj.documentId) };
  };

  window.holst = holst;
})();
