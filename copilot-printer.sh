#!/bin/bash
# copilot-printer.sh — Core print-to-copilot conversion script
# Receives a PDF (or PostScript) file path, converts to markdown,
# and saves to the PrintToCopilot inbox directory.
#
# Usage:
#   ./copilot-printer.sh /path/to/input.pdf
#   ./copilot-printer.sh /path/to/input.pdf "Optional Job Title"
#   cat document.pdf | ./copilot-printer.sh - "Piped Document"

set -euo pipefail

COPILOT_INBOX="${COPILOT_PRINTER_DIR:-$HOME/PrintToCopilot}"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
NOTIFY=${COPILOT_PRINTER_NOTIFY:-true}

# --- Helpers ---

notify() {
  if [[ "$NOTIFY" == "true" ]] && command -v osascript &>/dev/null; then
    osascript -e "display notification \"$2\" with title \"🖨️ Copilot Printer\" subtitle \"$1\""
  fi
}

log() {
  echo "[copilot-printer] $*" >&2
}

detect_converter() {
  if command -v pdftotext &>/dev/null; then
    echo "pdftotext"
  elif command -v textutil &>/dev/null; then
    # macOS built-in — handles many formats
    echo "textutil"
  elif command -v python3 &>/dev/null; then
    echo "python3"
  else
    echo "none"
  fi
}

# --- PDF to Markdown conversion ---

convert_pdftotext() {
  local pdf_path="$1"
  local md_path="$2"
  local tmp_txt
  tmp_txt=$(mktemp /tmp/copilot-printer-XXXXXX.txt)

  pdftotext -layout "$pdf_path" "$tmp_txt"

  if command -v pandoc &>/dev/null; then
    # pandoc needs a file, not stdin, for plain text
    pandoc --from=plain --to=gfm --wrap=none "$tmp_txt" -o "$md_path" 2>/dev/null || cp "$tmp_txt" "$md_path"
  else
    cp "$tmp_txt" "$md_path"
  fi

  rm -f "$tmp_txt"
}

convert_textutil() {
  local pdf_path="$1"
  local md_path="$2"
  local tmp_txt
  tmp_txt=$(mktemp /tmp/copilot-printer-XXXXXX.txt)

  # textutil can convert PDF to plain text on macOS
  textutil -convert txt -output "$tmp_txt" "$pdf_path" 2>/dev/null || {
    # Fallback: use mdls + strings for basic text extraction
    strings "$pdf_path" > "$tmp_txt"
  }

  if command -v pandoc &>/dev/null; then
    pandoc -f plain -t gfm --wrap=none "$tmp_txt" > "$md_path"
  else
    # Add a markdown header with metadata
    {
      echo "# Printed Document"
      echo ""
      echo "_Captured: $(date '+%Y-%m-%d %H:%M:%S')_"
      echo ""
      echo "---"
      echo ""
      cat "$tmp_txt"
    } > "$md_path"
  fi

  rm -f "$tmp_txt"
}

convert_python3() {
  local pdf_path="$1"
  local md_path="$2"

  python3 -c "
import subprocess, sys, os

pdf = '$pdf_path'
try:
    # Try PyPDF2/pypdf if available
    from pypdf import PdfReader
    reader = PdfReader(pdf)
    text = '\\n\\n'.join(page.extract_text() or '' for page in reader.pages)
except ImportError:
    # Fallback to strings extraction
    result = subprocess.run(['strings', pdf], capture_output=True, text=True)
    text = result.stdout

print('# Printed Document')
print()
print(f'_Captured: $(date \"+%Y-%m-%d %H:%M:%S\")_')
print()
print('---')
print()
print(text)
" > "$md_path"
}

convert_none() {
  local pdf_path="$1"
  local md_path="$2"

  # Last resort: just save the raw PDF and note we couldn't convert
  {
    echo "# Printed Document (Unconverted)"
    echo ""
    echo "_Captured: $(date '+%Y-%m-%d %H:%M:%S')_"
    echo ""
    echo "> ⚠️ No text extraction tool found. Install \`poppler\` (\`brew install poppler\`) for best results."
    echo ""
    echo "**Original PDF saved alongside this file.**"
    echo ""
    echo "---"
    echo ""
    strings "$pdf_path" 2>/dev/null | head -200
  } > "$md_path"
}

# --- Main ---

main() {
  local input_path="${1:--}"
  local job_title="${2:-Untitled}"

  # Sanitise job title for filename
  local safe_title
  safe_title=$(echo "$job_title" | tr -cs '[:alnum:] ._-' '_' | head -c 80)
  [[ -z "$safe_title" ]] && safe_title="Untitled"

  # Create inbox directory
  mkdir -p "$COPILOT_INBOX"

  local pdf_path
  local md_path="$COPILOT_INBOX/${TIMESTAMP}-${safe_title}.md"

  # Handle stdin or file input
  if [[ "$input_path" == "-" ]]; then
    pdf_path=$(mktemp /tmp/copilot-printer-XXXXXX.pdf)
    cat > "$pdf_path"
    log "Received print job from stdin → $pdf_path"
  elif [[ -f "$input_path" ]]; then
    pdf_path="$input_path"
    log "Received print job: $pdf_path"
  else
    log "Error: Input file not found: $input_path"
    notify "Error" "Input file not found"
    exit 1
  fi

  # Also save the original PDF to the inbox
  local saved_pdf="$COPILOT_INBOX/${TIMESTAMP}-${safe_title}.pdf"
  cp "$pdf_path" "$saved_pdf"

  # Detect best available converter and run it
  local converter
  converter=$(detect_converter)
  log "Using converter: $converter"

  case "$converter" in
    pdftotext)  convert_pdftotext "$pdf_path" "$md_path" ;;
    textutil)   convert_textutil "$pdf_path" "$md_path" ;;
    python3)    convert_python3 "$pdf_path" "$md_path" ;;
    none)       convert_none "$pdf_path" "$md_path" ;;
  esac

  # Clean up temp file if we created one
  if [[ "$input_path" == "-" ]]; then
    rm -f "$pdf_path"
  fi

  # Write a metadata sidecar
  cat > "$COPILOT_INBOX/${TIMESTAMP}-${safe_title}.meta.json" <<EOF
{
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "title": "$job_title",
  "converter": "$converter",
  "markdown_file": "${TIMESTAMP}-${safe_title}.md",
  "pdf_file": "${TIMESTAMP}-${safe_title}.pdf",
  "source": "copilot-printer"
}
EOF

  log "✅ Saved: $md_path"
  notify "$job_title" "Document ready for Copilot"

  # Output the markdown path for callers
  echo "$md_path"
}

main "$@"
