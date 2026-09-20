#!/bin/bash
# Runs the unit tests (pytest, tests/py/) inside the signer's venv. Installs
# pytest there on first use. Extra arguments go to pytest.
# Usage: ./test.sh [pytest args, e.g. -k locate -x]

set -eo pipefail
# shellcheck source=checks/check-helpers.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/checks/check-helpers.sh"

command -v python3 >/dev/null || {
    err "python3 not found (sudo apt install python3 python3-venv)"
    exit 1
}

venv_python="$SIGNER_VENV_DIR/bin/python"

# Only touch pip when something is missing, so a normal run works offline.
if ! "$venv_python" -c 'import pytest, pymupdf, pytesseract, PIL' 2>/dev/null; then
    ensure_venv "$SIGNER_VENV_DIR" "${SIGNER_PACKAGES[@]}" pytest
fi

exec "$venv_python" -m pytest tests/py "$@"
