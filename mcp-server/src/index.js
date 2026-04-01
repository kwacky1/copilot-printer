#!/usr/bin/env node
/**
 * Copilot Printer MCP Server
 *
 * Provides tools for Copilot CLI to read and process documents
 * that have been "printed" via the Copilot Printer virtual printer.
 *
 * Tools:
 *   - list_print_jobs: List documents in the print inbox
 *   - read_print_job: Read a specific printed document
 *   - summarise_print_job: Read and prepare a document for AI summarisation
 *   - clear_print_job: Remove a processed document from the inbox
 */

import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { z } from "zod";
import * as fs from "node:fs";
import * as path from "node:path";
import * as os from "node:os";

const INBOX_DIR = process.env.COPILOT_PRINTER_DIR || path.join(os.homedir(), "PrintToCopilot");

// Ensure inbox exists
if (!fs.existsSync(INBOX_DIR)) {
  fs.mkdirSync(INBOX_DIR, { recursive: true });
}

/**
 * Convert a PDF file to markdown, creating .md and .meta.json sidecar files.
 * Tries pdftotext first, falls back to strings extraction.
 */
async function convertPdfToMd(pdfPath) {
  const { execSync } = await import("node:child_process");
  const baseName = path.basename(pdfPath, ".pdf");
  const mdPath = pdfPath.replace(/\.pdf$/, ".md");
  const metaPath = pdfPath.replace(/\.pdf$/, ".meta.json");

  let converter = "none";
  try {
    // Try pdftotext (from poppler)
    execSync(
      `export PATH=/opt/homebrew/bin:/usr/local/bin:$PATH; pdftotext -layout "${pdfPath}" "${mdPath}"`,
      { stdio: "pipe" }
    );
    converter = "pdftotext";
  } catch {
    try {
      // Fallback to strings
      execSync(`/usr/bin/strings "${pdfPath}" > "${mdPath}"`, {
        stdio: "pipe",
      });
      converter = "strings";
    } catch {
      fs.writeFileSync(
        mdPath,
        `# ${baseName}\n\n> ⚠️ Could not extract text from this PDF. Install poppler: \`brew install poppler\`\n`
      );
      converter = "error";
    }
  }

  // Write metadata
  const meta = {
    timestamp: new Date().toISOString(),
    title: baseName,
    converter,
    source: "copilot-printer-mcp-autoconvert",
  };
  fs.writeFileSync(metaPath, JSON.stringify(meta, null, 2));
}

const server = new McpServer({
  name: "copilot-printer",
  version: "1.0.0",
});

/**
 * List all print jobs in the inbox
 */
server.tool(
  "list_print_jobs",
  "List documents that have been printed to Copilot. Shows pending documents waiting for AI processing.",
  {},
  async () => {
    const files = fs.readdirSync(INBOX_DIR);

    // Auto-convert any PDFs that don't have a matching .md file yet
    const pdfFiles = files.filter(
      (f) => f.endsWith(".pdf") && !files.includes(f.replace(/\.pdf$/, ".md"))
    );
    for (const pdf of pdfFiles) {
      await convertPdfToMd(path.join(INBOX_DIR, pdf));
    }

    // Re-read after conversion
    const allFiles = fs.readdirSync(INBOX_DIR);
    const mdFiles = allFiles.filter((f) => f.endsWith(".md"));

    if (mdFiles.length === 0) {
      return {
        content: [
          {
            type: "text",
            text: "📭 No documents in the print inbox. Print something using 'Print to Copilot' from any app's Print dialog.",
          },
        ],
      };
    }

    // Read metadata for each job
    const jobs = mdFiles.map((mdFile) => {
      const metaFile = mdFile.replace(/\.md$/, ".meta.json");
      const metaPath = path.join(INBOX_DIR, metaFile);
      const mdPath = path.join(INBOX_DIR, mdFile);
      const stats = fs.statSync(mdPath);

      let meta = {};
      if (fs.existsSync(metaPath)) {
        try {
          meta = JSON.parse(fs.readFileSync(metaPath, "utf-8"));
        } catch {
          // ignore parse errors
        }
      }

      return {
        filename: mdFile,
        title: meta.title || mdFile.replace(/\.md$/, ""),
        timestamp: meta.timestamp || stats.mtime.toISOString(),
        converter: meta.converter || "unknown",
        size: stats.size,
        hasPdf: fs.existsSync(
          path.join(INBOX_DIR, mdFile.replace(/\.md$/, ".pdf"))
        ),
      };
    });

    // Sort newest first
    jobs.sort((a, b) => new Date(b.timestamp) - new Date(a.timestamp));

    const listing = jobs
      .map(
        (j, i) =>
          `${i + 1}. **${j.title}** (${j.filename})\n` +
          `   📅 ${j.timestamp} | 📄 ${(j.size / 1024).toFixed(1)}KB | ` +
          `🔧 ${j.converter}${j.hasPdf ? " | 📎 PDF available" : ""}`
      )
      .join("\n\n");

    return {
      content: [
        {
          type: "text",
          text: `📬 **${jobs.length} document(s) in the print inbox:**\n\n${listing}\n\nUse \`read_print_job\` with a filename to read a document.`,
        },
      ],
    };
  }
);

/**
 * Read a specific print job
 */
