import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { CallToolRequestSchema, ListToolsRequestSchema } from "@modelcontextprotocol/sdk/types.js";

const BUILDIN_UI_TOKEN = process.env.BUILDIN_UI_TOKEN;
const BUILDIN_BASE_URL = "https://buildin.ai";

if (!BUILDIN_UI_TOKEN) {
  console.error("Error: BUILDIN_UI_TOKEN environment variable not set. Please authenticate first.");
  process.exit(1);
}

/**
 * Base fetch function mirroring the curl logic from bash scripts
 */
async function buildinFetch(method, endpoint, body = null) {
  const headers = {
    "Authorization": `Bearer ${BUILDIN_UI_TOKEN}`,
    "Content-Type": "application/json",
    "x-platform": "web-cookie",
    "x-app-origin": "web",
    "x-product": "buildin",
    "app_version_name": "1.146.0" // Mirroring exact headers from buildin.sh
  };

  const options = { method, headers };
  if (body) {
    options.body = JSON.stringify(body);
  }

  const res = await fetch(`${BUILDIN_BASE_URL}${endpoint}`, options);
  
  if (res.status === 401) {
    throw new Error("Buildin API Error: Token expired or invalid. Please re-authenticate.");
  }
  
  if (!res.ok) {
    throw new Error(`Buildin API Error: ${res.status} ${res.statusText} - ${await res.text()}`);
  }
  
  return res.json();
}

/**
 * Extract UUID from string or URL
 */
function parseId(input) {
  const uuidRe = /[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/i;
  const match = input.match(uuidRe);
  return match ? match[0] : input;
}

// ==========================================
// MCP Server Setup
// ==========================================

const server = new Server(
  {
    name: "buildin-mcp-draft",
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
        name: "buildin_get_page",
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
      }
    ],
  };
});

server.setRequestHandler(CallToolRequestSchema, async (request) => {
  const { name, arguments: args } = request.params;

  try {
    if (name === "buildin_get_page") {
      const pageId = parseId(args.page_id);
      const data = await buildinFetch("GET", `/api/docs/${pageId}`);
      
      return {
        content: [
          {
            type: "text",
            text: JSON.stringify(data, null, 2),
          },
        ],
      };
    }

    if (name === "buildin_get_title") {
      const pageId = parseId(args.page_id);
      // Mirrors buildin-nav.sh get_title()
      const data = await buildinFetch("GET", `/api/blocks/${pageId}`);
      const title = data?.data?.title || "(untitled)";
      
      return {
        content: [
          {
            type: "text",
            text: title,
          },
        ],
      };
    }

    throw new Error(`Tool not found: ${name}`);
  } catch (error) {
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
});

// Run server
async function run() {
  const transport = new StdioServerTransport();
  await server.connect(transport);
  console.error("Buildin Draft MCP server running on stdio");
}

run().catch((error) => {
  console.error("Fatal error:", error);
  process.exit(1);
});
