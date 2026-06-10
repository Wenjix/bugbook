#!/usr/bin/env node

// Bugbook MCP Server
//
// MCP config (add to ~/.claude/mcp.json):
//
//   {
//     "mcpServers": {
//       "bugbook": {
//         "command": "node",
//         "args": ["/Users/maxforsey/Code/bugbook/mcp-server/index.js"]
//       }
//     }
//   }

import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { z } from "zod/v3";
import { execFile } from "node:child_process";
import { writeFile, unlink } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { randomUUID } from "node:crypto";

const BUGBOOK = process.env.BUGBOOK_BIN || "bugbook";

// Run a bugbook CLI command and return stdout
function run(args) {
  return new Promise((resolve, reject) => {
    execFile(BUGBOOK, args, { maxBuffer: 10 * 1024 * 1024 }, (err, stdout, stderr) => {
      if (err) {
        reject(new Error(stderr?.trim() || err.message));
      } else {
        resolve(stdout);
      }
    });
  });
}

// Run a bugbook CLI command, never rejecting on nonzero exit.
// Artifact validation prints its JSON error report to stdout and exits 1,
// so callers need both the exit code and stdout.
function runStatus(args) {
  return new Promise((resolve) => {
    execFile(BUGBOOK, args, { maxBuffer: 10 * 1024 * 1024 }, (err, stdout, stderr) => {
      const code = err ? (typeof err.code === "number" ? err.code : 1) : 0;
      const errText = (stderr ?? "").trim() || (err && !stdout ? err.message : "");
      resolve({ code, stdout: stdout ?? "", stderr: errText });
    });
  });
}

// Write content to a temp file, return its path
async function writeTmp(content, ext = ".md") {
  const p = join(tmpdir(), `bugbook-mcp-${randomUUID()}${ext}`);
  await writeFile(p, content, "utf-8");
  return p;
}

// Clean up a temp file (best-effort)
async function cleanTmp(p) {
  try { await unlink(p); } catch {}
}

// Return an MCP text result
function ok(text) {
  return { content: [{ type: "text", text }] };
}

function fail(msg) {
  return { content: [{ type: "text", text: msg }], isError: true };
}

// -------------------------------------------------------------------

const server = new McpServer({
  name: "bugbook",
  version: "1.0.0",
});

// 1. bugbook_page_list
server.tool(
  "bugbook_page_list",
  "List all pages in the Bugbook workspace",
  {},
  async () => {
    try {
      return ok(await run(["page", "list"]));
    } catch (e) {
      return fail(e.message);
    }
  }
);

// 2. bugbook_page_get
server.tool(
  "bugbook_page_get",
  "Get a page's content by name",
  { name: z.string().describe("Page path, relative path, or page name") },
  async ({ name }) => {
    try {
      return ok(await run(["page", "get", name]));
    } catch (e) {
      return fail(e.message);
    }
  }
);

// 3. bugbook_page_create
server.tool(
  "bugbook_page_create",
  "Create a new page",
  {
    name: z.string().describe("New page path or name"),
    content: z.string().optional().describe("Markdown content for the page"),
  },
  async ({ name, content }) => {
    let tmp;
    try {
      const args = ["page", "create", name];
      if (content) {
        tmp = await writeTmp(content);
        args.push("--content-file", tmp);
      }
      return ok(await run(args));
    } catch (e) {
      return fail(e.message);
    } finally {
      if (tmp) await cleanTmp(tmp);
    }
  }
);

// 4. bugbook_page_update
server.tool(
  "bugbook_page_update",
  "Update an existing page's content",
  {
    name: z.string().describe("Page path, relative path, or page name"),
    content: z.string().describe("New markdown content for the page"),
  },
  async ({ name, content }) => {
    let tmp;
    try {
      tmp = await writeTmp(content);
      return ok(await run(["page", "update", name, "--content-file", tmp]));
    } catch (e) {
      return fail(e.message);
    } finally {
      if (tmp) await cleanTmp(tmp);
    }
  }
);

// 5. bugbook_db_list
server.tool(
  "bugbook_db_list",
  "List all databases in the workspace",
  {},
  async () => {
    try {
      return ok(await run(["db", "list"]));
    } catch (e) {
      return fail(e.message);
    }
  }
);

// 6. bugbook_db_schema
server.tool(
  "bugbook_db_schema",
  "Get the schema of a database",
  { name: z.string().describe("Database name or ID") },
  async ({ name }) => {
    try {
      return ok(await run(["db", "schema", name]));
    } catch (e) {
      return fail(e.message);
    }
  }
);

// 7. bugbook_query
server.tool(
  "bugbook_query",
  "Query rows from a database",
  {
    db: z.string().describe("Database name or ID"),
    filter: z.string().optional().describe("Filter expression"),
    sort: z.string().optional().describe("Sort expression"),
    limit: z.number().optional().describe("Maximum number of rows to return"),
    body: z.boolean().optional().describe("Include row body content"),
  },
  async ({ db, filter, sort, limit, body }) => {
    try {
      const args = ["query", db];
      if (filter) args.push("--filter", filter);
      if (sort) args.push("--sort", sort);
      if (limit !== undefined) args.push("--limit", String(limit));
      if (body) args.push("--body");
      return ok(await run(args));
    } catch (e) {
      return fail(e.message);
    }
  }
);

