#!/bin/bash
# Runs the bash unit tests (bats-core, tests/bash/) covering pure logic in
# tools/common.sh, pdf-tools.sh and tools/pdf-compressor.sh. Extra arguments
# go to bats.
# Usage: ./test-bash.sh [bats args, e.g. -f resolve_tool]

set -euo pipefail
# shellcheck source=checks/check-helpers.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/checks/check-helpers.sh"

command -v bats >/dev/null || {
    err "bats not found (sudo apt install bats)"
    exit 1
}

exec bats tests/bash "$@"
