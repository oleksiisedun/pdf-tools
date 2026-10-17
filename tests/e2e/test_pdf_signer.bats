#!/usr/bin/env bats
# End-to-end: drives tools/pdf-signer.sh through its prompts with real
# Tesseract OCR on a generated "scan" (Ukrainian text rendered to an image).

setup() {
    load helpers
    require_cmd tesseract
    tesseract --list-langs 2>/dev/null | grep -qx ukr || skip "tesseract-ocr-ukr not installed"
    require_signer_venv
    SIG="$BATS_TEST_TMPDIR/sig.png"
    SCAN="$BATS_TEST_TMPDIR/scan.pdf"
    make_fixture signature "$SIG"
    make_fixture scan "$SCAN"
}

# run_signer <name> <input> <output>: answers the prompts, keeping the
# gap/height/shift defaults (blank lines).
run_signer() {
    run bash -c 'printf "%s\n" "$1" "$2" "$3" "$4" "" "" "" | "$5"' _ \
        "$SIG" "$1" "$2" "$3" "$ROOT/tools/pdf-signer.sh"
}

@test "stamps the signature on a PDF that contains the name" {
    OUT="$BATS_TEST_TMPDIR/signed.pdf"
    run_signer "Олексій Седун" "$SCAN" "$OUT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"підпис проставлено"* ]]
    [ "$(pdf_image_count "$SCAN")" -eq 1 ]
    [ "$(pdf_image_count "$OUT")" -eq 2 ]
}

@test "fails with the log when the name is on no page" {
    OUT="$BATS_TEST_TMPDIR/signed.pdf"
    run_signer "Іван Петренко" "$SCAN" "$OUT"
    [ "$status" -ne 0 ]
    [[ "$output" == *"не знайдено"* ]]
    [ ! -f "$OUT" ]
}

@test "batch mode signs every PDF in a folder" {
    mkdir "$BATS_TEST_TMPDIR/in"
    cp "$SCAN" "$BATS_TEST_TMPDIR/in/a.pdf"
    cp "$SCAN" "$BATS_TEST_TMPDIR/in/b.pdf"
    run_signer "Олексій Седун" "$BATS_TEST_TMPDIR/in" "$BATS_TEST_TMPDIR/out"
    [ "$status" -eq 0 ]
    [ "$(pdf_image_count "$BATS_TEST_TMPDIR/out/a.pdf")" -eq 2 ]
    [ "$(pdf_image_count "$BATS_TEST_TMPDIR/out/b.pdf")" -eq 2 ]
}
