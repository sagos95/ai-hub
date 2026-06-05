#!/usr/bin/env node
import { createInterface } from 'node:readline';
import { readFileSync, existsSync } from 'node:fs';
import { join } from 'node:path';
import { homedir } from 'node:os';
import { randomUUID } from 'node:crypto';

// ---------------------------------------------------------------------------
// Load .env files (replaces dotenv)
// ---------------------------------------------------------------------------
function loadEnvFile(filepath) {
  if (!existsSync(filepath)) return;
  for (const line of readFileSync(filepath, 'utf-8').split('\n')) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith('#')) continue;
    const eq = trimmed.indexOf('=');
    if (eq < 0) continue;
    const key = trimmed.slice(0, eq).trim();
    let val = trimmed.slice(eq + 1).trim();
    if ((val.startsWith('"') && val.endsWith('"')) || (val.startsWith("'") && val.endsWith("'"))) {
      val = val.slice(1, -1);
    }
    if (!process.env[key]) process.env[key] = val;
  }
}

loadEnvFile(join(process.cwd(), '.env'));
loadEnvFile(join(homedir(), '.copilot/installed-plugins/.env'));

// ---------------------------------------------------------------------------
// Config
// ---------------------------------------------------------------------------
const BUILDIN_UI_TOKEN = process.env.BUILDIN_UI_TOKEN;
const BUILDIN_BASE_URL = 'https://buildin.ai';
const DEFAULT_SPACE_ID = process.env.BUILDIN_SPACE_ID;

if (!BUILDIN_UI_TOKEN) {
  console.error('Error: BUILDIN_UI_TOKEN environment variable not set. Please authenticate first.');
  process.exit(1);
}

// ---------------------------------------------------------------------------
// API helpers
// ---------------------------------------------------------------------------
async function buildinFetch(method, endpoint, body = null) {
  const headers = {
    Authorization: `Bearer ${BUILDIN_UI_TOKEN}`,
    'Content-Type': 'application/json',
    'x-platform': 'web-cookie',
    'x-app-origin': 'web',
    'x-product': 'buildin',
    app_version_name: '1.146.0',
  };

  const options = { method, headers };
  if (body) options.body = JSON.stringify(body);

  const res = await fetch(`${BUILDIN_BASE_URL}${endpoint}`, options);

  if (res.status === 401) {
    throw new Error('Buildin API Error: Token expired or invalid. Please re-authenticate.');
  }
  if (!res.ok) {
    const errorText = await res.text();
    throw new Error(`Buildin API Error: ${res.status} ${res.statusText} - ${errorText}`);
  }
  return res.json();
}

async function buildinTransaction(spaceId, operations) {
  return buildinFetch('POST', '/api/records/transactions', {
    requestId: randomUUID(),
    transactions: [{ id: randomUUID(), spaceId, operations }],
  });
}

async function getSpaceId(pageId) {
  const res = await buildinFetch('GET', `/api/blocks/${pageId}`);
  return res?.data?.spaceId || '';
}

async function getUserId() {
  const res = await buildinFetch('GET', '/api/users/me');
  return res?.data?.uuid || '';
}

function parseId(input) {
  const match = input.match(/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/i);
  return match ? match[0] : input;
}

// ---------------------------------------------------------------------------
// Markdown rendering
// ---------------------------------------------------------------------------
function renderSegments(segments) {
  if (!segments) return '';
  return segments.map(s => {
    let text = s.text || '';
    const enh = s.enhancer || {};
    if (enh.code) text = `\`${text}\``;
    else if (enh.bold) text = `**${text}**`;
    else if (enh.italic) text = `*${text}*`;
    if (s.url) text = `[${text}](${s.url})`;
    return text;
  }).join('');
}

