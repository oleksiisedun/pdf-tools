#!/usr/bin/env bats
# End-to-end: drives tools/pdf-print-marks.sh through its prompts with real
# Tesseract OCR on a generated "scan" (Ukrainian text rendered to an image).

setup() {
    load helpers
    require_cmd tesseract
    tesseract --list-langs 2>/dev/null | grep -qx ukr || skip "tesseract-ocr-ukr not installed"
    require_signer_venv
    IN="$BATS_TEST_TMPDIR/scan.pdf"
    OUT="$BATS_TEST_TMPDIR/marked.pdf"
    make_fixture scan "$IN"
}

# run_marks <intensity> [y|n]: answers the prompts with an explicit output path;
# the optional second answer is for the hidden-message prompt (default n).
run_marks() {
    run bash -c 'printf "%s\n" "$1" "$2" "$3" "$4" | "$5"' _ \
        "$IN" "$OUT" "$1" "${2:-n}" "$ROOT/tools/pdf-print-marks.sh"
}

@test "intensity 10 marks every surname with print-only annotations" {
    run_marks 10
    [ "$status" -eq 0 ]
    [[ "$output" == *"позначок додано"* ]]
    # The fixture has two surnames: "СЕДУН" (suffix) and "СЕДУН О.О." (initials).
    run pdf_annot_summary "$OUT"
    [ "$status" -eq 0 ]
    [ "${#lines[@]}" -eq 2 ]
    # Print (4) + NoView (32): invisible on screen, present on paper.
    for line in "${lines[@]}"; do
        [ "$line" = "FreeText 36" ]
    done
}

@test "intensity 1 marks exactly one surname" {
    run_marks 1
    [ "$status" -eq 0 ]
    run pdf_annot_summary "$OUT"
    [ "${#lines[@]}" -eq 1 ]
}

@test "the original bytes are untouched (incremental save)" {
    run_marks 10
    [ "$status" -eq 0 ]
    cmp -n "$(file_size "$IN")" "$IN" "$OUT"
}

@test "fails with the log when the PDF has no ALL-CAPS surnames" {
    make_fixture noisy "$IN"
    run_marks 5
    [ "$status" -ne 0 ]
    [[ "$output" == *"не знайдено"* ]]
}

@test "embeds the hidden message as a Hidden annotation when asked" {
    run_marks 10 y
    [ "$status" -eq 0 ]
    [[ "$output" == *"прихований текст"* ]]
    run pdf_annot_summary "$OUT"
    [ "${#lines[@]}" -eq 3 ]
    [[ "$output" == *"FreeText 2"* ]]
}

@test "adds no hidden annotation when declined" {
    run_marks 10 n
    run pdf_annot_summary "$OUT"
    [[ "$output" != *"FreeText 2"* ]]
}
