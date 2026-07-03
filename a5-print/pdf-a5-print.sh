#!/bin/bash

# ============================================================
#  pdf-a5-print.sh
#  Combines two A5 PDFs side by side on a single A4 landscape page.
#  Dependencies: pdfjam (texlive-extra-utils)
# ============================================================

set -eo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")" &>/dev/null && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

# ── Dependency check ─────────────────────────────────────────
require_bin pdfjam texlive-extra-utils pdfjam

echo ""

# ── Input: File 1 ─────────────────────────────────────────────
FILE1=$(prompt_input_file "Enter path to first A5 PDF:  ")
ok "File 1: $FILE1"

# ── Input: File 2 ─────────────────────────────────────────────
FILE2=$(prompt_input_file "Enter path to second A5 PDF (or press Enter to reuse first): " "$FILE1")
if [[ "$FILE2" == "$FILE1" ]]; then
    warn "No second file provided — using first file twice"
else
    ok "File 2: $FILE2"
fi

# ── Input: Output file ────────────────────────────────────────
OUTPUT=$(prompt_output_path "output_A4_landscape.pdf")

# ── Run ───────────────────────────────────────────────────────
LOGFILE=$(mktemp)
if pdfjam --nup 2x1 --landscape --paper a4paper \
    "$FILE1" "$FILE2" --outfile "$OUTPUT" &>"$LOGFILE"; then
    ok "Done! Output saved to: $(realpath "$OUTPUT")"
else
    err "pdfjam failed. Full log:"
    echo ""
    cat "$LOGFILE"
fi
rm -f "$LOGFILE"
