# Shared setup for the e2e bats files. Loaded with `load helpers`.
# Fixtures are generated per test into BATS_TEST_TMPDIR by make_fixtures.py,
# using the signer's venv (PyMuPDF + Pillow).

ROOT="$(cd -- "${BATS_TEST_DIRNAME}/../.." &>/dev/null && pwd)"
# shellcheck source=../../tools/common.sh
source "$ROOT/tools/common.sh"
VENV_PYTHON="$SIGNER_VENV_DIR/bin/python"

# require_cmd <binary>: skips the current test when a system tool is missing.
require_cmd() {
    command -v "$1" >/dev/null 2>&1 || skip "$1 not installed"
}

# require_signer_venv: skips unless the signer venv exists (run ./test.sh or
# the signer once to create it).
require_signer_venv() {
    [[ -x "$VENV_PYTHON" ]] || skip "signer venv missing ($SIGNER_VENV_DIR)"
}

# make_fixture <noisy|scan|signature|slides> <output>
make_fixture() {
    "$VENV_PYTHON" "$ROOT/tests/e2e/make_fixtures.py" "$1" "$2"
}

# file_size <path>: size in bytes.
file_size() {
    stat -c %s "$1"
}

# pdf_image_count <pdf>: total images across all pages.
pdf_image_count() {
    "$VENV_PYTHON" -c '
import sys, pymupdf
with pymupdf.open(sys.argv[1]) as doc:
    print(sum(len(page.get_images()) for page in doc))
' "$1"
}

# pdf_annot_summary <pdf>: one "<type> <flags>" line per annotation.
pdf_annot_summary() {
    "$VENV_PYTHON" -c '
import sys, pymupdf
with pymupdf.open(sys.argv[1]) as doc:
    for page in doc:
        for annot in page.annots():
            print(annot.type[1], annot.flags)
' "$1"
}

# video_info <video>: "<codec> <pix_fmt> <width>x<height> <duration-seconds>"
# of the first video stream, with the duration rounded to a whole second.
video_info() {
    # ffprobe prints fields in its own order (codec, width, height, pix_fmt),
    # whatever order -show_entries lists them in.
    local codec pix_fmt width height duration
    IFS=, read -r codec width height pix_fmt < <(
        ffprobe -v error -select_streams v:0 \
            -show_entries stream=codec_name,pix_fmt,width,height -of csv=p=0 "$1"
    )
    # awk, not printf %.0f: bash's printf follows the locale's decimal separator.
    duration=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$1" |
        awk '{ printf "%d", $1 + 0.5 }')
    echo "$codec $pix_fmt ${width}x${height} $duration"
}
