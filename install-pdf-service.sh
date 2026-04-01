#!/bin/bash
# install-pdf-service.sh — Creates the "Print to Copilot" PDF Service
# This installs an AppleScript app in ~/Library/PDF Services/ so it
# appears in every app's Print > PDF dropdown menu.
#
# Usage: ./install-pdf-service.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
COPILOT_PRINTER="$SCRIPT_DIR/copilot-printer.sh"
SERVICE_NAME="Print to Copilot 🤖"
PDF_SERVICES_DIR="$HOME/Library/PDF Services"
APP_PATH="$PDF_SERVICES_DIR/$SERVICE_NAME.app"

echo "🖨️  Installing 'Print to Copilot' PDF Service..."

# Ensure the PDF Services directory exists
mkdir -p "$PDF_SERVICES_DIR"

# Remove old versions (workflow or app)
for old in "$PDF_SERVICES_DIR/$SERVICE_NAME.workflow" "$APP_PATH"; do
  if [[ -e "$old" ]]; then
    echo "   Removing existing: $(basename "$old")"
    rm -rf "$old"
  fi
done

# Create an AppleScript application that receives PDF files from the
# Print dialog's PDF dropdown. macOS passes generated PDFs to .app
# bundles in ~/Library/PDF Services/ via the 'open' Apple Event handler.
cat > /tmp/copilot-printer-service.applescript << APPLESCRIPT
on open theFiles
	set inboxDir to (POSIX path of (path to home folder)) & "PrintToCopilot/"
	do shell script "mkdir -p " & quoted form of inboxDir

	set printerScript to "$COPILOT_PRINTER"
	set logFile to inboxDir & "debug.log"
	set pathPrefix to "export PATH=/opt/homebrew/bin:/usr/local/bin:\$PATH; "

	repeat with oneFile in theFiles
		set filePath to POSIX path of oneFile
		set fileName to do shell script "basename " & quoted form of filePath & " .pdf"
		do shell script pathPrefix & quoted form of printerScript & " " & quoted form of filePath & " " & quoted form of fileName & " >> " & quoted form of logFile & " 2>&1"
	end repeat

	display notification "Document ready for Copilot" with title "🖨️ Copilot Printer" subtitle "Saved to ~/PrintToCopilot/"
end open
APPLESCRIPT

osacompile -o "$APP_PATH" /tmp/copilot-printer-service.applescript
rm -f /tmp/copilot-printer-service.applescript

echo "   ✅ App installed: $APP_PATH"
echo ""
echo "   The option '${SERVICE_NAME}' will now appear in:"
echo "   File > Print > PDF dropdown (bottom-left of Print dialog)"
echo ""
echo "   Printed documents are saved to: ~/PrintToCopilot/"
echo ""
echo "   💡 Tip: If it doesn't appear immediately, log out and back in,"
echo "   or run: /System/Library/CoreServices/pbs -flush"
