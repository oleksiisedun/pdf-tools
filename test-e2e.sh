#!/bin/bash
# Runs the end-to-end tests (bats, tests/e2e/): feeds generated PDFs through
# the real tools, so it needs their system dependencies (gs, tesseract-ocr-ukr)
# and the signer's venv. Tests skip when a dependency is missing. Extra
# arguments go to bats.
# Usage: ./test-e2e.sh [bats args, e.g. -f signer]  (a file path arg would run the dir too)

set -euo pipefail
# shellcheck source=checks/check-helpers.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/checks/check-helpers.sh"

command -v bats >/dev/null || {
    err "bats not found (sudo apt install bats)"
    exit 1
}

exec bats tests/e2e "$@"
