#!/bin/bash
# install-launchd-watcher.sh
# Installs the copilot-printer launchd watcher agent.
# This provides push-based spool monitoring — PDFs are imported automatically
# when PDFWriter writes them, without needing to call list_print_jobs first.
#
# Usage: ./install-launchd-watcher.sh
#        ./install-launchd-watcher.sh --uninstall

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LABEL="com.kwacky1.copilot-printer-watcher"
PLIST_SRC="$SCRIPT_DIR/$LABEL.plist"
PLIST_DEST="$HOME/Library/LaunchAgents/$LABEL.plist"
WATCHER_SCRIPT="$SCRIPT_DIR/copilot-printer-watcher.sh"
SPOOL="/private/var/spool/pdfwriter/$(whoami)"
LOG_DIR="$HOME/Library/Logs"

if [[ "${1:-}" == "--uninstall" ]]; then
  echo "🗑️  Uninstalling copilot-printer watcher..."
  launchctl unload "$PLIST_DEST" 2>/dev/null && echo "   ✅ Unloaded from launchd" || echo "   ℹ️  Not loaded"
  rm -f "$PLIST_DEST" && echo "   ✅ Removed plist"
  echo "   Done. Watcher removed."
  exit 0
fi

echo ""
echo "  ⏱️  Copilot Printer — Spool Watcher Installer"
echo "  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Make watcher script executable
chmod +x "$WATCHER_SCRIPT"
echo "   ✅ Watcher script: $WATCHER_SCRIPT"

# Substitute placeholders in plist template → installed plist
mkdir -p "$HOME/Library/LaunchAgents"
sed \
  -e "s|SCRIPT_PLACEHOLDER|$WATCHER_SCRIPT|g" \
  -e "s|SPOOL_PLACEHOLDER|$SPOOL|g" \
  -e "s|HOME_PLACEHOLDER|$HOME|g" \
  "$PLIST_SRC" > "$PLIST_DEST"
echo "   ✅ Installed plist: $PLIST_DEST"

# Unload first in case it was previously loaded
launchctl unload "$PLIST_DEST" 2>/dev/null || true

# Load it
launchctl load "$PLIST_DEST"
echo "   ✅ Loaded into launchd"

echo ""
echo "  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  ✅ Spool watcher installed and running!"
echo "  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "  📂 Watching: $SPOOL"
echo "  📥 Importing to: $HOME/PrintToCopilot/"
echo "  📋 Logs: $LOG_DIR/copilot-printer-watcher.log"
echo ""
echo "  New PDFs will be auto-imported within seconds of printing."
echo "  No need to call list_print_jobs to trigger the import."
echo ""
echo "  To uninstall: ./install-launchd-watcher.sh --uninstall"
echo ""
