#!/bin/bash

# ============================================================
#  pdf-contrast-enhancer.sh
#  Increases contrast and sharpness of every page in a PDF by
#  rendering pages to images, enhancing them with Pillow, and
#  reassembling into a PDF.
#  Dependencies: python3, python3-venv, poppler-utils
#  (installed automatically below if missing)
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")" &>/dev/null && pwd)"
source "$SCRIPT_DIR/common.sh"

# ── Dependency check ─────────────────────────────────────────
# Unlike require_bin (single binary, hard-fail), this tool needs multiple
# apt packages plus a Python venv, so it auto-installs what's missing
# instead of just printing instructions and exiting.

mapfile -t MISSING_APT < <(python_venv_apt_pkgs)
command -v pdftoppm >/dev/null 2>&1 || MISSING_APT+=(poppler-utils)

apt_install_missing "${MISSING_APT[@]}"

ok "system dependencies found"

echo ""

# ── Python virtual environment ───────────────────────────────
# Persistent venv at ~/.pdf-contrast-enhancer-venv; see ensure_venv in common.sh.

VENV_DIR="$HOME/.pdf-contrast-enhancer-venv"
VENV_PYTHON="$VENV_DIR/bin/python"

ensure_venv "$VENV_DIR" pdf2image pillow img2pdf

echo ""

# ── Input: PDF file ───────────────────────────────────────────
INPUT=$(prompt_input_file "Enter path to input PDF: ")
ok "Input: $INPUT"

# ── Input: Output file ────────────────────────────────────────

echo ""

DEFAULT_OUTPUT=$(default_output_name "$INPUT" contrast)

OUTPUT=$(prompt_output_path "$DEFAULT_OUTPUT")

# ── Run ───────────────────────────────────────────────────────
# The enhancement logic lives in tools/py/pdf-contrast-enhancer.py and runs
# through the venv's Python; it reports progress by printing
# "PROGRESS:i/total" lines that the bash loop below parses the same way
# pdf-compressor.sh parses Ghostscript's page-progress output.

init_logfile

echo ""
set +e

"$VENV_PYTHON" "$SCRIPT_DIR/py/pdf-contrast-enhancer.py" "$INPUT" "$OUTPUT" 2>"$LOGFILE" | while IFS= read -r line; do
    if [[ "$line" =~ ^PROGRESS:([0-9]+)/([0-9]+)$ ]]; then
        draw_progress "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}"
    fi
done

# PIPESTATUS[0] (not $?) because $? after a pipeline reflects the trailing
# `while` command, not the Python process on the left of the pipe.
PYTHON_EXIT="${PIPESTATUS[0]}"
set -e
echo ""

if [[ "$PYTHON_EXIT" -ne 0 ]]; then
    dump_log_and_die "Enhancement" "$LOGFILE"
fi

report_size_comparison "$INPUT" "$OUTPUT"