function renderBlocksToMarkdown(nodeIds, blocks, indent = 0) {
  const pfx = '  '.repeat(indent);
  const lines = [];

  for (const nid of nodeIds) {
    const b = blocks[nid];
    if (!b) continue;
    const t = b.type ?? 1;
    const d = b.data || {};
    const text = renderSegments(d.segments);
    const sub = b.subNodes || [];
    const level = d.level ?? 1;

    switch (t) {
      case 0:  lines.push(`${pfx}> [${b.title || text}](https://buildin.ai/${b.spaceId || ''}/${nid})\n`); break;
      case 1:  lines.push(text ? `${pfx}${text}\n` : ''); break;
      case 3:  lines.push(`${pfx}${d.checked ? '☑' : '☐'} ${text}`); break;
      case 4:  lines.push(`${pfx}- ${text}`); break;
      case 5:  lines.push(`${pfx}1. ${text}`); break;
      case 6:  lines.push(`${pfx}▶ ${text}\n`); break;
      case 7:  lines.push(`${pfx}${'#'.repeat(Math.min(level + 1, 4))} ${text}\n`); break;
      case 9:  lines.push(`${pfx}---\n`); break;
      case 12: lines.push(`${pfx}> ${text}\n`); break;
      case 13: lines.push(`${pfx}> ${d.icon?.value || ''} ${text}\n`); break;
      case 14: lines.push(`${pfx}![${text}](${d.ossName || ''})\n`); break;
      case 21: lines.push(`${pfx}[${text || d.link || ''}](${d.link || ''})\n`); break;
      case 23: lines.push(`${pfx}$$ ${text} $$\n`); break;
      case 25: lines.push(`${pfx}\`\`\`${d.language || ''}`, `${pfx}${text}`, `${pfx}\`\`\`\n`); break;
      default: if (text) lines.push(`${pfx}${text}\n`); break;
    }

    if (sub.length > 0 && t !== 0) {
      lines.push(...renderBlocksToMarkdown(sub, blocks, indent + 1));
    }
  }
  return lines;
}

// ---------------------------------------------------------------------------
// Tool definitions
// ---------------------------------------------------------------------------
const TOOLS = [
  {
    name: 'buildin_get_page_json',
    description: 'Get full JSON representation of a Buildin page or block by ID or URL',
    inputSchema: { type: 'object', properties: { page_id: { type: 'string', description: 'UUID or URL of the page' } }, required: ['page_id'] },
  },
  {
    name: 'buildin_get_title',
    description: 'Get the title of a Buildin page by ID or URL',
    inputSchema: { type: 'object', properties: { page_id: { type: 'string', description: 'UUID or URL of the page' } }, required: ['page_id'] },
  },
  {
    name: 'buildin_read_page',
    description: 'Read a Buildin page and render its contents as Markdown. Accepts URL, UUID, or search query.',
    inputSchema: { type: 'object', properties: { query: { type: 'string', description: 'UUID, URL, or search query text' } }, required: ['query'] },
  },
  {
    name: 'buildin_search_pages',
    description: 'Search Buildin pages by name',
    inputSchema: {
      type: 'object',
      properties: {
        query: { type: 'string', description: 'Search query' },
        space_id: { type: 'string', description: 'Optional space ID. Uses BUILDIN_SPACE_ID env var by default.' },
      },
      required: ['query'],
    },
  },
  {
    name: 'buildin_create_page',
    description: 'Create a new page in Buildin.ai as a child of parent_page_id',
    inputSchema: {
      type: 'object',
      properties: {
        parent_page_id: { type: 'string', description: 'UUID or URL of the parent page' },
        title: { type: 'string', description: 'Title of the new page' },
      },
      required: ['parent_page_id', 'title'],
    },
  },
  {
    name: 'buildin_update_page',
    description: 'Update the title of an existing Buildin page',
    inputSchema: {
      type: 'object',
      properties: {
        page_id: { type: 'string', description: 'UUID or URL of the page' },
        title: { type: 'string', description: 'New title of the page' },
      },
      required: ['page_id', 'title'],
    },
  },
  {
    name: 'buildin_append_blocks',
    description: 'Append content blocks to the end of a Buildin page. Blocks are JSON array. Use block type 1 for text.',
    inputSchema: {
      type: 'object',
      properties: {
        page_id: { type: 'string', description: 'UUID or URL of the page' },
        blocks_json: { type: 'string', description: 'JSON array of block objects. Example: [{"type":1,"data":{"segments":[{"type":0,"text":"Hello"}]}}]' },
      },
      required: ['page_id', 'blocks_json'],
    },
  },
  {
    name: 'buildin_delete_block',
    description: 'Delete (archive) a block from a Buildin page',
    inputSchema: {
      type: 'object',
      properties: {
        block_id: { type: 'string', description: 'UUID or URL of the block to delete' },
        parent_id: { type: 'string', description: 'Optional: UUID of the parent block. Auto-detected if not provided.' },
      },
      required: ['block_id'],
    },
  },
];

