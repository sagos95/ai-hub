import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { CallToolRequestSchema, ListToolsRequestSchema } from "@modelcontextprotocol/sdk/types.js";
import crypto from 'crypto';
import { searchShadowIndex, updateShadowIndex } from "./shadow.js";

const BUILDIN_UI_TOKEN = process.env.BUILDIN_UI_TOKEN;
const BUILDIN_BASE_URL = "https://buildin.ai";
const DEFAULT_SPACE_ID = process.env.BUILDIN_SPACE_ID;

if (!BUILDIN_UI_TOKEN) {
  console.error("Error: BUILDIN_UI_TOKEN environment variable not set. Please authenticate first.");
  process.exit(1);
}

/**
 * Base fetch function mirroring the curl logic from bash scripts
 */
async function buildinFetch(method: string, endpoint: string, body: any = null): Promise<any> {
  const headers: Record<string, string> = {
    "Authorization": `Bearer ${BUILDIN_UI_TOKEN}`,
    "Content-Type": "application/json",
    "x-platform": "web-cookie",
    "x-app-origin": "web",
    "x-product": "buildin",
    "app_version_name": "1.146.0" // Mirroring exact headers from buildin.sh
  };

  const options: RequestInit = { method, headers };
  if (body) {
    options.body = JSON.stringify(body);
  }

  const res = await fetch(`${BUILDIN_BASE_URL}${endpoint}`, options);
  
  if (res.status === 401) {
    throw new Error("Buildin API Error: Token expired or invalid. Please re-authenticate.");
  }
  
  if (!res.ok) {
    const errorText = await res.text();
    throw new Error(`Buildin API Error: ${res.status} ${res.statusText} - ${errorText}`);
  }
  
  return res.json();
}

/**
 * Execute a Buildin UI API transaction
 */
async function buildinTransaction(spaceId: string, operations: any[]) {
  const reqId = crypto.randomUUID();
  const txId = crypto.randomUUID();
  
  const body = {
    requestId: reqId,
    transactions: [{
      id: txId,
      spaceId: spaceId,
      operations: operations
    }]
  };
  
  return await buildinFetch("POST", "/api/records/transactions", body);
}

/**
 * Get spaceId and current userId from Buildin
 */
async function getSpaceId(pageId: string): Promise<string> {
  const res = await buildinFetch("GET", `/api/blocks/${pageId}`);
  return res?.data?.spaceId || '';
}

