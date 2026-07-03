#!/bin/bash

# ============================================================
#  pdf-compressor.sh
#  Compresses a PDF with Ghostscript, picking one of three
#  quality/DPI presets.
#  Dependencies: ghostscript (gs)
# ============================================================

set -eo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")" &>/dev/null && pwd)"
source "$SCRIPT_DIR/common.sh"

# ── Dependency check ─────────────────────────────────────────
require_bin gs ghostscript ghostscript

echo ""

# ── Input: PDF file ───────────────────────────────────────────
INPUT=$(prompt_input_file "Enter path to input PDF: ")
ok "Input: $INPUT"

# ── Select compression quality ────────────────────────────────

echo ""
echo "Select compression level:"
echo "  1) screen   —  72 dpi  (smallest file)"
echo "  2) ebook    — 150 dpi  (moderate quality)"
echo "  3) prepress — 300 dpi  (highest quality)"
echo ""

while true; do
	read -rp "Choice [1/2/3] (default: 2): " CHOICE
	CHOICE="${CHOICE:-2}"
	case "$CHOICE" in
		1) PDFSETTINGS="/screen"   ; QUALITY_LABEL="screen (72 dpi)"    ; break ;;
		2) PDFSETTINGS="/ebook"    ; QUALITY_LABEL="ebook (150 dpi)"    ; break ;;
		3) PDFSETTINGS="/prepress" ; QUALITY_LABEL="prepress (300 dpi)" ; break ;;
		*) err "Invalid choice. Enter 1, 2, or 3." ;;
	esac
done

ok "Quality: $QUALITY_LABEL"
echo ""

# ── Input: Output file ────────────────────────────────────────

INPUT_BASENAME=$(basename "$INPUT" .pdf)
DEFAULT_OUTPUT="${INPUT_BASENAME}_compressed.pdf"

OUTPUT=$(prompt_output_path "$DEFAULT_OUTPUT")

# ── Run ───────────────────────────────────────────────────────

LOGFILE=$(mktemp)

echo ""
set +e

# gs writes its "Processing pages..."/"Page N" progress lines to stderr, so
# they're redirected into LOGFILE (used for the failure dump below) and also
# piped to a parser loop that pulls the total page count once, then feeds
# each page number to draw_progress. GS_EXIT is read from PIPESTATUS[0]
# because $? after a pipeline only reflects the trailing `while` command.
gs -sDEVICE=pdfwrite \
   -dCompatibilityLevel=1.4 \
   -dPDFSETTINGS="$PDFSETTINGS" \
   -dNOPAUSE -dBATCH \
   -sOutputFile="$OUTPUT" \
   "$INPUT" 2>"$LOGFILE" | while IFS= read -r line; do
	if [[ "$line" =~ Processing\ pages\ 1\ through\ ([0-9]+) ]]; then
		TOTAL="${BASH_REMATCH[1]}"
	elif [[ "$line" =~ ^Page[[:space:]]+([0-9]+)$ ]] && [[ "${TOTAL:-0}" -gt 0 ]]; then
		draw_progress "${BASH_REMATCH[1]}" "$TOTAL"
	fi
done

GS_EXIT="${PIPESTATUS[0]}"
set -e
echo ""

if [[ "$GS_EXIT" -ne 0 ]]; then
	err "ghostscript failed. Full log:"
	echo ""
	cat "$LOGFILE"
	rm -f "$LOGFILE"
	exit 1
fi

INPUT_SIZE=$(du -sh "$INPUT" | cut -f1)
OUTPUT_SIZE=$(du -sh "$OUTPUT" | cut -f1)
ok "Done! Output saved to: $(realpath "$OUTPUT")"
echo ""
echo "  Input size:  $INPUT_SIZE"
echo "  Output size: $OUTPUT_SIZE"

rm -f "$LOGFILE"
