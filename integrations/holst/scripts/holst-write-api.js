/**
 * Holst.so Board Write API — injectable helper for editing board content.
 *
 * IMPORTANT: Requires holst-api.js to be injected first (for init/read),
 * AND a Slate editor to be active (user must double-click any sticker before using write methods).
 *
 * Usage (via chrome-devtools MCP evaluate_script):
 *   1. Inject holst-api.js and call holst.init()
 *   2. User double-clicks any sticker on the board (opens Slate editor)
 *   3. Inject this file
 *   4. Call holstWrite.init() — captures Slate editor and live Y.Doc
 *   5. Use write methods
 *
 * How it works:
 *   Holst's WASM engine manages a live Yjs document. External Yjs mutations are ignored.
 *   BUT when a sticker is in edit mode, Holst creates a Slate.js editor bound to the
 *   sticker's XmlText via `editor.sharedRoot`. We can disconnect/reconnect the editor
 *   to any document and use `editor.insertText()` + `editor.flushLocalChanges()` to
 *   write text through the proper collaborative binding that the WASM engine accepts.
 */
(() => {
  if (window.holstWrite) return;

  const hw = {};

  let _editor = null;
  let _yDoc = null;
  let _documents = null;
  let _objects = null;
  let _originalDocId = null;

  /**
   * Find the Slate editor from the currently active text editing session.
   * User MUST have double-clicked a sticker before calling this.
   */
  function findSlateEditor() {
    const el = document.querySelector('[data-slate-editor]');
    if (!el) return null;

    const fiberKey = Object.keys(el).find(k => k.startsWith('__reactFiber'));
    if (!fiberKey) return null;

    let f = el[fiberKey];
    let editor = null;
    let docId = null;

    for (let i = 0; i < 30 && f; i++) {
      const props = f.memoizedProps;
      if (props?.editor?.sharedRoot && !editor) {
        editor = props.editor;
      }
      if (props?.id && props?.isSingleYDocument !== undefined && !docId) {
        docId = props.id;
      }
      f = f.return;
    }

    return editor ? { editor, docId } : null;
  }

  /**
   * Initialize write API. Must be called after user opens a sticker for editing.
   * Returns info about the live Y.Doc.
   */
  hw.init = function () {
    const result = findSlateEditor();
    if (!result) {
      throw new Error('No Slate editor found. Double-click a sticker first.');
    }

    _editor = result.editor;
    _originalDocId = result.docId;
    _yDoc = _editor.sharedRoot.doc;

    if (!_yDoc) {
      throw new Error('Could not access live Y.Doc from editor.');
    }

    _documents = _yDoc.getMap('documents');
    _objects = _yDoc.getMap('objects');

    let objCount = 0;
    _objects.forEach(() => objCount++);
    let docCount = 0;
    _documents.forEach(() => docCount++);

    return {
      activeDocId: _originalDocId,
      activeText: _editor.sharedRoot.toString(),
      totalObjects: objCount,
      totalDocuments: docCount
    };
  };

  /**
   * Set text content for a specific document by ID.
   * Uses Slate editor disconnect/reconnect pattern for WASM-compatible writes.
   *
   * @param {string} documentId — UUID of the document in the documents map
   * @param {string} text — new text content
   * @param {Object} [marks] — optional Slate marks (e.g. { bold: true })
   * @returns {{ documentId, text }}
   */
  hw.setText = function (documentId, text, marks) {
    if (!_editor || !_documents) throw new Error('Call holstWrite.init() first.');

    const xmlText = _documents.get(documentId);
    if (!xmlText) throw new Error(`Document not found: ${documentId}`);

    _editor.disconnect();
    _editor.sharedRoot = xmlText;
    _editor.connect();

    _editor.selectEntireEditor();
    if (marks) {
      _editor.insertText(text);
      // Apply marks to entire text
      _editor.selectEntireEditor();
      for (const [key, value] of Object.entries(marks)) {
        _editor.addMark(key, value);
      }
    } else {
      _editor.insertText(text);
    }
    _editor.flushLocalChanges();

    return { documentId, text: _editor.sharedRoot.toString() };
  };

  /**
   * Set text for a sticker by its object ID.
   *
   * @param {string} stickerId — UUID of the sticker object
   * @param {string} text — new text content
   * @returns {{ stickerId, documentId, text }}
   */
  hw.setStickerText = function (stickerId, text) {
    if (!_objects) throw new Error('Call holstWrite.init() first.');

    const obj = _objects.get(stickerId);
    if (!obj) throw new Error(`Object not found: ${stickerId}`);
    const json = obj.toJSON ? obj.toJSON() : obj;

    if (!json.documentId) throw new Error(`Object ${stickerId} has no documentId`);

    const result = hw.setText(json.documentId, text);
    return { stickerId, ...result };
  };

  /**
   * Set text for multiple stickers at once.
   *
   * @param {Array<{stickerId?: string, documentId?: string, text: string}>} items
   * @returns {Array<{id, text, ok, error?}>}
   */
  hw.setMultipleTexts = function (items) {
    return items.map(item => {
      try {
        if (item.stickerId) {
          const r = hw.setStickerText(item.stickerId, item.text);
          return { id: item.stickerId, text: r.text, ok: true };
        } else if (item.documentId) {
          const r = hw.setText(item.documentId, item.text);
          return { id: item.documentId, text: r.text, ok: true };
        }
        return { id: null, ok: false, error: 'No stickerId or documentId provided' };
      } catch (e) {
        return { id: item.stickerId || item.documentId, ok: false, error: e.message };
      }
    });
  };

  /**
   * Restore the editor to its original document (the one user double-clicked).
   * Call this when done editing to avoid leaving the editor in a broken state.
   */
  hw.restore = function () {
    if (!_editor || !_originalDocId || !_documents) return false;

    const origXml = _documents.get(_originalDocId);
    if (!origXml) return false;

    _editor.disconnect();
    _editor.sharedRoot = origXml;
    _editor.connect();
    return true;
  };

  /**
   * Create a new frame on the board.
   * Uses IndexedDB Yjs updates (works for structural objects, not text).
   *
   * @param {Object} opts
   * @param {string} opts.label — frame title
   * @param {{x: number, y: number}} opts.position
   * @param {number} opts.width
   * @param {number} opts.height
   * @param {string} [opts.fillColor='white3']
   * @param {string} [opts.parentId=null]
   * @returns {{ id, label }}
   */
  hw.createFrame = function (opts) {
    if (!_objects || !_yDoc) throw new Error('Call holstWrite.init() first.');

    const Y = window.Y || window.Yjs;
    if (!Y) throw new Error('Yjs not loaded. Call holst.init() first.');

    const id = crypto.randomUUID();
    const now = Date.now();

    _yDoc.transact(() => {
      const ymap = new Y.Map();
      ymap.set('type', 'frame');
      ymap.set('id', id);
      ymap.set('labelText', opts.label);
      ymap.set('width', opts.width);
      ymap.set('height', opts.height);
      ymap.set('position', opts.position);
      ymap.set('fillColor', { color: opts.fillColor || 'white3' });
      ymap.set('zIndex', 12000000 + Math.random() * 1000);
      ymap.set('parentId', opts.parentId || null);
      ymap.set('created', { a: 0, t: now });
      ymap.set('updated', { a: 0, t: now });
      _objects.set(id, ymap);
    });

    return { id, label: opts.label };
  };

  /**
   * Create a sticker on the board.
   *
   * @param {Object} opts
   * @param {{x: number, y: number}} opts.position
   * @param {number} [opts.width=192]
   * @param {number} [opts.height=192]
   * @param {string} [opts.color='yellow4']
   * @param {number} [opts.opacity=1]
   * @param {string} [opts.parentId=null] — parent frame ID
   * @param {string} [opts.text] — initial text (set via Slate after creation)
   * @returns {{ id, documentId }}
   */
  hw.createSticker = function (opts) {
    if (!_objects || !_documents || !_yDoc) throw new Error('Call holstWrite.init() first.');

    const Y = window.Y || window.Yjs;
    if (!Y) throw new Error('Yjs not loaded.');

    const id = crypto.randomUUID();
    const documentId = crypto.randomUUID();
    const now = Date.now();

    _yDoc.transact(() => {
      // Create empty XmlText document
      const xmlText = new Y.XmlText();
      _documents.set(documentId, xmlText);

      // Create sticker object
      const ymap = new Y.Map();
      ymap.set('type', 'sticker');
      ymap.set('id', id);
      ymap.set('documentId', documentId);
      ymap.set('position', opts.position);
      ymap.set('width', opts.width || 192);
      ymap.set('height', opts.height || 192);
      ymap.set('fillColor', { color: opts.color || 'yellow4', opacity: opts.opacity ?? 1 });
      ymap.set('parentId', opts.parentId || null);
      ymap.set('zIndex', 12000000 + Math.random() * 1000);
      ymap.set('created', { a: 0, t: now });
      ymap.set('updated', { a: 0, t: now });
      _objects.set(id, ymap);
    });

    // Set text via Slate if provided
    if (opts.text) {
      hw.setText(documentId, opts.text);
    }

    return { id, documentId };
  };

  /**
   * Get info about the live Y.Doc (objects and documents counts, frame list).
   */
  hw.info = function () {
    if (!_objects) throw new Error('Call holstWrite.init() first.');

    const frames = [];
    _objects.forEach((val) => {
      const obj = val.toJSON ? val.toJSON() : val;
      if (obj.type === 'frame' && obj.labelText) {
        frames.push({ id: obj.id, label: obj.labelText, position: obj.position });
      }
    });
    frames.sort((a, b) => (a.position?.y ?? 0) - (b.position?.y ?? 0));

    return { frames: frames.length, topFrames: frames.slice(0, 10) };
  };

  window.holstWrite = hw;
})();
