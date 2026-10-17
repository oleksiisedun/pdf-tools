#!/usr/bin/env bats
# End-to-end: drives tools/pdf-to-video.sh through its prompts with real
# pdftoppm and ffmpeg on a generated 3-page PDF, then inspects the MP4 with
# ffprobe.

setup() {
    load helpers
    require_cmd pdftoppm
    require_cmd ffmpeg
    require_cmd ffprobe
    require_signer_venv
    IN="$BATS_TEST_TMPDIR/slides.pdf"
    OUT="$BATS_TEST_TMPDIR/show.mp4"
    make_fixture slides "$IN"
}

# run_video <answers...>: pipes the answers (input, seconds, output) into the tool.
run_video() {
    run bash -c 'printf "%s\n" "${@:2}" | "$1"' _ "$ROOT/tools/pdf-to-video.sh" "$@"
}

@test "duration is pages x seconds, as 1920x1080 H.264/yuv420p" {
    run_video "$IN" 2 "$OUT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Slides:   3"* ]]
    [ "$(video_info "$OUT")" = "h264 yuv420p 1920x1080 6" ]
}

@test "defaults to 5 seconds per slide and appends .mp4 to the output name" {
    run_video "$IN" "" "$BATS_TEST_TMPDIR/noext"
    [ "$status" -eq 0 ]
    [ "$(video_info "$BATS_TEST_TMPDIR/noext.mp4")" = "h264 yuv420p 1920x1080 15" ]
}

@test "rejects 0 seconds, then accepts a valid value" {
    run_video "$IN" 0 1 "$OUT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"greater than 0"* ]]
    [ "$(video_info "$OUT")" = "h264 yuv420p 1920x1080 3" ]
}