// 8. bugbook_row_create
server.tool(
  "bugbook_row_create",
  "Create a new row in a database",
  {
    db: z.string().describe("Database name or ID"),
    properties: z.record(z.string()).describe("Property key-value pairs to set"),
    body: z.string().optional().describe("Markdown body content for the row"),
  },
  async ({ db, properties, body }) => {
    let tmp;
    try {
      const args = ["create", db];
      for (const [k, v] of Object.entries(properties)) {
        args.push("--set", `${k}=${v}`);
      }
      if (body) {
        tmp = await writeTmp(body);
        args.push("--body-file", tmp);
      }
      return ok(await run(args));
    } catch (e) {
      return fail(e.message);
    } finally {
      if (tmp) await cleanTmp(tmp);
    }
  }
);

// 9. bugbook_row_update
server.tool(
  "bugbook_row_update",
  "Update an existing row in a database",
  {
    db: z.string().describe("Database name or ID"),
    row_id: z.string().describe("Row ID to update"),
    properties: z.record(z.string()).optional().describe("Property key-value pairs to set"),
    body: z.string().optional().describe("New markdown body content for the row"),
  },
  async ({ db, row_id, properties, body }) => {
    let tmp;
    try {
      const args = ["update", db, row_id];
      if (properties) {
        for (const [k, v] of Object.entries(properties)) {
          args.push("--set", `${k}=${v}`);
        }
      }
      if (body) {
        tmp = await writeTmp(body);
        args.push("--body-file", tmp);
      }
      return ok(await run(args));
    } catch (e) {
      return fail(e.message);
    } finally {
      if (tmp) await cleanTmp(tmp);
    }
  }
);

// 10. bugbook_row_get
server.tool(
  "bugbook_row_get",
  "Get a single row by ID from a database",
  {
    db: z.string().describe("Database name or ID"),
    row_id: z.string().describe("Row ID"),
    body: z.boolean().optional().describe("Include row body content"),
  },
  async ({ db, row_id, body }) => {
    try {
      const args = ["get", db, row_id];
      if (body) args.push("--body");
      return ok(await run(args));
    } catch (e) {
      return fail(e.message);
    }
  }
);

// bugbook_artifact_create
server.tool(
  "bugbook_artifact_create",
  "Create a self-contained interactive HTML artifact in the Bugbook workspace. " +
  "Artifacts render in a sandboxed OFFLINE webview, so the HTML must be ONE fully " +
  "self-contained file: all CSS and JS inline, data embedded as <script " +
  "type=\"application/json\">, NO external resources (no CDN scripts, remote " +
  "stylesheets, images, fonts — fetch/WebSocket are blocked at render time too). " +
  "Plain <a href=\"https://...\"> links are allowed (they open behind a native " +
  "confirmation). Required in <head>: <meta name=\"bugbook-artifact\" content=\"1\"> " +
  "and <meta name=\"bugbook-title\" content=\"...\">. Place page-attached artifacts " +
  "at '<Page Name>/<topic>.html' and row-attached at '<Database>/_artifacts/" +
  "<row-slug>-<topic>.html'. Validation runs automatically: on failure nothing is " +
  "written and the errors are returned. The result includes a markdown_link line — " +
  "always add it to the parent page or row body.",
  {
    path: z.string().describe("Workspace-relative target path ending in .html"),
    html: z.string().describe("Complete self-contained HTML document"),
  },
  async ({ path, html }) => {
    let tmp;
    try {
      tmp = await writeTmp(html, ".html");
      const { code, stdout, stderr } = await runStatus(["artifact", "create", path, "--content-file", tmp]);
      return code === 0 ? ok(stdout) : fail(stdout.trim() || stderr || "artifact create failed");
    } catch (e) {
      return fail(e.message);
    } finally {
      if (tmp) await cleanTmp(tmp);
    }
  }
);

// bugbook_artifact_validate
server.tool(
  "bugbook_artifact_validate",
  "Validate an existing HTML artifact in the Bugbook workspace. Checks the required " +
  "<meta name=\"bugbook-artifact\" content=\"1\"> marker, rejects any external " +
  "resource reference (script/link/img/css url()/@import/meta-refresh — artifacts " +
  "must inline everything; only clickable <a href> links are allowed), and enforces " +
  "size limits (warn >2MB, error >10MB). Returns a JSON report with errors and " +
  "warnings; fix every error and re-validate.",
  {
    path: z.string().describe("Workspace-relative or absolute path to a .html artifact"),
  },
  async ({ path }) => {
    try {
      const { code, stdout, stderr } = await runStatus(["artifact", "validate", path]);
      return code === 0 ? ok(stdout) : fail(stdout.trim() || stderr || "artifact validation failed");
    } catch (e) {
      return fail(e.message);
    }
  }
);

// Start the server
const transport = new StdioServerTransport();
await server.connect(transport);
