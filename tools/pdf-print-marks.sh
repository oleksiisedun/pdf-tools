#!/bin/bash

# ============================================================
#  pdf-print-marks.sh
#  Adds a small random punctuation mark (. , ; ") after some
#  ALL-CAPS surnames in a scanned PDF. Each mark is a PDF
#  annotation with the Print and NoView flags: invisible on
#  screen, present only on paper. The scan itself is untouched.
#  Optionally also embeds pdf-print-marks-hidden-message.txt as an annotation
#  that is neither shown nor printed.
#  Dependencies: python3, python3-venv, tesseract-ocr,
#  tesseract-ocr-ukr (installed automatically below if missing)
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")" &>/dev/null && pwd)"
source "$SCRIPT_DIR/common.sh"

# ── Dependency check ─────────────────────────────────────────
# Same needs as pdf-signer.sh (OCR + the shared venv).

mapfile -t MISSING_APT < <(python_venv_apt_pkgs)
mapfile -t -O "${#MISSING_APT[@]}" MISSING_APT < <(ocr_apt_pkgs)

apt_install_missing "${MISSING_APT[@]}"

ok "system dependencies found"

echo ""

# ── Python virtual environment ───────────────────────────────
# Shares the signer's venv (same packages); see ensure_venv in common.sh.

VENV_PYTHON="$SIGNER_VENV_DIR/bin/python"

ensure_venv "$SIGNER_VENV_DIR" "${SIGNER_PACKAGES[@]}"

echo ""

# ── Input / output ────────────────────────────────────────────
INPUT=$(prompt_input_file "Enter path to input PDF (scanned): ")
ok "Input: $INPUT"

echo ""

DEFAULT_OUTPUT=$(default_output_name "$INPUT" marked)
OUTPUT=$(prompt_output_path "$DEFAULT_OUTPUT")

echo ""

# ── Option: intensity ─────────────────────────────────────────
# The only place the default lives: the Python side requires the flag.
DEFAULT_INTENSITY=5

INTENSITY=$(prompt_number "Intensity 1-10: 1 marks one surname, 10 marks all (default: $DEFAULT_INTENSITY): " "$DEFAULT_INTENSITY" '^([1-9]|10)$' "Enter a whole number from 1 to 10.")

# ── Option: hidden message ────────────────────────────────────
MESSAGE_ARGS=()
read -rp "Embed the hidden message from pdf-print-marks-hidden-message.txt? [y/N]: " EMBED_MESSAGE
if [[ "$EMBED_MESSAGE" =~ ^[Yy]$ ]]; then
    if [[ ! -s "$HIDDEN_MESSAGE_FILE" ]]; then
        err "$HIDDEN_MESSAGE_FILE is missing or empty."
        exit 1
    fi
    MESSAGE_ARGS=(--message-file "$HIDDEN_MESSAGE_FILE")
fi

# ── Run ───────────────────────────────────────────────────────
init_logfile

echo ""
set +e

"$VENV_PYTHON" "$SCRIPT_DIR/py/pdf-print-marks.py" \
    --input "$INPUT" --output "$OUTPUT" --intensity "$INTENSITY" \
    "${MESSAGE_ARGS[@]}" \
    2>"$LOGFILE"

PYTHON_EXIT=$?
set -e
echo ""

if [[ "$PYTHON_EXIT" -ne 0 ]]; then
    dump_log_and_die "Adding marks" "$LOGFILE"
fi

report_size_comparison "$INPUT" "$OUTPUT"
