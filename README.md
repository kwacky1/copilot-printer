# 🖨️ Copilot Printer

**Print to Copilot from any application.**

A virtual printer that captures documents from any macOS app's Print dialog and makes them available to GitHub Copilot CLI for AI processing — summarisation, action item extraction, or any other analysis.

Born from the frustration of Slack Huddle AI notes being trapped in canvases with no export. If you can print it, you can Copilot it.

## How It Works

```
Any App → File > Print → PDF > "Print to Copilot 🤖"
    → PDF captured → converted to markdown → Copilot inbox
        → Copilot CLI reads via MCP → AI processing
```

### Components

| Component | What it does |
|---|---|
| `copilot-printer.sh` | Core script — receives PDF, converts to markdown |
| `install-pdf-service.sh` | Creates Automator Print Plugin for the Print dialog |
| `mcp-server/` | MCP server so Copilot CLI can read the inbox |
| `install.sh` | One-command installer for everything |

## Quick Start

```bash
# Clone and install
git clone https://github.com/kwacky1/copilot-printer.git
cd copilot-printer
./install.sh

# Print something from any app (File > Print > PDF > "Print to Copilot 🤖")

# Ask Copilot about it
copilot -i "What's in my print inbox?"
copilot -i "Summarise the latest document I printed"
```

## Manual Usage

### Print directly from the command line

```bash
# Convert a PDF
./copilot-printer.sh ~/Documents/meeting-notes.pdf "Team Meeting Notes"

# Pipe from another command
curl -s https://example.com/report.pdf | ./copilot-printer.sh - "Web Report"
```

### MCP Tools (used by Copilot automatically)

| Tool | Description |
|---|---|
| `list_print_jobs` | List documents waiting in the inbox |
| `read_print_job` | Read a specific document (or `"latest"`) |
| `summarise_print_job` | Read with a summarisation prompt |
| `clear_print_job` | Move processed docs to `processed/` subfolder |

## Requirements

- macOS 12.0+ (for Automator Print Plugin support)
- Node.js 18+ (for MCP server)
- Recommended: `poppler` and `pandoc` (`brew install poppler pandoc`)

The script degrades gracefully if conversion tools aren't available — it falls back to `textutil` (built into macOS), then `python3`, then raw `strings` extraction.

## Architecture

```
┌──────────────────────────┐
│     Any Application      │
│   File > Print > PDF >   │
│  "Print to Copilot 🤖"  │
└──────────┬───────────────┘
           │ PDF data
           ▼
┌──────────────────────────┐
│   copilot-printer.sh     │
│                          │
│ pdftotext → pandoc → .md │
│ (graceful degradation)   │
└──────────┬───────────────┘
           │ .md + .pdf + .meta.json
           ▼
┌──────────────────────────┐
│   ~/PrintToCopilot/      │
│   (inbox directory)      │
└──────────┬───────────────┘
           │ watched by
           ▼
┌──────────────────────────┐
│  copilot-printer-mcp     │
│  (MCP server for CLI)    │
│                          │
│  Tools:                  │
│   • list_print_jobs      │
│   • read_print_job       │
│   • summarise_print_job  │
│   • clear_print_job      │
└──────────────────────────┘
```

## Conversion Fallback Chain

| Priority | Tool | Quality | Install |
|---|---|---|---|
| 1 | `pdftotext` + `pandoc` | ⭐⭐⭐ Best | `brew install poppler pandoc` |
| 2 | `textutil` | ⭐⭐ Good | Built into macOS |
| 3 | `python3` + `pypdf` | ⭐⭐ Good | `pip install pypdf` |
| 4 | `strings` | ⭐ Basic | Built into macOS |

## File Structure

Each print job creates three files in `~/PrintToCopilot/`:

```
20260401-150730-Meeting-Notes.md         # Converted markdown
20260401-150730-Meeting-Notes.pdf        # Original PDF
20260401-150730-Meeting-Notes.meta.json  # Metadata (title, timestamp, converter)
```

## Uninstall

```bash
# Remove the PDF Service
rm -rf ~/Library/PDF\ Services/Print\ to\ Copilot\ 🤖.workflow

# Remove MCP registration (edit ~/.copilot/mcp-config.json and remove "copilot-printer")

# Remove inbox (optional — keeps your documents)
rm -rf ~/PrintToCopilot
```

## The Vision

This is Phase 1-2 of the Copilot Printer concept:

- [x] **Phase 1:** PDF Service — "Print to Copilot" in every Print dialog
- [x] **Phase 2:** MCP Server — Copilot CLI reads the inbox
- [ ] **Phase 3:** Full CUPS virtual printer backend (proper printer in System Preferences)
- [ ] **Phase 4:** AirPrint support (print to Copilot from iPhone!)

## Licence

MIT