server.tool(
  "read_print_job",
  "Read the content of a printed document from the inbox. Returns the full markdown text of the document.",
  {
    filename: z
      .string()
      .describe(
        "Filename of the document to read (from list_print_jobs), or 'latest' for the most recent"
      ),
  },
  async ({ filename }) => {
    let targetFile = filename;

    if (filename === "latest") {
      const mdFiles = fs
        .readdirSync(INBOX_DIR)
        .filter((f) => f.endsWith(".md"))
        .sort()
        .reverse();

      if (mdFiles.length === 0) {
        return {
          content: [
            { type: "text", text: "📭 No documents in the print inbox." },
          ],
        };
      }
      targetFile = mdFiles[0];
    }

    const mdPath = path.join(INBOX_DIR, targetFile);

    if (!fs.existsSync(mdPath)) {
      return {
        content: [
          {
            type: "text",
            text: `❌ Document not found: ${targetFile}\nUse \`list_print_jobs\` to see available documents.`,
          },
        ],
      };
    }

    // Security: ensure we're not reading outside the inbox
    const resolved = path.resolve(mdPath);
    if (!resolved.startsWith(path.resolve(INBOX_DIR))) {
      return {
        content: [
          { type: "text", text: "❌ Access denied: path traversal detected." },
        ],
      };
    }

    const content = fs.readFileSync(mdPath, "utf-8");

    // Read metadata if available
    const metaPath = mdPath.replace(/\.md$/, ".meta.json");
    let meta = {};
    if (fs.existsSync(metaPath)) {
      try {
        meta = JSON.parse(fs.readFileSync(metaPath, "utf-8"));
      } catch {
        // ignore
      }
    }

    const header =
      `📄 **Document: ${meta.title || targetFile}**\n` +
      `📅 Captured: ${meta.timestamp || "unknown"}\n` +
      `🔧 Converter: ${meta.converter || "unknown"}\n` +
      `---\n\n`;

    return {
      content: [{ type: "text", text: header + content }],
    };
  }
);

/**
 * Summarise a print job — reads and formats for AI consumption
 */
server.tool(
  "summarise_print_job",
  "Read a printed document and prepare it for summarisation. Returns the document with a prompt asking for a summary and action items.",
  {
    filename: z
      .string()
      .default("latest")
      .describe("Filename to summarise, or 'latest'"),
  },
  async ({ filename }) => {
    let targetFile = filename;

    if (filename === "latest") {
      const mdFiles = fs
        .readdirSync(INBOX_DIR)
        .filter((f) => f.endsWith(".md"))
        .sort()
        .reverse();

      if (mdFiles.length === 0) {
        return {
          content: [
            { type: "text", text: "📭 No documents in the print inbox." },
          ],
        };
      }
      targetFile = mdFiles[0];
    }

    const mdPath = path.join(INBOX_DIR, targetFile);
    if (!fs.existsSync(mdPath)) {
      return {
        content: [
          { type: "text", text: `❌ Document not found: ${targetFile}` },
        ],
      };
    }

    const resolved = path.resolve(mdPath);
    if (!resolved.startsWith(path.resolve(INBOX_DIR))) {
      return {
        content: [
          { type: "text", text: "❌ Access denied: path traversal detected." },
        ],
      };
    }

    const content = fs.readFileSync(mdPath, "utf-8");

    return {
      content: [
        {
          type: "text",
          text:
            `The following document was printed to Copilot for processing.\n` +
            `Please provide:\n` +
            `1. A concise summary (3-5 sentences)\n` +
            `2. Key points or decisions\n` +
            `3. Action items (if any)\n` +
            `4. Any questions or areas needing clarification\n\n` +
            `---\n\n` +
            content,
        },
      ],
    };
  }
);

/**
 * Clear a processed print job
 */
server.tool(
  "clear_print_job",
  "Remove a processed document from the print inbox. Moves it to a 'processed' subdirectory.",
  {
    filename: z.string().describe("Filename to clear, or 'all' to clear everything"),
  },
  async ({ filename }) => {
    const processedDir = path.join(INBOX_DIR, "processed");
    fs.mkdirSync(processedDir, { recursive: true });

    if (filename === "all") {
      const files = fs.readdirSync(INBOX_DIR).filter((f) => !fs.statSync(path.join(INBOX_DIR, f)).isDirectory());
      for (const f of files) {
        fs.renameSync(path.join(INBOX_DIR, f), path.join(processedDir, f));
      }
      return {
        content: [
          {
            type: "text",
            text: `🧹 Moved ${files.length} file(s) to processed/`,
          },
        ],
      };
    }

    // Move the md, pdf, and meta files
    const baseName = filename.replace(/\.(md|pdf|meta\.json)$/, "");
    const extensions = [".md", ".pdf", ".meta.json"];
    let moved = 0;

    for (const ext of extensions) {
      const src = path.join(INBOX_DIR, baseName + ext);
      if (fs.existsSync(src)) {
        fs.renameSync(src, path.join(processedDir, baseName + ext));
        moved++;
      }
    }

    return {
      content: [
        {
          type: "text",
          text:
            moved > 0
              ? `🧹 Moved ${moved} file(s) for "${baseName}" to processed/`
              : `❌ No files found matching "${filename}"`,
        },
      ],
    };
  }
);

// --- Start the server ---
const transport = new StdioServerTransport();
await server.connect(transport);
