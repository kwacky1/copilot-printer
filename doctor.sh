#!/bin/bash
# doctor.sh — Copilot Printer health check
# Diagnoses the full pipeline: PDFWriter → spool → watcher → inbox → MCP
#
# Usage: ./doctor.sh

export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SPOOL="/private/var/spool/pdfwriter/$(whoami)"
INBOX="$HOME/PrintToCopilot"
WATCHER_LABEL="com.kwacky1.copilot-printer-watcher"
WATCHER_PLIST="$HOME/Library/LaunchAgents/$WATCHER_LABEL.plist"
WATCHER_LOG="$HOME/Library/Logs/copilot-printer-watcher.log"
MCP_SERVER="$SCRIPT_DIR/mcp-server/src/index.js"

ok()   { echo "  ✅ $*"; }
warn() { echo "  ⚠️  $*"; }
fail() { echo "  ❌ $*"; }
info() { echo "  ℹ️  $*"; }

echo ""
echo "  🩺 Copilot Printer — Doctor"
echo "  ━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# --- 1. Dependencies ---
echo "📦 Dependencies"
command -v pdftotext &>/dev/null && ok "pdftotext (poppler) found: $(which pdftotext)" || warn "pdftotext not found — install with: brew install poppler"
command -v pandoc &>/dev/null   && ok "pandoc found: $(which pandoc)"                  || info "pandoc not found (optional — pdftotext fallback is fine)"
command -v node &>/dev/null     && ok "node found: $(which node) [$(node --version)]"  || fail "node not found — MCP server won't start"
echo ""

# --- 2. PDF Service (printer in Print dialog) ---
echo "🖨️  PDF Service"
PDF_SERVICES_DIR="$HOME/Library/PDF Services"
PRINTER_APP="$PDF_SERVICES_DIR/Print to Copilot 🤖.app"
if [[ -d "$PRINTER_APP" ]]; then
  ok "Print to Copilot app installed: $PRINTER_APP"
else
  warn "Print to Copilot app NOT found — run: ./install-pdf-service.sh"
  info "Without this, you can't use 'Print to Copilot' from the Print dialog."
  info "Alternative: use PDFWriter (CUPS virtual printer) if installed separately."
fi
echo ""

# --- 3. PDFWriter spool ---
echo "📂 PDFWriter Spool"
if [[ -d "$SPOOL" ]]; then
  ok "Spool directory exists: $SPOOL"
  SPOOL_COUNT=$(find "$SPOOL" -maxdepth 1 -name "*.pdf" 2>/dev/null | wc -l | tr -d ' ')
  if [[ "$SPOOL_COUNT" -gt 0 ]]; then
    info "$SPOOL_COUNT PDF(s) in spool (oldest → newest):"
    while IFS= read -r f; do
      fname=$(basename "$f")
      fsize=$(stat -f "%z" "$f" 2>/dev/null || echo "?")
      fdate=$(stat -f "%Sm" -t "%Y-%m-%d %H:%M" "$f" 2>/dev/null || echo "?")
      INBOX_PDF="$INBOX/$fname"
      INBOX_MD="${INBOX_PDF%.pdf}.md"
      if [[ -f "$INBOX_MD" ]]; then
        info "  ✅ $fname ($fdate, ${fsize}B) — already in inbox"
      else
        warn "  📌 STUCK: $fname ($fdate, ${fsize}B) — NOT in inbox yet"
        info "     Rescue: bash $SCRIPT_DIR/copilot-printer.sh \"$f\" \"${fname%.pdf}\""
      fi
    done < <(find "$SPOOL" -maxdepth 1 -name "*.pdf" ! -name "Icon*" -print 2>/dev/null | sort -t/ -k7)
  else
    ok "Spool is empty (no pending PDFs)"
  fi
else
  warn "Spool directory not found: $SPOOL"
  info "PDFWriter may not be installed, or no PDFs have been spooled yet."
