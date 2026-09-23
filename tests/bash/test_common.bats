#!/usr/bin/env bats
# Pure-logic tests for tools/common.sh: clean_path, ensure_extension,
# default_output_name.

setup() {
    ROOT="$(cd -- "${BATS_TEST_DIRNAME}/../.." &>/dev/null && pwd)"
    source "$ROOT/tools/common.sh"
}

@test "clean_path expands a leading tilde" {
    run clean_path '~/docs/file.pdf'
    [ "$status" -eq 0 ]
    [ "$output" = "$HOME/docs/file.pdf" ]
}

@test "clean_path strips surrounding single quotes" {
    run clean_path "'/path/with space.pdf'"
    [ "$status" -eq 0 ]
    [ "$output" = "/path/with space.pdf" ]
}

@test "clean_path strips surrounding double quotes" {
    run clean_path '"/path/file.pdf"'
    [ "$status" -eq 0 ]
    [ "$output" = "/path/file.pdf" ]
}

@test "clean_path unescapes backslash-escaped spaces" {
    run clean_path '/path/with\ space.pdf'
    [ "$status" -eq 0 ]
    [ "$output" = "/path/with space.pdf" ]
}

@test "clean_path leaves a plain path unchanged" {
    run clean_path '/plain/path.pdf'
    [ "$status" -eq 0 ]
    [ "$output" = "/plain/path.pdf" ]
}

@test "ensure_extension appends the extension when missing" {
    run ensure_extension "/tmp/out" "pdf"
    [ "$status" -eq 0 ]
    [ "$output" = "/tmp/out.pdf" ]
}

@test "ensure_extension leaves a path that already has it unchanged" {
    run ensure_extension "/tmp/out.pdf" "pdf"
    [ "$status" -eq 0 ]
    [ "$output" = "/tmp/out.pdf" ]
}

@test "ensure_extension does not match a different extension" {
    run ensure_extension "/tmp/out.mp4" "pdf"
    [ "$status" -eq 0 ]
    [ "$output" = "/tmp/out.mp4.pdf" ]
}

@test "default_output_name builds <basename>_<suffix>.<ext>" {
    run default_output_name "/tmp/report.pdf" "compressed"
    [ "$status" -eq 0 ]
    [ "$output" = "report_compressed.pdf" ]
}

@test "default_output_name honors a custom extension" {
    run default_output_name "/tmp/slides.pdf" "slideshow" "mp4"
    [ "$status" -eq 0 ]
    [ "$output" = "slides_slideshow.mp4" ]
}

@test "default_output_name handles an input with no .pdf extension" {
    run default_output_name "/tmp/report" "compressed"
    [ "$status" -eq 0 ]
    [ "$output" = "report_compressed.pdf" ]
}
