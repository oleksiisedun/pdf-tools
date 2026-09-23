#!/usr/bin/env bats
# Pure-logic test for tools/pdf-compressor.sh: format_mb(). Sourcing the
# script is safe -- its dependency check/prompts are guarded to run only
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
