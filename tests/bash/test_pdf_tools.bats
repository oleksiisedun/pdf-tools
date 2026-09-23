#!/usr/bin/env bats
# Pure-logic tests for pdf-tools.sh: resolve_tool(). Sourcing the script is
# safe -- its CLI/menu body is guarded to run only when executed directly
# (see the BASH_SOURCE[0] == $0 check at the bottom of the file).

setup() {
    ROOT="$(cd -- "${BATS_TEST_DIRNAME}/../.." &>/dev/null && pwd)"
    source "$ROOT/pdf-tools.sh"
}

@test "resolve_tool maps a valid number to a 0-based index" {
    run resolve_tool "1"
    [ "$status" -eq 0 ]
    [ "$output" = "0" ]
}

@test "resolve_tool maps the last valid number to the last index" {
    run resolve_tool "${#TOOL_KEYS[@]}"
    [ "$status" -eq 0 ]
    [ "$output" = "$((${#TOOL_KEYS[@]} - 1))" ]
}

@test "resolve_tool rejects 0 as out of range" {
    run resolve_tool "0"
    [ "$status" -eq 1 ]
}

@test "resolve_tool rejects a number past the last tool" {
    run resolve_tool "$((${#TOOL_KEYS[@]} + 1))"
    [ "$status" -eq 1 ]
}

@test "resolve_tool maps a valid key to its index" {
    run resolve_tool "pdf-compressor"
    [ "$status" -eq 0 ]
    [ "$output" = "1" ]
}

@test "resolve_tool rejects an unknown key" {
    run resolve_tool "bogus"
    [ "$status" -eq 1 ]
}
