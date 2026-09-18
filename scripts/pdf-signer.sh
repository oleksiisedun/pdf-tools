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

set -eo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")" &>/dev/null && pwd)"
source "$SCRIPT_DIR/common.sh"

# ── Dependency check ─────────────────────────────────────────
# Same auto-install approach as pdf-contrast-enhancer.sh: multiple apt
# packages plus a Python venv, so missing pieces are installed instead of
# just printing instructions and exiting.

MISSING_APT=()
command -v python3       >/dev/null 2>&1              || MISSING_APT+=(python3)
python3 -c "import venv" 2>/dev/null                   || MISSING_APT+=(python3-venv)
command -v tesseract     >/dev/null 2>&1               || MISSING_APT+=(tesseract-ocr)
tesseract --list-langs 2>/dev/null | grep -qx ukr      || MISSING_APT+=(tesseract-ocr-ukr)

if [ ${#MISSING_APT[@]} -gt 0 ]; then
	warn "Installing missing packages: ${MISSING_APT[*]}"
	sudo apt-get install -y "${MISSING_APT[@]}"
fi

ok "system dependencies found"

echo ""

# ── Python virtual environment ───────────────────────────────
# Persisted outside the repo (~/.pdf-signer-venv) so it survives across
# runs and clones; only created once, but pip install still runs every
# time to pick up dependency updates (it's a no-op when already current).

VENV_DIR="$HOME/.pdf-signer-venv"
VENV_PIP="$VENV_DIR/bin/pip"
VENV_PYTHON="$VENV_DIR/bin/python"

if [ ! -d "$VENV_DIR" ]; then
	python3 -m venv "$VENV_DIR"
fi

"$VENV_PIP" install --quiet --upgrade pip
"$VENV_PIP" install --quiet pymupdf pytesseract pillow

ok "Python environment ready"

echo ""

# ── Input: signature image ────────────────────────────────────
SIGNATURE=$(prompt_input_file "Enter path to signature image (PNG, ideally transparent background): ")
ok "Signature: $SIGNATURE"

echo ""

# ── Input: signer name ────────────────────────────────────────
SIGNER_NAME=""
while [[ -z "$SIGNER_NAME" ]]; do
	read -rp 'Enter signer'"'"'s full name (e.g. "Сергій Сизов"): ' SIGNER_NAME
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
	INPUT_BASENAME=$(basename "$INPUT" .pdf)
	DEFAULT_OUTPUT="${INPUT_BASENAME}_signed.pdf"
	OUTPUT=$(prompt_output_path "$DEFAULT_OUTPUT")
fi

echo ""

# ── Option: placement tuning ──────────────────────────────────
GAP=$(prompt_number "Gap between signature and name, in points (default: 10): " 10 '^-?[0-9]+(\.[0-9]+)?$')
HEIGHT=$(prompt_number "Signature height, in points (default: 48): " 48 '^[0-9]+(\.[0-9]+)?$')
SHIFT=$(prompt_number "Extra horizontal shift, in points, positive = further right (default: 0): " 0 '^-?[0-9]+(\.[0-9]+)?$')

# ── Run ───────────────────────────────────────────────────────
# The signing logic is embedded as a heredoc rather than a separate .py
# file so the tool stays self-contained, same approach as
# pdf-contrast-enhancer.sh. It's written to a tempfile and run through the
# venv's Python. Unlike the compressor/contrast-enhancer, there's no
# meaningful total-page count to drive a progress bar (pages are searched
# last-to-first until the name is found), so the Python side's own status
# lines print straight through instead.

LOGFILE=$(mktemp)
PYFILE=$(mktemp --suffix=.py)

cat > "$PYFILE" << 'PYEOF'
import argparse
import glob
import os

import pymupdf as fitz
import pytesseract
from PIL import Image

OCR_DPI = 150
OCR_LANG = "ukr"


def _ocr_words(page, dpi=OCR_DPI):
    pix = page.get_pixmap(dpi=dpi)
    img = Image.frombytes("RGB", [pix.width, pix.height], pix.samples)
    return pytesseract.image_to_data(img, lang=OCR_LANG, output_type=pytesseract.Output.DICT)


def find_name_box(page, name_parts, dpi=OCR_DPI):
    """Return (x0, y0, x1, y1) in PDF points around the first place on this
    page where the words of `name_parts` appear next to each other (matched
    by prefix, so Ukrainian case endings like СИЗОВ / СИЗОВУ / СИЗОВА still
    match), or None if not found."""
    data = _ocr_words(page, dpi)
    scale = 72.0 / dpi
    lines = {}
    for i in range(len(data["text"])):
        w = data["text"][i].strip()
        if not w:
            continue
        key = (data["block_num"][i], data["par_num"][i], data["line_num"][i])
        lines.setdefault(key, []).append(
            (w, data["left"][i], data["top"][i], data["width"][i], data["height"][i])
        )

    k = len(name_parts)
    for words in lines.values():
        words = sorted(words, key=lambda w: w[1])
        for start in range(len(words) - k + 1):
            window = words[start:start + k]
            if all(
                window[j][0].upper().startswith(name_parts[j])
                or name_parts[j].startswith(window[j][0].upper())
                for j in range(k)
            ):
                xs = [w[1] for w in window] + [w[1] + w[3] for w in window]
                ys = [w[2] for w in window] + [w[2] + w[4] for w in window]
                return (min(xs) * scale, min(ys) * scale, max(xs) * scale, max(ys) * scale)
    return None


def locate_signer(doc, signer_name):
    """Search pages from last to first. Returns (page_index, name_box)."""
    name_parts = [p.upper() for p in signer_name.split() if p.strip()]
    if not name_parts:
        raise ValueError("Ім'я підписанта не вказано.")
    for page_index in range(len(doc) - 1, -1, -1):
        box = find_name_box(doc[page_index], name_parts)
        if box:
            return page_index, box
    return None, None


def stamp(input_pdf, signature_png, signer_name, output_pdf,
          gap=10.0, height=48.0, shift=0.0):
    doc = fitz.open(input_pdf)
    page_index, name_box = locate_signer(doc, signer_name)
    if page_index is None:
        doc.close()
        raise RuntimeError(f"Ім'я «{signer_name}» не знайдено на жодній сторінці.")

    nx0, ny0, nx1, ny1 = name_box
    sig_img = Image.open(signature_png)
    ratio = sig_img.width / sig_img.height
    sig_h = height
    sig_w = sig_h * ratio

    x1 = nx0 - gap + shift
    x0 = x1 - sig_w
    y_center = (ny0 + ny1) / 2
    y0 = y_center - sig_h / 2
    y1 = y_center + sig_h / 2

    page = doc[page_index]
    page.insert_image(fitz.Rect(x0, y0, x1, y1), filename=signature_png, keep_proportion=True)
    doc.save(output_pdf)
    doc.close()
    print(f"[{os.path.basename(input_pdf)}] сторінка {page_index + 1}: підпис проставлено -> {output_pdf}")


def batch(input_dir, signature_png, signer_name, output_dir, **kwargs):
    os.makedirs(output_dir, exist_ok=True)
    files = sorted(glob.glob(os.path.join(input_dir, "*.pdf")))
    if not files:
        print(f"У папці {input_dir} не знайдено .pdf файлів.")
        return
    for f in files:
        out = os.path.join(output_dir, os.path.basename(f))
        try:
            stamp(f, signature_png, signer_name, out, **kwargs)
        except Exception as e:
            print(f"[{os.path.basename(f)}] ПОМИЛКА: {e}")


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("signature_png")
    ap.add_argument("signer_name")
    ap.add_argument("--input", required=True)
    ap.add_argument("--output", required=True)
    ap.add_argument("--gap", type=float, default=10.0)
    ap.add_argument("--height", type=float, default=48.0)
    ap.add_argument("--shift", type=float, default=0.0)
    args = ap.parse_args()

    kwargs = dict(gap=args.gap, height=args.height, shift=args.shift)
    if os.path.isdir(args.input):
        batch(args.input, args.signature_png, args.signer_name, args.output, **kwargs)
    else:
        stamp(args.input, args.signature_png, args.signer_name, args.output, **kwargs)
PYEOF

echo ""
set +e

"$VENV_PYTHON" "$PYFILE" "$SIGNATURE" "$SIGNER_NAME" \
	--input "$INPUT" --output "$OUTPUT" \
	--gap "$GAP" --height "$HEIGHT" --shift "$SHIFT" \
	2>"$LOGFILE"

PYTHON_EXIT=$?
rm -f "$PYFILE"
set -e
echo ""

if [[ "$PYTHON_EXIT" -ne 0 ]]; then
	dump_log_and_die "Signing" "$LOGFILE"
fi

rm -f "$LOGFILE"

report_size_comparison "$INPUT" "$OUTPUT"
