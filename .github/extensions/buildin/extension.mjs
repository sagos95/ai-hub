import { joinSession } from "@github/copilot-sdk/extension";
import { spawn } from "child_process";
import { fileURLToPath } from "url";
import { dirname, resolve } from "path";

const __dirname = dirname(fileURLToPath(import.meta.url));
const repoRoot = resolve(__dirname, "../..");
const mcpBuildPath = resolve(repoRoot, "integrations/buildin-mcp/build/index.js");

async function callMcpTool(toolName, toolArgs) {
  return new Promise((resolve, reject) => {
    const proc = spawn("node", [mcpBuildPath, "cli", toolName, JSON.stringify(toolArgs)], {
      stdio: ["ignore", "pipe", "pipe"],
      env: { ...process.env },
    });

    let stdout = "";
    let stderr = "";

    proc.stdout?.on("data", (chunk) => {
      stdout += chunk.toString();
    });

    proc.stderr?.on("data", (chunk) => {
      stderr += chunk.toString();
    });

    proc.on("close", (code) => {
      if (code === 0) {
        try {
          const result = JSON.parse(stdout);
          resolve(result);
        } catch (e) {
          reject(new Error(`Failed to parse MCP output: ${stdout}`));
        }
      } else {
        reject(new Error(`MCP tool failed: ${stderr || stdout}`));
      }
    });

    proc.on("error", reject);
  });
}

const session = await joinSession({
  tools: [
    {
      name: "buildin_read_page",
      description: "Read and render a Buildin page to Markdown. Accepts UUID, URL, or text query.",
      parameters: {
        type: "object",
        properties: {
          page_id: {
            type: "string",
            description: "UUID, URL, or text query to find the page",
          },
          use_shadow_index: {
            type: "boolean",
            description: "Use local cache (shadow index) for faster lookups. Defaults to true.",
          },
        },
        required: ["page_id"],
      },
      skipPermission: false,
      handler: async (args) => {
        const result = await callMcpTool("buildin_read_page", args);
        return result.content?.[0]?.text || JSON.stringify(result);
      },
    },
    {
      name: "buildin_search_pages",
      description: "Search Buildin pages by name",
      parameters: {
        type: "object",
        properties: {
          query: {
            type: "string",
            description: "Search query",
          },
          space_id: {
            type: "string",
            description: "Optional space ID. Uses process.env.BUILDIN_SPACE_ID by default.",
          },
        },
        required: ["query"],
      },
      skipPermission: false,
      handler: async (args) => {
        const result = await callMcpTool("buildin_search_pages", args);
        return result.content?.[0]?.text || JSON.stringify(result);
      },
    },
    {
      name: "buildin_create_page",
      description: "Create a new page in Buildin.ai as a child of parent_page_id",
      parameters: {
        type: "object",
        properties: {
          parent_page_id: {
            type: "string",
            description: "UUID or URL of the parent page",
          },
          title: {
            type: "string",
            description: "Title of the new page",
          },
        },
        required: ["parent_page_id", "title"],
      },
      skipPermission: false,
      handler: async (args) => {
        const result = await callMcpTool("buildin_create_page", args);
        return result.content?.[0]?.text || JSON.stringify(result);
      },
    },
    {
      name: "buildin_update_page",
      description: "Update the title of an existing Buildin page",
      parameters: {
        type: "object",
        properties: {
          page_id: {
            type: "string",
            description: "UUID or URL of the page",
          },
          title: {
            type: "string",
            description: "New title of the page",
          },
        },
        required: ["page_id", "title"],
      },
      skipPermission: false,
      handler: async (args) => {
        const result = await callMcpTool("buildin_update_page", args);
        return result.content?.[0]?.text || JSON.stringify(result);
      },
    },
    {
      name: "buildin_append_blocks",
      description: "Append content blocks to the end of a Buildin page. Blocks are JSON array. Use block type 1 for text.",
      parameters: {
        type: "object",
        properties: {
          page_id: {
            type: "string",
            description: "UUID or URL of the page",
          },
          blocks_json: {
            type: "string",
            description: 'JSON array of block objects. Example: [{"type":1,"data":{"segments":[{"type":0,"text":"Hello"}]}}]',
          },
        },
        required: ["page_id", "blocks_json"],
      },
      skipPermission: false,
      handler: async (args) => {
        const result = await callMcpTool("buildin_append_blocks", args);
        return result.content?.[0]?.text || JSON.stringify(result);
      },
    },
  ],
});
