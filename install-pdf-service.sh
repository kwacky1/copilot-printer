#!/bin/bash
# install-pdf-service.sh — Creates the "Print to Copilot" Automator PDF Service
# This installs a Print Plugin that appears in every app's Print > PDF dropdown.
#
# Usage: ./install-pdf-service.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
COPILOT_PRINTER="$SCRIPT_DIR/copilot-printer.sh"
SERVICE_NAME="Print to Copilot 🤖"
PDF_SERVICES_DIR="$HOME/Library/PDF Services"
WORKFLOW_DIR="$PDF_SERVICES_DIR/$SERVICE_NAME.workflow"

echo "🖨️  Installing 'Print to Copilot' PDF Service..."

# Ensure the PDF Services directory exists
mkdir -p "$PDF_SERVICES_DIR"

# Remove old version if present
if [[ -d "$WORKFLOW_DIR" ]]; then
  echo "   Removing existing workflow..."
  rm -rf "$WORKFLOW_DIR"
fi

# Create the Automator workflow bundle structure
mkdir -p "$WORKFLOW_DIR/Contents"

# Info.plist — tells macOS this is a Print Plugin workflow
cat > "$WORKFLOW_DIR/Contents/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>NSServices</key>
	<array>
		<dict>
			<key>NSMenuItem</key>
			<dict>
				<key>default</key>
				<string>Print to Copilot 🤖</string>
			</dict>
			<key>NSMessage</key>
			<string>runWorkflowAsService</string>
			<key>NSSendTypes</key>
			<array>
				<string>NSPDFPboardType</string>
				<string>com.adobe.pdf</string>
			</array>
		</dict>
	</array>
</dict>
</plist>
PLIST

# document.wflow — the Automator workflow definition
# This runs a shell script that receives the PDF from the Print dialog
cat > "$WORKFLOW_DIR/Contents/document.wflow" << WFLOW
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>AMApplicationBuild</key>
	<string>523</string>
	<key>AMApplicationVersion</key>
	<string>2.10</string>
	<key>AMDocumentVersion</key>
	<string>2</string>
	<key>actions</key>
	<array>
		<dict>
			<key>action</key>
			<dict>
				<key>AMAccepts</key>
				<dict>
					<key>Container</key>
					<string>List</string>
					<key>Optional</key>
					<true/>
					<key>Types</key>
					<array>
						<string>com.apple.cocoa.path</string>
					</array>
				</dict>
				<key>AMActionVersion</key>
				<string>2.0.3</string>
				<key>AMApplication</key>
				<array>
					<string>Automator</string>
				</array>
				<key>AMCategory</key>
				<string>AMCategoryUtilities</string>
				<key>AMIconName</key>
				<string>Run Shell Script</string>
				<key>AMKeywords</key>
				<array>
					<string>Shell</string>
					<string>Script</string>
					<string>Command</string>
					<string>Run</string>
				</array>
				<key>AMName</key>
				<string>Run Shell Script</string>
				<key>AMProvides</key>
				<dict>
					<key>Container</key>
					<string>List</string>
					<key>Types</key>
					<array>
						<string>com.apple.cocoa.path</string>
					</array>
				</dict>
				<key>ActionBundlePath</key>
				<string>/System/Library/Automator/Run Shell Script.action</string>
				<key>ActionName</key>
				<string>Run Shell Script</string>
				<key>BundleIdentifier</key>
				<string>com.apple.RunShellScript</string>
				<key>CFBundleVersion</key>
				<string>2.0.3</string>
				<key>CanShowSelectedItemsWhenRun</key>
				<false/>
				<key>CanShowWhenRun</key>
				<true/>
				<key>Category</key>
				<array>
					<string>AMCategoryUtilities</string>
				</array>
				<key>Class Name</key>
				<string>RunShellScriptAction</string>
				<key>InputUUID</key>
				<string>A1B2C3D4-E5F6-7890-ABCD-EF1234567890</string>
				<key>Keywords</key>
				<array>
					<string>Shell</string>
					<string>Script</string>
					<string>Command</string>
					<string>Run</string>
				</array>
				<key>OutputUUID</key>
				<string>B2C3D4E5-F6A7-8901-BCDE-F12345678901</string>
				<key>UUID</key>
				<string>C3D4E5F6-A7B8-9012-CDEF-123456789012</string>
			</dict>
			<key>class</key>
			<string>AMBundleAction</string>
			<key>isViewVisible</key>
			<true/>
			<key>location</key>
			<string>569.500000:620.000000</string>
			<key>nibPath</key>
			<string>/System/Library/Automator/Run Shell Script.action/Contents/Resources/Base.lproj/main.nib</string>
			<key>parameters</key>
			<dict>
				<key>COMMAND_STRING</key>
				<string>#!/bin/bash
# Print to Copilot — receives PDF file paths from the Print dialog
export PATH="/opt/homebrew/bin:/usr/local/bin:\$PATH"
LOG="\$HOME/PrintToCopilot/debug.log"
mkdir -p "\$HOME/PrintToCopilot"
echo "\$(date): Print to Copilot triggered with \$# args: \$@" >> "\$LOG"
for f in "\$@"; do
  echo "\$(date): Processing: \$f" >> "\$LOG"
  "$COPILOT_PRINTER" "\$f" "\$(basename "\$f" .pdf)" >> "\$LOG" 2>&amp;1
done
</string>
				<key>CheckedForUserDefaultShell</key>
				<true/>
				<key>inputMethod</key>
				<integer>1</integer>
				<key>shell</key>
				<string>/bin/bash</string>
				<key>source</key>
				<string></string>
			</dict>
		</dict>
	</array>
	<key>connectors</key>
	<dict/>
	<key>workflowMetaData</key>
	<dict>
		<key>workflowTypeIdentifier</key>
		<string>com.apple.Automator.printPlugin</string>
	</dict>
</dict>
</plist>
WFLOW

echo "   ✅ Workflow installed: $WORKFLOW_DIR"
echo ""
echo "   The option '${SERVICE_NAME}' will now appear in:"
echo "   File > Print > PDF dropdown (bottom-left of Print dialog)"
echo ""
echo "   Printed documents are saved to: ~/PrintToCopilot/"
echo ""
echo "   💡 Tip: If it doesn't appear immediately, log out and back in,"
echo "   or run: /System/Library/CoreServices/pbs -flush"
