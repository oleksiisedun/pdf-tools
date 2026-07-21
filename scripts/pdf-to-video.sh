#!/bin/bash

# ============================================================
#  pdf-to-video.sh
#  Converts a PDF presentation into an MP4 slideshow video,
#  showing each page for a fixed number of seconds. Output is
#  H.264/yuv420p in a 1920x1080 letterboxed frame for broad
#  TV/USB playback compatibility.
#  Dependencies: poppler-utils (pdftoppm, pdfinfo), ffmpeg
# ============================================================

set -eo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")" &>/dev/null && pwd)"
source "$SCRIPT_DIR/common.sh"

# ── Dependency check ─────────────────────────────────────────
require_bin pdftoppm poppler-utils poppler-utils
require_bin ffmpeg ffmpeg ffmpeg

echo ""

# ── Input: PDF file ───────────────────────────────────────────
INPUT=$(prompt_input_file "Enter path to input PDF: ")
ok "Input: $INPUT"

# ── Option: seconds per slide ─────────────────────────────────

echo ""
read -rp "Seconds per slide (default: 5): " SECONDS_PER_SLIDE
SECONDS_PER_SLIDE="${SECONDS_PER_SLIDE:-5}"
while [[ ! "$SECONDS_PER_SLIDE" =~ ^[1-9][0-9]*$ ]]; do
	err "Enter a whole number of seconds greater than 0."
	read -rp "Seconds per slide: " SECONDS_PER_SLIDE
done

ok "Duration: ${SECONDS_PER_SLIDE}s per slide"
echo ""

# ── Input: Output file ────────────────────────────────────────

INPUT_BASENAME=$(basename "$INPUT" .pdf)
DEFAULT_OUTPUT="${INPUT_BASENAME}_slideshow.mp4"

OUTPUT=$(prompt_output_path "$DEFAULT_OUTPUT" "mp4")

# ── Run ───────────────────────────────────────────────────────

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT
LOGFILE=$(mktemp)

echo ""

TOTAL_PAGES=$(pdfinfo "$INPUT" | awk '/^Pages:/{print $2}')

if ! pdftoppm -png -r 150 "$INPUT" "$TMPDIR/slide" 2>"$LOGFILE"; then
	dump_log_and_die "Slide rendering" "$LOGFILE"
fi

# Build an ffmpeg concat-demuxer list. sort -V handles pdftoppm's
# page-count-dependent zero-padding (slide-1.png vs slide-01.png) correctly.
mapfile -t SLIDE_IMAGES < <(find "$TMPDIR" -maxdepth 1 -name 'slide-*.png' | sort -V)

CONCAT_FILE="$TMPDIR/concat.txt"
: > "$CONCAT_FILE"
for img in "${SLIDE_IMAGES[@]}"; do
	printf "file '%s'\nduration %s\n" "$img" "$SECONDS_PER_SLIDE" >> "$CONCAT_FILE"
done

TOTAL_DURATION=$(( TOTAL_PAGES * SECONDS_PER_SLIDE ))

set +e

# ffmpeg's -progress pipe:1 emits "out_time_ms=<n>" lines to stdout as it
# encodes; the loop below parses those to drive draw_progress the same way
# pdf-compressor.sh parses Ghostscript's page-progress output. FFMPEG_EXIT
# is read from PIPESTATUS[0] since $? after a pipeline reflects the
# trailing `while` command, not ffmpeg itself.
ffmpeg -y -f concat -safe 0 -i "$CONCAT_FILE" \
	-vf "scale=1920:1080:force_original_aspect_ratio=decrease,pad=1920:1080:(ow-iw)/2:(oh-ih)/2,format=yuv420p" \
	-r 25 -c:v libx264 -pix_fmt yuv420p -movflags +faststart \
	-progress pipe:1 -nostats \
	"$OUTPUT" 2>"$LOGFILE" | while IFS= read -r line; do
	if [[ "$line" =~ ^out_time_ms=([0-9]+)$ ]]; then
		CURRENT_SEC=$(( BASH_REMATCH[1] / 1000000 ))
		(( CURRENT_SEC > TOTAL_DURATION )) && CURRENT_SEC=$TOTAL_DURATION
		draw_progress "$CURRENT_SEC" "$TOTAL_DURATION" "sec"
	fi
done

FFMPEG_EXIT="${PIPESTATUS[0]}"
set -e
echo ""

if [[ "$FFMPEG_EXIT" -ne 0 ]]; then
	dump_log_and_die "ffmpeg" "$LOGFILE"
fi

rm -f "$LOGFILE"

# Comparing input PDF size to output video size isn't a meaningful metric
# here, so report_size_comparison doesn't fit -- print a custom summary
# instead, same rationale as pdf-a5-print.sh's own "Done!" line.
ok "Done! Output saved to: $(realpath "$OUTPUT")"
echo ""
echo "  Slides:   $TOTAL_PAGES"
echo "  Duration: ${TOTAL_DURATION}s"
echo "  Size:     $(du -sh "$OUTPUT" | cut -f1)"