async function getUserId(): Promise<string> {
  const res = await buildinFetch("GET", "/api/users/me");
  return res?.data?.uuid || '';
}
function parseId(input: string): string {
  const uuidRe = /[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/i;
  const match = input.match(uuidRe);
  return match ? match[0] : input;
}

// Markdown rendering logic ported from buildin-pages.sh
function renderSegments(segments: any[] | undefined): string {
  if (!segments) return '';
  const parts: string[] = [];
  for (const s of segments) {
    let text = s.text || '';
    const enh = s.enhancer || {};
    const url = s.url || '';
    
    if (enh.code) text = `\`${text}\``;
    else if (enh.bold) text = `**${text}**`;
    else if (enh.italic) text = `*${text}*`;
    
    if (url) text = `[${text}](${url})`;
    
    parts.push(text);
  }
  return parts.join('');
}

function renderBlocksToMarkdown(nodeIds: string[], blocks: Record<string, any>, indent: number = 0): string[] {
  const pfx = '  '.repeat(indent);
  const lines: string[] = [];

  for (const nid of nodeIds) {
    const b = blocks[nid];
    if (!b) continue;
    
    const t = b.type ?? 1;
    const d = b.data || {};
    const segs = d.segments || [];
    const text = renderSegments(segs);
    const sub = b.subNodes || [];
    const level = d.level ?? 1;

    switch (t) {
      case 0: { // Sub-page
        const title = b.title || text;
        const spaceId = b.spaceId || '';
        lines.push(`${pfx}> [${title}](https://buildin.ai/${spaceId}/${nid})\n`);
        break;
      }
      case 1: { // Paragraph
        if (text) lines.push(`${pfx}${text}\n`);
        else lines.push('');
        break;
      }
      case 3: { // Todo
        const checked = d.checked ? '☑' : '☐';
        lines.push(`${pfx}${checked} ${text}`);
        break;
      }
      case 4: { // Bulleted
        lines.push(`${pfx}- ${text}`);
        break;
      }
      case 5: { // Numbered
        lines.push(`${pfx}1. ${text}`);
        break;
      }
      case 6: { // Toggle
        lines.push(`${pfx}▶ ${text}\n`);
        break;
      }
      case 7: { // Heading
        const h = '#'.repeat(Math.min(level + 1, 4));
        lines.push(`${pfx}${h} ${text}\n`);
        break;
      }
      case 9: { // Divider
        lines.push(`${pfx}---\n`);
        break;
      }
      case 12: { // Quote
        lines.push(`${pfx}> ${text}\n`);
        break;
      }
      case 13: { // Callout
        const icon = (d.icon && d.icon.value) ? d.icon.value : '';
        lines.push(`${pfx}> ${icon} ${text}\n`);
        break;
      }
      case 14: { // Image
        const oss = d.ossName || '';
        lines.push(`${pfx}![${text}](${oss})\n`);
        break;
      }
      case 21: { // Bookmark
        const link = d.link || '';
        lines.push(`${pfx}[${text || link}](${link})\n`);
        break;
      }
      case 23: { // Equation
        lines.push(`${pfx}$$ ${text} $$\n`);
        break;
      }
      case 25: { // Code
        const lang = d.language || '';
        lines.push(`${pfx}\`\`\`${lang}`);
        lines.push(`${pfx}${text}`);
        lines.push(`${pfx}\`\`\`\n`);
        break;
      }
      default: {
        if (text) lines.push(`${pfx}${text}\n`);
        break;
      }
    }

    if (sub.length > 0 && t !== 0) {
      lines.push(...renderBlocksToMarkdown(sub, blocks, indent + 1));
    }
  }

  return lines;
}

// ==========================================
// MCP Server Setup
// ==========================================

const server = new Server(
  {
    name: "buildin-mcp",
    version: "1.0.0",
  },
  {
    capabilities: {
      tools: {},
    },
  }
);

server.setRequestHandler(ListToolsRequestSchema, async () => {
  return {
    tools: [
      {
        name: "buildin_get_page_json",
        description: "Get full JSON representation of a Buildin page or block by ID or URL",
        inputSchema: {
          type: "object",
          properties: {
            page_id: { type: "string", description: "UUID or URL of the page" }
          },
          required: ["page_id"],
        },
      },
      {
        name: "buildin_get_title",
        description: "Get the title of a Buildin page by ID or URL",
        inputSchema: {
          type: "object",
          properties: {
            page_id: { type: "string", description: "UUID or URL of the page" }
          },
          required: ["page_id"],
        },
      },
      {
        name: "buildin_read_page",
        description: "Read a Buildin page and render its contents as Markdown. Accepts URL, UUID, or search query.",
        inputSchema: {
          type: "object",
          properties: {
            query: { type: "string", description: "UUID, URL, or search query text" }
          },
          required: ["query"],
        },
      },
      {
        name: "buildin_search_pages",
        description: "Search Buildin pages by name",
        inputSchema: {
          type: "object",
          properties: {
            query: { type: "string", description: "Search query" },
            space_id: { type: "string", description: "Optional space ID. Uses process.env.BUILDIN_SPACE_ID by default." }
          },
          required: ["query"],
        },
      },
      {
        name: "buildin_create_page",
        description: "Create a new page in Buildin.ai as a child of parent_page_id",
        inputSchema: {
          type: "object",
          properties: {
            parent_page_id: { type: "string", description: "UUID or URL of the parent page" },
            title: { type: "string", description: "Title of the new page" }
          },
          required: ["parent_page_id", "title"],
        },
      },
      {
        name: "buildin_update_page",
        description: "Update the title of an existing Buildin page",
        inputSchema: {
          type: "object",
          properties: {
            page_id: { type: "string", description: "UUID or URL of the page" },
            title: { type: "string", description: "New title of the page" }
          },
          required: ["page_id", "title"],
        },
      },
      {
        name: "buildin_append_blocks",
        description: "Append content blocks to the end of a Buildin page. Blocks are JSON array. Use block type 1 for text.",
        inputSchema: {
          type: "object",
          properties: {
            page_id: { type: "string", description: "UUID or URL of the page" },
            blocks_json: { type: "string", description: "JSON array of block objects. Example: [{\"type\":1,\"data\":{\"segments\":[{\"type\":0,\"text\":\"Hello\"}]}}]" }
          },
          required: ["page_id", "blocks_json"],
        },
      }
    ],
  };
});

server.setRequestHandler(CallToolRequestSchema, async (request) => {
  const name = request.params.name;
  const args = request.params.arguments || {};
  return await executeTool(name, args);
});

async function executeTool(name: string, args: any) {
  try {
    if (name === "buildin_get_page_json") {
      const pageId = parseId(args.page_id as string);
      const data = await buildinFetch("GET", `/api/docs/${pageId}`);
      
      return {
        content: [{ type: "text", text: JSON.stringify(data, null, 2) }],
      };
    }

    if (name === "buildin_get_title") {
      const pageId = parseId(args.page_id as string);
      const data = await buildinFetch("GET", `/api/blocks/${pageId}`);
      const title = data?.data?.title || "(untitled)";
      
      return {
        content: [{ type: "text", text: title }],
      };
    }

    if (name === "buildin_read_page") {
      let query = args.query as string;
      let pageId = parseId(query);

      // If it doesn't look like a UUID, treat it as a search query
      if (pageId === query && !query.includes('-')) {
        const spaceId = DEFAULT_SPACE_ID;
        if (!spaceId) {
          throw new Error("space_id is required for search fallback. Provide BUILDIN_SPACE_ID env var.");
        }
        
        // 1. Check shadow index first
        const shadowMatchId = searchShadowIndex(query);
        if (shadowMatchId) {
          pageId = shadowMatchId;
        } else {
          // 2. Fallback to UI search API
          const body = {
            page: 1,
            perPage: 5,
            query: query,
            source: 'quickFind',
            sort: 'relevance',
            filters: { createdBy: [], ancestors: [] }
          };

          const searchData = await buildinFetch("POST", `/api/search/${spaceId}/docs`, body);
          const results = searchData?.data?.results || [];
          if (results.length === 0) {
            return {
              content: [{ type: "text", text: `No pages found matching query: "${query}"` }]
            };
          }
          // Take the best match
          pageId = results[0].pageId || results[0].uuid;
        }
      }

      const data = await buildinFetch("GET", `/api/docs/${pageId}`);
      
      const payload = data?.data || {};
      const blocks = payload.blocks || {};
      const page = blocks[pageId] || {};
      const title = page.title || "(untitled)";
      
      const lines = [`# ${title}\n`];
      const subNodes = page.subNodes || [];
      const markdownLines = renderBlocksToMarkdown(subNodes, blocks, 0);
      const fullMarkdown = lines.concat(markdownLines).join('\n');
      
      // Update shadow index
      updateShadowIndex(pageId, title, fullMarkdown, page.parentId);

      return {
        content: [{ type: "text", text: fullMarkdown }],
      };
    }

    if (name === "buildin_search_pages") {
      const query = args.query as string;
      const spaceId = (args.space_id as string) || DEFAULT_SPACE_ID;
      
      if (!spaceId) {
        throw new Error("space_id is required for search. Provide it as an argument or set BUILDIN_SPACE_ID env var.");
      }

      const body = {
        page: 1,
        perPage: 20,
        query: query,
        source: 'quickFind',
        sort: 'relevance',
        filters: { createdBy: [], ancestors: [] }
      };

      const data = await buildinFetch("POST", `/api/search/${spaceId}/docs`, body);
      const payload = data?.data || {};
      const results = payload.results || [];
      const blocks = payload.recordMap?.blocks || {};
      const total = payload.total || 0;

      if (results.length === 0) {
        return {
          content: [{ type: "text", text: "No results found." }]
        };
      }

      const lines = [`Found ${total} results (showing ${results.length}):\n`];
      
      for (const r of results) {
        const pId = r.pageId || r.uuid || '';
        const hit = r.hitText || '';
        const block = blocks[pId] || {};
        const title = block.title || hit;
        const spId = block.spaceId || r.spaceId || '';
        
        lines.push(`  ${title}`);
        lines.push(`    ID: ${pId}`);
        lines.push(`    URL: https://buildin.ai/${spId}/${pId}`);
        if (hit && hit !== title) {
          lines.push(`    Hit: ${hit.substring(0, 100)}...`);
        }
        lines.push('');
      }

      return {
        content: [{ type: "text", text: lines.join('\n') }],
      };
    }

    if (name === "buildin_create_page") {
      const parentId = parseId(args.parent_page_id as string);
      const title = args.title as string;

      const spaceId = await getSpaceId(parentId);
      if (!spaceId) {
        throw new Error(`Cannot determine spaceId for parent ${parentId}`);
      }

      const userId = await getUserId();
      const pageId = crypto.randomUUID();
      const blockId = crypto.randomUUID();
      const now = Date.now();

      const ops = [
        {
          id: pageId,
          command: 'set',
          table: 'block',
          path: [],
          args: {
            uuid: pageId,
            spaceId: spaceId,
            parentId: parentId,
            type: 0,
            textColor: '',
            backgroundColor: '',
            status: 1,
            permissions: [],
            createdAt: now,
            createdBy: userId,
            updatedBy: userId,
            updatedAt: now,
            data: {
              segments: [{ type: 0, text: title, enhancer: {} }],
              pageFixedWidth: true,
              format: { commentAlignment: 'top' }
            }
          }
        },
        {
          id: parentId,
          command: 'listAfter',
          table: 'block',
          path: ['subNodes'],
          args: { uuid: pageId }
        },
        {
          id: blockId,
          command: 'set',
          table: 'block',
          path: [],
          args: {
            uuid: blockId,
            spaceId: spaceId,
            parentId: pageId,
            type: 1,
            textColor: '',
            backgroundColor: '',
            status: 1,
            permissions: [],
            createdAt: now,
            createdBy: userId,
            updatedBy: userId,
            updatedAt: now,
            data: {
              pageFixedWidth: true,
              format: { commentAlignment: 'top' }
            }
          }
        },
        {
          id: pageId,
          command: 'listAfter',
          table: 'block',
          path: ['subNodes'],
          args: { uuid: blockId }
        },
        {
          id: parentId,
          command: 'update',
          table: 'block',
          path: [],
          args: { updatedBy: userId, updatedAt: now }
        }
      ];

      await buildinTransaction(spaceId, ops);

      return {
        content: [{ type: "text", text: `Created page: ${pageId}\nURL: https://buildin.ai/${spaceId}/${pageId}` }],
      };
    }

    if (name === "buildin_update_page") {
      const pageId = parseId(args.page_id as string);
      const title = args.title as string;

      const spaceId = await getSpaceId(pageId);
      const userId = await getUserId();
      const now = Date.now();

      const ops = [
        {
          id: pageId,
          command: 'update',
          table: 'block',
          path: ['data'],
          args: { segments: [{ type: 0, text: title, enhancer: {} }] }
        },
        {
          id: pageId,
          command: 'update',
          table: 'block',
          path: [],
          args: { updatedBy: userId, updatedAt: now }
        }
      ];

      await buildinTransaction(spaceId, ops);

      return {
        content: [{ type: "text", text: `Updated page title for: ${pageId}` }],
      };
    }

    if (name === "buildin_append_blocks") {
      const pageId = parseId(args.page_id as string);
      const blocksJsonStr = args.blocks_json as string;
      const blocks = JSON.parse(blocksJsonStr);

      const spaceId = await getSpaceId(pageId);
      const userId = await getUserId();
      const now = Date.now();
      const ops = [];

      for (const block of blocks) {
        const blockId = crypto.randomUUID();
        const blockType = block.type ?? 1;
        const blockData = block.data || {};

        ops.push({
          id: blockId,
          command: 'set',
          table: 'block',
          path: [],
          args: {
            uuid: blockId,
            spaceId: spaceId,
            parentId: pageId,
            type: blockType,
            textColor: '',
            backgroundColor: '',
            status: 1,
            permissions: [],
            createdAt: now,
            createdBy: userId,
            updatedBy: userId,
            updatedAt: now,
            data: { pageFixedWidth: true, format: { commentAlignment: 'top' }, ...blockData }
          }
        });

        ops.push({
          id: pageId,
          command: 'listAfter',
          table: 'block',
          path: ['subNodes'],
          args: { uuid: blockId }
        });
      }

      ops.push({
        id: pageId,
        command: 'update',
        table: 'block',
        path: [],
        args: { updatedBy: userId, updatedAt: now }
      });

      await buildinTransaction(spaceId, ops);

      return {
        content: [{ type: "text", text: `Successfully appended ${blocks.length} blocks to page ${pageId}` }],
      };
    }

    throw new Error(`Tool not found: ${name}`);
  } catch (error: any) {
    return {
      isError: true,
      content: [
        {
          type: "text",
          text: error.message,
        },
      ],
    };
  }
}

async function run() {
  const transport = new StdioServerTransport();
  await server.connect(transport);
  console.error("Buildin MCP server running on stdio");
}

if (process.argv[2] === 'cli') {
  const toolName = process.argv[3];
  const toolArgs = JSON.parse(process.argv[4] || '{}');
  executeTool(toolName, toolArgs).then(result => {
    console.log(JSON.stringify(result, null, 2));
  }).catch(error => {
    console.error("Fatal error:", error);
    process.exit(1);
  });
} else {
  run().catch((error) => {
    console.error("Fatal error:", error);
    process.exit(1);
  });
}
