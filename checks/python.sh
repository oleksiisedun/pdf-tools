#!/bin/bash
# Lints the tool payloads in tools/py/*.py. Syntax is always checked; ruff
# (errors and pyflakes only: undefined names, unused imports) runs if installed.

set -uo pipefail
# shellcheck source=lib.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/lib.sh"

py_files=(tools/py/*.py)

have_ruff=0
optional_bin ruff "pip install ruff" && have_ruff=1

for f in "${py_files[@]}"; do
    python3 -c 'import ast, sys; ast.parse(open(sys.argv[1], encoding="utf-8").read(), sys.argv[1])' "$f" ||
        fail "$f: syntax error"
done

if ((have_ruff)); then
    ruff check --quiet --isolated --no-cache --select E9,F "${py_files[@]}" || fail "ruff reported issues"
fi

((failures == 0)) || exit 1
