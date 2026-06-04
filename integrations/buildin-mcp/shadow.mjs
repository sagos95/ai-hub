import fs from 'node:fs';
import path from 'node:path';

const INDEX_FILE = path.join(process.cwd(), '../shadow-index.json');

function loadIndex() {
  try {
    if (fs.existsSync(INDEX_FILE)) {
      return JSON.parse(fs.readFileSync(INDEX_FILE, 'utf-8'));
    }
  } catch (e) {
    console.error('Failed to load shadow index', e);
  }
  return { meta: { description: 'Shadow index' }, pages: {} };
}

function saveIndex(index) {
  try {
    fs.writeFileSync(INDEX_FILE, JSON.stringify(index, null, 2), 'utf-8');
  } catch (e) {
    console.error('Failed to save shadow index', e);
  }
}

export function searchShadowIndex(query) {
  const index = loadIndex();
  const q = query.toLowerCase();
  let bestScore = 0;
  let bestId = null;

  for (const [pid, page] of Object.entries(index.pages)) {
    const title = (page.title || '').toLowerCase();
    const summary = (page.summary || '').toLowerCase();
    let score = 0;
    if (q === title) score = 100;
    else if (title.includes(q)) score = 50;
    else if (summary.includes(q)) score = 20;

    if (score > bestScore) {
      bestScore = score;
      bestId = pid;
    }
  }

  return bestScore > 0 ? bestId : null;
}

export function updateShadowIndex(pageId, title, markdownText, parentId) {
  const index = loadIndex();
  const existing = index.pages[pageId] || {};
  const cleanText = markdownText.replace(/[#*`\n]/g, ' ').replace(/\s+/g, ' ').trim();
  const summary = cleanText.substring(0, 150) + (cleanText.length > 150 ? '...' : '');

  index.pages[pageId] = {
    title: title || existing.title || '(untitled)',
    parent_id: parentId || existing.parent_id,
    summary: summary || existing.summary || '',
    url: `https://buildin.ai/docs/${pageId}`,
    synced_at: new Date().toISOString().split('T')[0],
    children: existing.children,
  };

  saveIndex(index);
}
