#!/bin/bash

# ============================================================
#  pdf-compressor.sh
#  Compresses a PDF with Ghostscript, either with one of three
#  quality/DPI presets or by searching for the highest image
#  quality that fits a target file size (in MB).
#  Dependencies: ghostscript (gs)
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")" &>/dev/null && pwd)"
source "$SCRIPT_DIR/common.sh"

MIN_DPI=30
MAX_DPI=300
DPI_TOLERANCE=10 # stop the search once the DPI window is this narrow

# run_gs <output> <extra-gs-arg>...
# Runs one Ghostscript pass over $INPUT into <output>, drawing a progress bar.
# gs writes its "Processing pages..."/"Page N" progress lines to stderr, so
# they're redirected into LOGFILE (used for the failure dump below) and also
# piped to a parser loop that pulls the total page count once, then feeds
# each page number to draw_progress. The exit code is read from PIPESTATUS[0]
# because $? after a pipeline only reflects the trailing `while` command.
run_gs() {
    local output="$1" gs_exit
    shift
    set +e
    gs -sDEVICE=pdfwrite \
        -dCompatibilityLevel=1.4 \
        -dNOPAUSE -dBATCH \
        -sOutputFile="$output" \
        "$@" \
        "$INPUT" 2>"$LOGFILE" | while IFS= read -r line; do
        if [[ "$line" =~ Processing\ pages\ 1\ through\ ([0-9]+) ]]; then
            TOTAL="${BASH_REMATCH[1]}"
        elif [[ "$line" =~ ^Page[[:space:]]+([0-9]+)$ ]] && [[ "${TOTAL:-0}" -gt 0 ]]; then
            draw_progress "${BASH_REMATCH[1]}" "$TOTAL"
        fi
    done
    gs_exit="${PIPESTATUS[0]}"
    set -e
    echo ""

    if [[ "$gs_exit" -ne 0 ]]; then
        dump_log_and_die "ghostscript" "$LOGFILE"
    fi
}

# format_mb <bytes> -- echoes e.g. "4.20 MB" (1 MB = 1048576 bytes, like du -h).
format_mb() {
    awk -v b="$1" 'BEGIN { printf "%.2f MB", b / 1048576 }'
}

# run_gs_at_dpi <output> <dpi> -- one pass with every image class downsampled to <dpi>.
run_gs_at_dpi() {
    local output="$1" dpi="$2"
    run_gs "$output" \
        -dPDFSETTINGS=/ebook \
        -dDownsampleColorImages=true -dColorImageResolution="$dpi" -dColorImageDownsampleThreshold=1.0 \
        -dDownsampleGrayImages=true -dGrayImageResolution="$dpi" -dGrayImageDownsampleThreshold=1.0 \
        -dDownsampleMonoImages=true -dMonoImageResolution="$dpi" -dMonoImageDownsampleThreshold=1.0
}

# search_best_dpi <fits-command>
# Binary-searches MIN_DPI+1..MAX_DPI for the highest DPI for which
# "<fits-command> <dpi>" succeeds, stopping once the window is narrower than
# DPI_TOLERANCE. Sets BEST_DPI (MIN_DPI if nothing in the window fits).
search_best_dpi() {
    local fits_fn="$1" lo=$((MIN_DPI + 1)) hi=$MAX_DPI mid
    BEST_DPI=$MIN_DPI
    while ((hi - lo >= DPI_TOLERANCE)); do
        mid=$(((lo + hi) / 2))
        if "$fits_fn" "$mid"; then
            BEST_DPI=$mid
            lo=$((mid + 1))
        else
            hi=$((mid - 1))
        fi
    done
}

# dpi_fits <dpi> -- one attempt into $CANDIDATE; on a fit, moves it over $output
# (compress_to_target's output, via TARGET_OUTPUT) and returns 0.
dpi_fits() {
    local dpi="$1" size
    echo "  Trying $dpi dpi..."
    run_gs_at_dpi "$CANDIDATE" "$dpi"
    size=$(stat -c %s "$CANDIDATE")
    if ((size <= TARGET_BYTES_LIMIT)); then
        echo "  → $(format_mb "$size") (fits)"
        mv "$CANDIDATE" "$TARGET_OUTPUT"
        return 0
    fi
    echo "  → $(format_mb "$size") (too big)"
    return 1
}