fi
echo ""

# --- 4. Inbox ---
echo "📬 Inbox"
if [[ -d "$INBOX" ]]; then
  ok "Inbox exists: $INBOX"
  MD_COUNT=$(find "$INBOX" -maxdepth 1 -name "*.md" 2>/dev/null | wc -l | tr -d ' ')
  PDF_WITHOUT_MD=$(find "$INBOX" -maxdepth 1 -name "*.pdf" 2>/dev/null | while read -r p; do [[ ! -f "${p%.pdf}.md" ]] && echo "$p"; done | wc -l | tr -d ' ')
  info "$MD_COUNT document(s) in inbox"
  if [[ "$PDF_WITHOUT_MD" -gt 0 ]]; then
    warn "$PDF_WITHOUT_MD PDF(s) in inbox without .md — will be converted on next list_print_jobs call"
  fi
else
  warn "Inbox not found: $INBOX"
  info "Run: mkdir -p $INBOX"
fi
echo ""

# --- 5. Spool watcher (launchd agent) ---
echo "⏱️  Spool Watcher (launchd)"
if [[ -f "$WATCHER_PLIST" ]]; then
  ok "Watcher plist installed: $WATCHER_PLIST"
  WATCHER_STATUS=$(launchctl list "$WATCHER_LABEL" 2>/dev/null | grep '"PID"' | awk '{print $3}' | tr -d ',;')
  if [[ -n "$WATCHER_STATUS" ]] && [[ "$WATCHER_STATUS" != "0" ]]; then
    ok "Watcher is loaded (PID $WATCHER_STATUS)"
  else
    LAST_EXIT=$(launchctl list "$WATCHER_LABEL" 2>/dev/null | grep '"LastExitStatus"' | awk '{print $3}' | tr -d ',;')
    if [[ "$LAST_EXIT" == "0" ]]; then
      ok "Watcher loaded, last run exited cleanly (exit 0)"
    else
      warn "Watcher loaded but last exit status: ${LAST_EXIT:-unknown}"
      info "Reload: launchctl unload $WATCHER_PLIST && launchctl load $WATCHER_PLIST"
    fi
  fi
  if [[ -f "$WATCHER_LOG" ]]; then
    info "Last 3 log lines:"
    tail -3 "$WATCHER_LOG" | sed 's/^/     /'
  fi
else
  warn "Spool watcher NOT installed — PDFs require manual import or list_print_jobs call"
  info "Install: ./install-launchd-watcher.sh"
  info "Without the watcher, PDFs only get imported when Copilot calls list_print_jobs."
fi
echo ""

# --- 6. MCP Server ---
echo "🔌 MCP Server"
if [[ -f "$MCP_SERVER" ]]; then
  ok "MCP server script found: $MCP_SERVER"
else
  fail "MCP server not found: $MCP_SERVER"
fi

MCP_CONFIG="$HOME/.copilot/mcp-config.json"
if [[ -f "$MCP_CONFIG" ]]; then
  if grep -q "copilot-printer" "$MCP_CONFIG" 2>/dev/null; then
    ok "MCP server registered in $MCP_CONFIG"
  else
    warn "copilot-printer NOT in MCP config — run: ./install.sh"
  fi
else
  warn "MCP config not found: $MCP_CONFIG"
fi

MCP_PROCS=$(pgrep -f "copilot-printer/mcp-server" 2>/dev/null | wc -l | tr -d ' ')
if [[ "$MCP_PROCS" -gt 0 ]]; then
  ok "$MCP_PROCS MCP server process(es) running"
else
  info "No MCP server process running (starts on-demand with Copilot CLI)"
fi
echo ""

# --- 7. Summary ---
echo "  ━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Done. Fix any ❌ or ⚠️ items above."
echo "  For stuck files: bash $SCRIPT_DIR/copilot-printer.sh <spool-pdf> <title>"
echo ""
