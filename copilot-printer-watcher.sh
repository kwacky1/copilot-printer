#!/bin/bash
# copilot-printer-watcher.sh
# Triggered by launchd (WatchPaths + StartInterval) when the PDFWriter spool changes.
# Imports any new PDFs from spool → ~/PrintToCopilot/ and converts to markdown.
#
# Installed by: install-launchd-watcher.sh
# Log: ~/Library/Logs/copilot-printer-watcher.log

export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"

SPOOL="/private/var/spool/pdfwriter/$(whoami)"
INBOX="$HOME/PrintToCopilot"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PRINTER_SCRIPT="$SCRIPT_DIR/copilot-printer.sh"
LOCK_FILE="/tmp/copilot-printer-watcher.lock"

# Prevent overlapping runs (launchd can trigger before a previous run finishes)
if [[ -f "$LOCK_FILE" ]]; then
  echo "[watcher] Already running (lock file exists), skipping" >&2
  exit 0
fi
touch "$LOCK_FILE"
trap 'rm -f "$LOCK_FILE"' EXIT

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] [watcher] $*"
}

mkdir -p "$INBOX"

if [[ ! -d "$SPOOL" ]]; then
  log "Spool directory not found: $SPOOL — nothing to do"
  exit 0
fi

imported=0
while IFS= read -r -d '' pdf_path; do
  pdf_name=$(basename "$pdf_path")

  # Skip the macOS icon resource file
  [[ "$pdf_name" == "Icon"* ]] && continue

  dest="$INBOX/$pdf_name"
  md_dest="${dest%.pdf}.md"
  meta_dest="${dest%.pdf}.meta.json"

  if [[ -f "$dest" ]] && [[ -f "$md_dest" ]]; then
    continue  # Already imported and converted
  fi

  log "Importing: $pdf_name"

  # Copy PDF to inbox with the original spool filename (preserves filename for doctor checks)
  cp "$pdf_path" "$dest"

  # Convert to markdown
  if command -v pdftotext &>/dev/null; then
    pdftotext -layout "$dest" "$md_dest" 2>/dev/null && converter="pdftotext" || converter="strings"
  fi
  if [[ "${converter:-}" != "pdftotext" ]]; then
    /usr/bin/strings "$dest" > "$md_dest" 2>/dev/null && converter="strings" || converter="error"
  fi

  # Write metadata sidecar
  TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  printf '{"timestamp":"%s","title":"%s","converter":"%s","source":"copilot-printer-watcher"}\n' \
    "$TS" "${pdf_name%.pdf}" "$converter" > "$meta_dest"

  log "✅ Imported and converted: $pdf_name (converter: $converter)"
  imported=$((imported + 1))

  # macOS notification
  osascript -e "display notification \"${pdf_name%.pdf}\" with title \"🖨️ Copilot Printer\" subtitle \"Auto-imported from PDFWriter\"" 2>/dev/null &
done < <(find "$SPOOL" -maxdepth 1 -name "*.pdf" -print0 2>/dev/null)

if [[ $imported -gt 0 ]]; then
  log "Imported $imported new PDF(s)"
else
  log "No new PDFs to import"
fi