# compress_to_target <output> <target-bytes>
# Finds the highest image DPI (MIN_DPI..MAX_DPI) whose result is at most
# <target-bytes> and leaves that result in <output>. Tries MIN_DPI first: if
# even that doesn't fit, the target is unreachable (text/fonts/vector data
# aren't affected by downsampling), so it keeps that smallest result and warns.
# Otherwise it binary-searches upward, writing each attempt to a scratch file
# and moving it over <output> only when it fits.
compress_to_target() {
    local output="$1" target="$2" size
    TARGET_OUTPUT="$output"
    TARGET_BYTES_LIMIT="$target"

    echo "  Trying $MIN_DPI dpi (smallest possible)..."
    run_gs_at_dpi "$output" "$MIN_DPI"
    size=$(stat -c %s "$output")
    echo "  → $(format_mb "$size")"
    if ((size > target)); then
        warn "Can't reach $(format_mb "$target"): even $MIN_DPI dpi gives $(format_mb "$size"). Keeping that result."
        return 0
    fi

    search_best_dpi dpi_fits
    ok "Best fit: $BEST_DPI dpi"
}

# Guarded so tests/bash/*.bats can `source` this file to exercise format_mb()
# without running the CLI itself (which would block on the input-file prompt).
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
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
    echo "  4) target   — best quality that fits a file size you enter (MB)"
    echo ""

    while true; do
        read -rp "Choice [1/2/3/4] (default: 2): " CHOICE
        CHOICE="${CHOICE:-2}"
        case "$CHOICE" in
        1)
            PDFSETTINGS="/screen"
            QUALITY_LABEL="screen (72 dpi)"
            break
            ;;
        2)
            PDFSETTINGS="/ebook"
            QUALITY_LABEL="ebook (150 dpi)"
            break
            ;;
        3)
            PDFSETTINGS="/prepress"
            QUALITY_LABEL="prepress (300 dpi)"
            break
            ;;
        4)
            PDFSETTINGS=""
            QUALITY_LABEL="target file size"
            break
            ;;
        *) err "Invalid choice. Enter 1, 2, 3, or 4." ;;
        esac
    done

    ok "Quality: $QUALITY_LABEL"

    if [[ -z "$PDFSETTINGS" ]]; then
        TARGET_MB=$(prompt_number "Target file size in MB (e.g. 5 or 2.5): " "" \
            '^([1-9][0-9]*(\.[0-9]+)?|0\.[0-9]*[1-9][0-9]*)$' "Enter a positive number, e.g. 5 or 2.5.")
        TARGET_BYTES=$(awk -v mb="$TARGET_MB" 'BEGIN { printf "%d", mb * 1048576 }')
        ok "Target: $TARGET_MB MB"
    fi
    echo ""

    # ── Input: Output file ────────────────────────────────────────

    DEFAULT_OUTPUT=$(default_output_name "$INPUT" compressed)

    OUTPUT=$(prompt_output_path "$DEFAULT_OUTPUT")

    # ── Run ───────────────────────────────────────────────────────

    init_logfile
    CANDIDATE=$(mktemp) # scratch output for target-size attempts
    # shellcheck disable=SC2064 # both paths are set once, expand them now
    trap "rm -f '$LOGFILE' '$CANDIDATE'" EXIT

    echo ""

    if [[ -n "$PDFSETTINGS" ]]; then
        run_gs "$OUTPUT" -dPDFSETTINGS="$PDFSETTINGS"
    elif (($(stat -c %s "$INPUT") <= TARGET_BYTES)); then
        warn "Input is already $(format_mb "$(stat -c %s "$INPUT")"), within the $TARGET_MB MB target. Nothing to do."
        exit 0
    else
        compress_to_target "$OUTPUT" "$TARGET_BYTES"
    fi

    report_size_comparison "$INPUT" "$OUTPUT"
fi
