import fs from 'fs';
import path from 'path';

const INDEX_FILE = path.join(process.cwd(), '../shadow-index.json');

export interface ShadowPage {
  title: string;
  summary: string;
  parent_id?: string;
  url: string;
  synced_at: string;
  children?: string[];
}

export interface ShadowIndex {
  meta: any;
  pages: Record<string, ShadowPage>;
}

export function loadIndex(): ShadowIndex {
  try {
    if (fs.existsSync(INDEX_FILE)) {
      const data = fs.readFileSync(INDEX_FILE, 'utf-8');
      return JSON.parse(data);
    }
  } catch (e) {
    console.error('Failed to load shadow index', e);
  }
  return { meta: { description: "Shadow index" }, pages: {} };
}

export function saveIndex(index: ShadowIndex) {
  try {
    fs.writeFileSync(INDEX_FILE, JSON.stringify(index, null, 2), 'utf-8');
  } catch (e) {
    console.error('Failed to save shadow index', e);
  }
}

export function searchShadowIndex(query: string): string | null {
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

export function updateShadowIndex(pageId: string, title: string, markdownText: string, parentId?: string) {
  const index = loadIndex();
  const existing = index.pages[pageId] || {};
  
  // Create a simple summary from the first 150 chars of markdown text
  const cleanText = markdownText.replace(/[\#\*\`\n]/g, ' ').replace(/\s+/g, ' ').trim();
  const summary = cleanText.substring(0, 150) + (cleanText.length > 150 ? '...' : '');

  index.pages[pageId] = {
    title: title || existing.title || '(untitled)',
    parent_id: parentId || existing.parent_id,
    summary: summary || existing.summary || '',
    url: `https://buildin.ai/docs/${pageId}`,
    synced_at: new Date().toISOString().split('T')[0],
    children: existing.children
  };

  saveIndex(index);
}
