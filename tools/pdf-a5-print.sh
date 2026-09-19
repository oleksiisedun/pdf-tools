#!/bin/bash

# ============================================================
#  pdf-a5-print.sh
#  Combines two A5 PDFs side by side on a single A4 landscape page.
#  Dependencies: pdfjam (texlive-extra-utils)
# ============================================================

set -eo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")" &>/dev/null && pwd)"
source "$SCRIPT_DIR/common.sh"

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
# pdfjam's own pdflatex traps SIGINT (Ctrl-C) instead of dying from it, so a
# plain foreground `pdfjam ...` would hang around forever if interrupted --
# even the enclosing `if pdfjam; then` never returns, leaving pdflatex as an
# orphaned process. Running it under setsid gives pdfjam (and the pdflatex it
# spawns) their own process group, so on interrupt we can SIGTERM that whole
# group -- which pdflatex does honor -- instead of just its direct child.
LOGFILE=$(mktemp)
setsid pdfjam --nup 2x1 --landscape --paper a4paper \
    "$FILE1" "$FILE2" --outfile "$OUTPUT" &>"$LOGFILE" &
PDFJAM_PID=$!
trap 'kill -TERM -- -"$PDFJAM_PID" 2>/dev/null; rm -f "$LOGFILE"; exit 130' INT TERM

if wait "$PDFJAM_PID"; then
    trap - INT TERM
    ok "Done! Output saved to: $(realpath "$OUTPUT")"
    rm -f "$LOGFILE"
else
    trap - INT TERM
    dump_log_and_die "pdfjam" "$LOGFILE"
fi
