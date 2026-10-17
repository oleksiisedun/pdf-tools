#!/usr/bin/env bats
# Pure-logic tests for tools/pdf-compressor.sh: format_mb() and
# search_best_dpi(). Sourcing the script is safe -- its dependency check/prompts are guarded to run only
# when executed directly, so this doesn't require ghostscript or any input.

setup() {
    ROOT="$(cd -- "${BATS_TEST_DIRNAME}/../.." &>/dev/null && pwd)"
    source "$ROOT/tools/pdf-compressor.sh"
}

@test "format_mb converts bytes to a 2-decimal MB string" {
    run format_mb 4404019 # 4.20 MB at 1 MB = 1048576 bytes
    [ "$status" -eq 0 ]
    [ "$output" = "4.20 MB" ]
}

@test "format_mb handles exactly zero bytes" {
    run format_mb 0
    [ "$status" -eq 0 ]
    [ "$output" = "0.00 MB" ]
}

@test "format_mb handles exactly one MB" {
    run format_mb 1048576
    [ "$status" -eq 0 ]
    [ "$output" = "1.00 MB" ]
}

# search_best_dpi sets BEST_DPI, so these call it directly instead of via `run`.
fits_up_to_150() { ((${1} <= 150)); }
always_fits() { return 0; }
never_fits() { return 1; }

@test "search_best_dpi lands within tolerance below the highest fitting DPI" {
    search_best_dpi fits_up_to_150
    [ "$BEST_DPI" -le 150 ]
    [ "$BEST_DPI" -gt $((150 - DPI_TOLERANCE)) ]
}

@test "search_best_dpi approaches MAX_DPI when every attempt fits" {
    search_best_dpi always_fits
    [ "$BEST_DPI" -le "$MAX_DPI" ]
    [ "$BEST_DPI" -gt $((MAX_DPI - DPI_TOLERANCE)) ]
}

@test "search_best_dpi keeps MIN_DPI when nothing above it fits" {
    search_best_dpi never_fits
    [ "$BEST_DPI" -eq "$MIN_DPI" ]
}