// ---------------------------------------------------------------------------
// Tool execution
// ---------------------------------------------------------------------------
async function executeTool(name, args) {
  try {
    if (name === 'buildin_get_page_json') {
      const data = await buildinFetch('GET', `/api/docs/${parseId(args.page_id)}`);
      return { content: [{ type: 'text', text: JSON.stringify(data, null, 2) }] };
    }

    if (name === 'buildin_get_title') {
      const data = await buildinFetch('GET', `/api/blocks/${parseId(args.page_id)}`);
      return { content: [{ type: 'text', text: data?.data?.title || '(untitled)' }] };
    }

    if (name === 'buildin_read_page') {
      let query = args.query;
      let pageId = parseId(query);

      if (pageId === query && !query.includes('-')) {
        const spaceId = DEFAULT_SPACE_ID;
        if (!spaceId) throw new Error('space_id is required for search fallback. Provide BUILDIN_SPACE_ID env var.');

        const searchData = await buildinFetch('POST', `/api/search/${spaceId}/docs`, {
            page: 1, perPage: 5, query, source: 'quickFind', sort: 'relevance',
            filters: { createdBy: [], ancestors: [] },
          });
          const results = searchData?.data?.results || [];
          if (results.length === 0) {
            return { content: [{ type: 'text', text: `No pages found matching query: "${query}"` }] };
          }
          pageId = results[0].pageId || results[0].uuid;
      }

      const data = await buildinFetch('GET', `/api/docs/${pageId}`);
      const payload = data?.data || {};
      const blocks = payload.blocks || {};
      const page = blocks[pageId] || {};
      const title = page.title || '(untitled)';
      const lines = [`# ${title}\n`];
      const fullMarkdown = lines.concat(renderBlocksToMarkdown(page.subNodes || [], blocks)).join('\n');
      return { content: [{ type: 'text', text: fullMarkdown }] };
    }

    if (name === 'buildin_search_pages') {
      const spaceId = args.space_id || DEFAULT_SPACE_ID;
      if (!spaceId) throw new Error('space_id is required. Provide it as an argument or set BUILDIN_SPACE_ID env var.');

      const data = await buildinFetch('POST', `/api/search/${spaceId}/docs`, {
        page: 1, perPage: 20, query: args.query, source: 'quickFind', sort: 'relevance',
        filters: { createdBy: [], ancestors: [] },
      });
      const payload = data?.data || {};
      const results = payload.results || [];
      const blocks = payload.recordMap?.blocks || {};

      if (results.length === 0) return { content: [{ type: 'text', text: 'No results found.' }] };

      const lines = [`Found ${payload.total || 0} results (showing ${results.length}):\n`];
      for (const r of results) {
        const pId = r.pageId || r.uuid || '';
        const block = blocks[pId] || {};
        const title = block.title || r.hitText || '';
        const spId = block.spaceId || r.spaceId || '';
        lines.push(`  ${title}`, `    ID: ${pId}`, `    URL: https://buildin.ai/${spId}/${pId}`, '');
      }
      return { content: [{ type: 'text', text: lines.join('\n') }] };
    }

    if (name === 'buildin_create_page') {
      const parentId = parseId(args.parent_page_id);
      const spaceId = await getSpaceId(parentId);
      if (!spaceId) throw new Error(`Cannot determine spaceId for parent ${parentId}`);
      const userId = await getUserId();
      const pageId = randomUUID();
      const blockId = randomUUID();
      const now = Date.now();

      await buildinTransaction(spaceId, [
        { id: pageId, command: 'set', table: 'block', path: [], args: { uuid: pageId, spaceId, parentId, type: 0, textColor: '', backgroundColor: '', status: 1, permissions: [], createdAt: now, createdBy: userId, updatedBy: userId, updatedAt: now, data: { segments: [{ type: 0, text: args.title, enhancer: {} }], pageFixedWidth: true, format: { commentAlignment: 'top' } } } },
        { id: parentId, command: 'listAfter', table: 'block', path: ['subNodes'], args: { uuid: pageId } },
        { id: blockId, command: 'set', table: 'block', path: [], args: { uuid: blockId, spaceId, parentId: pageId, type: 1, textColor: '', backgroundColor: '', status: 1, permissions: [], createdAt: now, createdBy: userId, updatedBy: userId, updatedAt: now, data: { pageFixedWidth: true, format: { commentAlignment: 'top' } } } },
        { id: pageId, command: 'listAfter', table: 'block', path: ['subNodes'], args: { uuid: blockId } },
        { id: parentId, command: 'update', table: 'block', path: [], args: { updatedBy: userId, updatedAt: now } },
      ]);
      return { content: [{ type: 'text', text: `Created page: ${pageId}\nURL: https://buildin.ai/${spaceId}/${pageId}` }] };
    }

    if (name === 'buildin_update_page') {
      const pageId = parseId(args.page_id);
      const spaceId = await getSpaceId(pageId);
      const userId = await getUserId();
      const now = Date.now();
      await buildinTransaction(spaceId, [
        { id: pageId, command: 'update', table: 'block', path: ['data'], args: { segments: [{ type: 0, text: args.title, enhancer: {} }] } },
        { id: pageId, command: 'update', table: 'block', path: [], args: { updatedBy: userId, updatedAt: now } },
      ]);
      return { content: [{ type: 'text', text: `Updated page title for: ${pageId}` }] };
    }

    if (name === 'buildin_append_blocks') {
      const pageId = parseId(args.page_id);
      const blocks = JSON.parse(args.blocks_json);
      const spaceId = await getSpaceId(pageId);
      const userId = await getUserId();
      const now = Date.now();
      const ops = [];
      for (const block of blocks) {
        const blockId = randomUUID();
        ops.push(
          { id: blockId, command: 'set', table: 'block', path: [], args: { uuid: blockId, spaceId, parentId: pageId, type: block.type ?? 1, textColor: '', backgroundColor: '', status: 1, permissions: [], createdAt: now, createdBy: userId, updatedBy: userId, updatedAt: now, data: { pageFixedWidth: true, format: { commentAlignment: 'top' }, ...(block.data || {}) } } },
          { id: pageId, command: 'listAfter', table: 'block', path: ['subNodes'], args: { uuid: blockId } }
        );
      }
      ops.push({ id: pageId, command: 'update', table: 'block', path: [], args: { updatedBy: userId, updatedAt: now } });
      await buildinTransaction(spaceId, ops);
      return { content: [{ type: 'text', text: `Successfully appended ${blocks.length} blocks to page ${pageId}` }] };
    }

    if (name === 'buildin_delete_block') {
      const blockId = parseId(args.block_id);
      let parentId = args.parent_id ? parseId(args.parent_id) : null;
      if (!parentId) {
        const blockData = await buildinFetch('GET', `/api/blocks/${blockId}`);
        parentId = blockData?.data?.parentId || null;
        if (!parentId) throw new Error(`Cannot determine parent ID for block ${blockId}. Provide parent_id explicitly.`);
      }
      const spaceId = await getSpaceId(blockId);
      const userId = await getUserId();
      const now = Date.now();
      await buildinTransaction(spaceId, [
        { id: blockId, command: 'update', table: 'block', path: [], args: { status: -1, updatedBy: userId, updatedAt: now } },
        { id: parentId, command: 'listRemove', table: 'block', path: ['subNodes'], args: { uuid: blockId } },
      ]);
      return { content: [{ type: 'text', text: `Successfully deleted block ${blockId}` }] };
    }

    throw new Error(`Tool not found: ${name}`);
  } catch (error) {
    return { isError: true, content: [{ type: 'text', text: error.message }] };
  }
}

