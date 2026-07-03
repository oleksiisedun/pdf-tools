#!/bin/bash

# ============================================================
#  pdf-contrast-enhancer.sh
#  Increases contrast and sharpness of every page in a PDF by
#  rendering pages to images, enhancing them with Pillow, and
#  reassembling into a PDF.
#  Dependencies: python3, python3-venv, poppler-utils
#  (installed automatically below if missing)
# ============================================================

set -eo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")" &>/dev/null && pwd)"
source "$SCRIPT_DIR/common.sh"

# ── Dependency check ─────────────────────────────────────────
# Unlike require_bin (single binary, hard-fail), this tool needs multiple
# apt packages plus a Python venv, so it auto-installs what's missing
# instead of just printing instructions and exiting.

MISSING_APT=()
command -v python3        >/dev/null 2>&1 || MISSING_APT+=(python3)
python3 -c "import venv"  2>/dev/null     || MISSING_APT+=(python3-venv)
command -v pdftoppm       >/dev/null 2>&1 || MISSING_APT+=(poppler-utils)

if [ ${#MISSING_APT[@]} -gt 0 ]; then
	warn "Installing missing packages: ${MISSING_APT[*]}"
	sudo apt-get install -y "${MISSING_APT[@]}"
fi

ok "system dependencies found"

echo ""

# ── Python virtual environment ───────────────────────────────
# Persisted outside the repo (~/.pdf-contrast-enhancer-venv) so it survives
# across runs and clones; only created once, but pip install still runs
# every time to pick up dependency updates (it's a no-op when already current).

VENV_DIR="$HOME/.pdf-contrast-enhancer-venv"
VENV_PIP="$VENV_DIR/bin/pip"
VENV_PYTHON="$VENV_DIR/bin/python"

if [ ! -d "$VENV_DIR" ]; then
	python3 -m venv "$VENV_DIR"
fi

"$VENV_PIP" install --quiet --upgrade pip
"$VENV_PIP" install --quiet pdf2image pillow img2pdf

ok "Python environment ready"

echo ""

# ── Input: PDF file ───────────────────────────────────────────
INPUT=$(prompt_input_file "Enter path to input PDF: ")
ok "Input: $INPUT"

# ── Input: Output file ────────────────────────────────────────

echo ""

INPUT_BASENAME=$(basename "$INPUT" .pdf)
DEFAULT_OUTPUT="${INPUT_BASENAME}_contrast.pdf"

OUTPUT=$(prompt_output_path "$DEFAULT_OUTPUT")

# ── Run ───────────────────────────────────────────────────────
# The enhancement logic is embedded as a heredoc rather than a separate
# .py file so the tool stays a single self-contained script. It's written
# to a tempfile and run through the venv's Python; it reports progress by
# printing "PROGRESS:i/total" lines that the bash loop below parses the
# same way pdf-compressor.sh parses Ghostscript's page-progress output.

LOGFILE=$(mktemp)
PYFILE=$(mktemp --suffix=.py)

cat > "$PYFILE" << 'PYEOF'
import sys
from pdf2image import convert_from_path
from PIL import ImageEnhance
import img2pdf
import tempfile, os

input_pdf  = sys.argv[1]
output_pdf = sys.argv[2]

images = convert_from_path(input_pdf, dpi=300)
total = len(images)
print(f"PROGRESS:0/{total}", flush=True)

with tempfile.TemporaryDirectory() as tmpdir:
    enhanced_paths = []
    for i, img in enumerate(images):
        img = ImageEnhance.Contrast(img).enhance(2.5)
        img = ImageEnhance.Sharpness(img).enhance(1.5)
        path = os.path.join(tmpdir, f"page_{i}.jpg")
        img.save(path, "JPEG", quality=85)
        enhanced_paths.append(path)
        print(f"PROGRESS:{i + 1}/{total}", flush=True)

    with open(output_pdf, "wb") as f:
        f.write(img2pdf.convert(enhanced_paths))
PYEOF

echo ""
set +e

"$VENV_PYTHON" "$PYFILE" "$INPUT" "$OUTPUT" 2>"$LOGFILE" | while IFS= read -r line; do
	if [[ "$line" =~ ^PROGRESS:([0-9]+)/([0-9]+)$ ]]; then
		draw_progress "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}"
	fi
done

# PIPESTATUS[0] (not $?) because $? after a pipeline reflects the trailing
# `while` command, not the Python process on the left of the pipe.
PYTHON_EXIT="${PIPESTATUS[0]}"
rm -f "$PYFILE"
set -e
echo ""

if [[ "$PYTHON_EXIT" -ne 0 ]]; then
	dump_log_and_die "Enhancement" "$LOGFILE"
fi

report_size_comparison "$INPUT" "$OUTPUT"

rm -f "$LOGFILE"
