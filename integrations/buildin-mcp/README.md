# Buildin MCP Server

This is an MCP (Model Context Protocol) server for Buildin.

## Setup

1. Install dependencies:
   ```bash
   npm install
   ```

2. Build the server:
   ```bash
   npm run build
   ```

## Usage

This server communicates over standard I/O (stdio). You can configure Claude or other MCP clients to start this server by running:

```bash
node build/index.js
```
