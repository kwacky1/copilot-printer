# 🩺 Copilot Printer — Troubleshooting

## Quick Diagnosis

```bash
./doctor.sh
```

The doctor script checks the full pipeline and tells you exactly what's broken.

---

## Common Issues

### PDF stuck in spool — never appears in ~/PrintToCopilot/

**Symptom:** You printed something, but Copilot says the inbox is empty. The PDF exists in `/private/var/spool/pdfwriter/<username>/` but there's no matching file in `~/PrintToCopilot/`.

**Root cause:** The spool → inbox transfer is triggered in two ways:
1. The launchd watcher (if installed) — fires automatically when PDFWriter writes a new file
2. The MCP `list_print_jobs` tool — imports on-demand when Copilot calls it

If neither has run since the PDF landed, it stays stuck in the spool.

**Fix — rescue a specific stuck file:**
```bash
./copilot-printer.sh "/private/var/spool/pdfwriter/$(whoami)/Your File.pdf" "Your File Title"
```

**Fix — install the launchd watcher (prevents recurrence):**
```bash
./install-launchd-watcher.sh
```

**Fix — trigger import without the watcher:**
Ask Copilot: *"What's in my print inbox?"* — calling `list_print_jobs` imports from spool automatically.

---

### "Print to Copilot" doesn't appear in the Print dialog

**Symptom:** The PDF dropdown in any app's Print dialog doesn't have a "Print to Copilot 🤖" option.

**Fixes:**

1. Check it's installed:
   ```bash
   ls ~/Library/PDF\ Services/
   ```
   You should see `Print to Copilot 🤖.app`. If not:
   ```bash
   ./install-pdf-service.sh
   ```

2. If installed but not showing, flush the print service registry:
   ```bash
   /System/Library/CoreServices/pbs -flush
   ```

3. Log out and back in (macOS caches the PDF Services list at login).

---

### "Printing just bombed out" — print failed before hitting the spool

**Symptom:** Tried to print, got an error or nothing happened, and there's no file in the spool at all.

**Causes:**
- The PDF Service `.app` crashed (AppleScript error)
- macOS sandbox blocked the shell script execution
- Very large documents can time out (the AppleScript `do shell script` has a timeout limit)

**Diagnosis:**
```bash
# Check if the app ran but logged errors
cat ~/PrintToCopilot/debug.log 2>/dev/null || echo "No debug log"

# Check Console.app for the error
log show --predicate 'process == "osascript"' --last 1h 2>/dev/null | tail -20
```

**Workaround for large documents:**
Print from the command line directly, bypassing the Print dialog:
```bash
./copilot-printer.sh ~/path/to/your.pdf "Document Title"
```

Or, if you have a PDF saved somewhere:
```bash
./copilot-printer.sh /path/to/file.pdf "Title"
```

**Workaround for session canvases:**
Slack canvases can be exported via File > Export in the Slack desktop app, then run through `copilot-printer.sh` directly.

---

### Watcher installed but not triggering

**Symptom:** `install-launchd-watcher.sh` reported success, but new PDFs still don't appear automatically.

**Check watcher status:**
```bash
launchctl list com.kwacky1.copilot-printer-watcher
```
Look for `"LastExitStatus"` — should be `0`. Any other value means it errored.

**Check the log:**
```bash
tail -20 ~/Library/Logs/copilot-printer-watcher.log
```

**Reload the watcher:**
```bash
PLIST="$HOME/Library/LaunchAgents/com.kwacky1.copilot-printer-watcher.plist"
launchctl unload "$PLIST" && launchctl load "$PLIST"
```

**Note:** `WatchPaths` in launchd fires when the watched directory changes. On macOS 14+, there can be a few seconds of delay. The agent also polls every 60 seconds as a safety net.

---

### MCP server not reading from inbox

**Symptom:** Copilot can't find printed documents even though files exist in `~/PrintToCopilot/`.

**Check MCP registration:**
```bash
cat ~/.copilot/mcp-config.json | grep -A5 copilot-printer
```

**Re-register:**
```bash
./install.sh
```

**Check the MCP server is functional:**
```bash
node mcp-server/src/index.js
# Should hang waiting for MCP input (Ctrl+C to exit)
# Any error here is the problem
```

---

## Architecture Reference

```
PDFWriter (CUPS virtual printer)
  └─→ /private/var/spool/pdfwriter/<user>/   ← PDF lands here first
           │
           ▼ (triggered by launchd WatchPaths OR list_print_jobs call)
  copilot-printer-watcher.sh
  └─→ copilot-printer.sh                     ← converts PDF → markdown
           │
           ▼
  ~/PrintToCopilot/                          ← inbox (3 files per job: .pdf, .md, .meta.json)
           │
           ▼ (on-demand)
  MCP server (copilot-printer)               ← Copilot CLI reads via list_print_jobs / read_print_job
```

**Transfer triggers:**

| Mechanism | How it works | Installed by |
|---|---|---|
| launchd watcher (recommended) | Fires when spool directory changes + polls every 60s | `install-launchd-watcher.sh` |
| `list_print_jobs` MCP tool | Imports on-demand when Copilot asks | Always available |
| Manual rescue | `./copilot-printer.sh <pdf> <title>` | n/a |

---

## Spool Archaeology

All PDFs ever printed accumulate in the spool — nothing cleans it up automatically. To see what's there:

```bash
ls -lt /private/var/spool/pdfwriter/$(whoami)/
```

To rescue any of them:
```bash
./doctor.sh   # will list all stuck files with rescue commands
```
