#!/bin/bash
# install.sh — One-command installer for Copilot Printer
#
# Installs:
#   1. Text extraction dependencies (poppler, pandoc)
#   2. The Automator PDF Service (Print to Copilot in every Print dialog)
#   3. The MCP server (registers with Copilot CLI)
#   4. The PrintToCopilot inbox directory

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
COPILOT_INBOX="$HOME/PrintToCopilot"

echo ""
echo "  🖨️  Copilot Printer Installer"
echo "  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# --- Step 1: Dependencies ---
echo "📦 Step 1: Checking dependencies..."

install_brew_pkg() {
  local pkg="$1"
  local check_cmd="${2:-$1}"
  if command -v "$check_cmd" &>/dev/null; then
    echo "   ✅ $pkg already installed"
  else
    if command -v brew &>/dev/null; then
      echo "   📥 Installing $pkg via Homebrew..."
      brew install "$pkg" --quiet
      echo "   ✅ $pkg installed"
    else
      echo "   ⚠️  $pkg not found and Homebrew not available."
      echo "      Install manually: brew install $pkg"
    fi
  fi
}

install_brew_pkg "poppler" "pdftotext"
install_brew_pkg "pandoc" "pandoc"

# --- Step 2: Create inbox directory ---
echo ""
echo "📂 Step 2: Creating PrintToCopilot inbox..."
mkdir -p "$COPILOT_INBOX"
echo "   ✅ $COPILOT_INBOX"

# --- Step 3: Install PDF Service ---
echo ""
echo "🖨️  Step 3: Installing PDF Service..."
bash "$SCRIPT_DIR/install-pdf-service.sh"

# --- Step 4: Install MCP Server ---
echo ""
echo "🔌 Step 4: Setting up MCP server..."

MCP_SERVER_DIR="$SCRIPT_DIR/mcp-server"
if [[ ! -d "$MCP_SERVER_DIR/node_modules" ]]; then
  echo "   📥 Installing Node.js dependencies..."
  cd "$MCP_SERVER_DIR" && npm install --quiet
fi

# Register with Copilot CLI
MCP_CONFIG="$HOME/.copilot/mcp-config.json"
MCP_INDEX_PATH="$MCP_SERVER_DIR/src/index.js"
NODE_PATH=$(which node)

if [[ -f "$MCP_CONFIG" ]]; then
  # Check if already registered
  if grep -q "copilot-printer" "$MCP_CONFIG" 2>/dev/null; then
    echo "   ✅ MCP server already registered in Copilot CLI"
  else
    echo "   📝 Adding copilot-printer to MCP config..."
    # Use node to safely merge into existing JSON
    node -e "
      const fs = require('fs');
      const config = JSON.parse(fs.readFileSync('$MCP_CONFIG', 'utf-8'));
      if (!config.mcpServers) config.mcpServers = {};
      config.mcpServers['copilot-printer'] = {
        type: 'stdio',
        command: '$NODE_PATH',
        args: ['$MCP_INDEX_PATH']
      };
      fs.writeFileSync('$MCP_CONFIG', JSON.stringify(config, null, 2));
    "
    echo "   ✅ MCP server registered"
  fi
else
  echo "   📝 Creating MCP config with copilot-printer..."
  mkdir -p "$(dirname "$MCP_CONFIG")"
  cat > "$MCP_CONFIG" << EOF
{
  "mcpServers": {
    "copilot-printer": {
      "type": "stdio",
      "command": "$NODE_PATH",
      "args": ["$MCP_INDEX_PATH"]
    }
  }
}
EOF
  echo "   ✅ MCP config created at $MCP_CONFIG"
fi

# --- Done ---
echo ""
echo "  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  ✅ Copilot Printer installed successfully!"
echo "  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "  🖨️  PRINT TO COPILOT:"
echo "     Open any app → File → Print → PDF dropdown → 'Print to Copilot 🤖'"
echo ""
echo "  🤖 USE IN COPILOT CLI:"
echo "     copilot -i \"What's in my print inbox?\""
echo "     (Copilot will use list_print_jobs and read_print_job tools)"
echo ""
echo "  📂 INBOX LOCATION:"
echo "     $COPILOT_INBOX"
echo ""
echo "  💡 If the PDF Service doesn't appear in the Print dialog,"
echo "     log out and back in, or run:"
echo "     /System/Library/CoreServices/pbs -flush"
echo ""
