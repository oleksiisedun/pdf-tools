#!/bin/bash

# ============================================================
#  pdf-signer.sh
#  Stamps a signature image next to a signer's printed name in
#  a scanned PDF. OCRs each page (checked from the last page
#  backward) looking for the signer's name, then places the
#  signature image just to its left, vertically centered.
#  Also accepts a folder of PDFs for batch signing.
#  Dependencies: python3, python3-venv, tesseract-ocr,
#  tesseract-ocr-ukr (installed automatically below if missing)
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")" &>/dev/null && pwd)"
source "$SCRIPT_DIR/common.sh"

# ── Dependency check + Python virtual environment ───────────
# OCR packages plus the signer's persistent venv (SIGNER_VENV_DIR); see
# ensure_ocr_env in common.sh.

ensure_ocr_env
VENV_PYTHON="$SIGNER_VENV_DIR/bin/python"

echo ""

# ── Input: signature image ────────────────────────────────────
SIGNATURE=$(prompt_input_file "Enter path to signature image (PNG, ideally transparent background): ")
ok "Signature: $SIGNATURE"

echo ""

# ── Input: signer name ────────────────────────────────────────
SIGNER_NAME=""
while [[ -z "$SIGNER_NAME" ]]; do
    read -rp 'Enter signer'"'"'s full name (e.g. "Олексій Седун"): ' SIGNER_NAME
    [[ -z "$SIGNER_NAME" ]] && err "Signer name cannot be empty."
done

echo ""

# ── Input: PDF file or folder ─────────────────────────────────
# Unlike prompt_input_file (file-only), this tool also accepts a folder of
# PDFs for batch signing, so the existence check is inline here rather
# than in common.sh.
prompt_input_path() {
    local prompt="$1" result
    while true; do
        read -rp "$prompt" result
        result=$(clean_path "$result")
        if [[ -f "$result" || -d "$result" ]]; then
            echo "$result"
            return 0
        else
            err "Not found: $result"
        fi
    done
}

INPUT=$(prompt_input_path "Enter path to input PDF or folder of PDFs: ")
ok "Input: $INPUT"

echo ""

# ── Input: Output file or folder ──────────────────────────────
# Batch mode (INPUT is a folder) needs an output folder rather than a
# single PDF, so prompt_output_path's extension enforcement doesn't fit --
# the target folder is created by the Python side (os.makedirs) instead.

if [[ -d "$INPUT" ]]; then
    DEFAULT_OUTPUT="${INPUT%/}_signed"
    read -rp "Enter output folder [$DEFAULT_OUTPUT]: " OUTPUT
    OUTPUT="${OUTPUT/#\~/$HOME}"
    OUTPUT="${OUTPUT:-$DEFAULT_OUTPUT}"
else
    DEFAULT_OUTPUT=$(default_output_name "$INPUT" signed)
    OUTPUT=$(prompt_output_path "$DEFAULT_OUTPUT")
fi

echo ""

# ── Option: placement tuning ──────────────────────────────────
# These are the only place the defaults live: the Python side requires all three.
DEFAULT_GAP=10
DEFAULT_HEIGHT=48
DEFAULT_SHIFT=0
SIGNED_NUMBER_RE='^-?[0-9]+(\.[0-9]+)?$'

GAP=$(prompt_number "Gap between signature and name, in points (default: $DEFAULT_GAP): " "$DEFAULT_GAP" "$SIGNED_NUMBER_RE")
HEIGHT=$(prompt_number "Signature height, in points (default: $DEFAULT_HEIGHT): " "$DEFAULT_HEIGHT" '^[0-9]+(\.[0-9]+)?$')
SHIFT=$(prompt_number "Extra horizontal shift, in points, positive = further right (default: $DEFAULT_SHIFT): " "$DEFAULT_SHIFT" "$SIGNED_NUMBER_RE")

# ── Run ───────────────────────────────────────────────────────
# The signing logic lives in tools/py/pdf-signer.py and runs through the
# venv's Python. Unlike the compressor/contrast-enhancer, there's no
# meaningful total-page count to drive a progress bar (pages are searched
# last-to-first until the name is found), so the Python side's own status
# lines print straight through instead.

init_logfile

echo ""
set +e

"$VENV_PYTHON" "$SCRIPT_DIR/py/pdf-signer.py" "$SIGNATURE" "$SIGNER_NAME" \
    --input "$INPUT" --output "$OUTPUT" \
    --gap "$GAP" --height "$HEIGHT" --shift "$SHIFT" \
    2>"$LOGFILE"

PYTHON_EXIT=$?
set -e
echo ""

if [[ "$PYTHON_EXIT" -ne 0 ]]; then
    dump_log_and_die "Signing" "$LOGFILE"
fi

report_size_comparison "$INPUT" "$OUTPUT"
