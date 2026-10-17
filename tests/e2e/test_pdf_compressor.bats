#!/usr/bin/env bats
# End-to-end: drives tools/pdf-compressor.sh through its prompts with real
# Ghostscript on a generated PDF.

setup() {
    load helpers
    require_cmd gs
    require_signer_venv
    IN="$BATS_TEST_TMPDIR/in.pdf"
    OUT="$BATS_TEST_TMPDIR/out.pdf"
    make_fixture noisy "$IN"
}

@test "screen preset writes a smaller PDF" {
    run bash -c 'printf "%s\n" "$1" 1 "$2" | "$3"' _ "$IN" "$OUT" "$ROOT/tools/pdf-compressor.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Done!"* ]]
    [ -f "$OUT" ]
    (($(file_size "$OUT") < $(file_size "$IN"))) 
}

@test "target-size mode produces a file within the target" {
    run bash -c 'printf "%s\n" "$1" 4 1 "$2" | "$3"' _ "$IN" "$OUT" "$ROOT/tools/pdf-compressor.sh"
    [ "$status" -eq 0 ]
    [ -f "$OUT" ]
    (($(file_size "$OUT") <= 1048576))
}

@test "an invalid menu choice is rejected, then retried" {
    run bash -c 'printf "%s\n" "$1" 9 1 "$2" | "$3"' _ "$IN" "$OUT" "$ROOT/tools/pdf-compressor.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Invalid choice"* ]]
    [ -f "$OUT" ]
}
