#!/bin/bash
# Shared setup for check.sh and checks/*.sh. Sourced, never executed directly.

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." &>/dev/null && pwd)"
# shellcheck source=../tools/common.sh
source "$ROOT/tools/common.sh"
cd "$ROOT" || exit 1

failures=0

# fail <message> -- reports a failed check and counts it toward the exit status.
fail() {
    err "$1"
    failures=$((failures + 1))
}

# optional_bin <binary> <install-hint>
# Returns 0 if the binary is installed. Otherwise returns 1, after warning
# (local runs skip the check) or, when $CI is set, counting a failure so a
# missing tool can't silently disable a guardrail in CI.
optional_bin() {
    local bin="$1" hint="$2"
    command -v "$bin" &>/dev/null && return 0
    if [[ -n "${CI:-}" ]]; then
        fail "$bin not installed ($hint)"
    else
        warn "$bin not installed -- skipping ($hint)"
    fi
    return 1
}