// ---------------------------------------------------------------------------
// CLI mode: node index.mjs cli <tool> '<json-args>'
// ---------------------------------------------------------------------------
if (process.argv[2] === 'cli') {
  const result = await executeTool(process.argv[3], JSON.parse(process.argv[4] || '{}'));
  console.log(JSON.stringify(result, null, 2));
  process.exit(0);
}

// ---------------------------------------------------------------------------
// MCP stdio server (newline-delimited JSON-RPC 2.0)
// ---------------------------------------------------------------------------
function send(obj) {
  process.stdout.write(JSON.stringify(obj) + '\n');
}

const rl = createInterface({ input: process.stdin, crlfDelay: Infinity });

rl.on('line', async (line) => {
  let msg;
  try { msg = JSON.parse(line.trim()); } catch { return; }

  const { id, method, params } = msg;

  if (method === 'initialize') {
    send({ jsonrpc: '2.0', id, result: { protocolVersion: '2024-11-05', capabilities: { tools: {} }, serverInfo: { name: 'buildin-mcp', version: '1.0.0' } } });
  } else if (method === 'tools/list') {
    send({ jsonrpc: '2.0', id, result: { tools: TOOLS } });
  } else if (method === 'tools/call') {
    const result = await executeTool(params.name, params.arguments || {});
    send({ jsonrpc: '2.0', id, result });
  } else if (id !== undefined) {
    send({ jsonrpc: '2.0', id, error: { code: -32601, message: `Method not found: ${method}` } });
  }
  // notifications (no id) are silently ignored
});

console.error('Buildin MCP server running on stdio');
