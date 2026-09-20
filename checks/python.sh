#!/bin/bash
# Lints the tool payloads in tools/py/*.py and their tests in tests/py/*.py.
# Syntax is always checked; ruff (rules and line length from pyproject.toml,
# plus formatting) and pyright run if installed.

set -uo pipefail
# shellcheck source=check-helpers.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/check-helpers.sh"

py_files=(tools/py/*.py tests/py/*.py)

have_ruff=0
optional_bin ruff "pip install ruff" && have_ruff=1
have_pyright=0
optional_bin pyright "pip install pyright" && have_pyright=1

for f in "${py_files[@]}"; do
    python3 -c 'import ast, sys; ast.parse(open(sys.argv[1], encoding="utf-8").read(), sys.argv[1])' "$f" ||
        fail "$f: syntax error"
done

if ((have_ruff)); then
    ruff check --quiet --no-cache "${py_files[@]}" || fail "ruff reported issues"
    ruff format --check --quiet --no-cache "${py_files[@]}" || fail "ruff format: run 'ruff format tools/py tests/py'"
fi

if ((have_pyright)); then
    pyright --warnings >/dev/null || fail "pyright reported issues (run 'pyright' for details)"
fi

((failures == 0)) || exit 1
