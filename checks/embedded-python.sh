#!/bin/bash
# Lints the Python embedded in bash heredocs (<< 'PYEOF'), which neither
# `bash -n` nor shellcheck looks inside. Syntax is always checked; ruff
# (errors and pyflakes only: undefined names, unused imports) runs if
# installed. Reported line numbers are relative to the start of the heredoc.

set -uo pipefail
# shellcheck source=lib.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/lib.sh"

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

have_ruff=0
optional_bin ruff "pip install ruff" && have_ruff=1

for f in scripts/*.sh; do
    grep -q "<< 'PYEOF'" "$f" || continue
    py="$tmpdir/$(basename "$f" .sh).py"
    awk "/<< 'PYEOF'/{p=1;next} /^PYEOF\$/{p=0} p" "$f" >"$py"
    if [[ ! -s "$py" ]]; then
        fail "$f: could not extract embedded Python"
        continue
    fi
    python3 -c 'import ast, sys; ast.parse(open(sys.argv[1]).read(), sys.argv[1])' "$py" ||
        fail "$f: embedded Python has a syntax error"
    if ((have_ruff)); then
        ruff check --quiet --isolated --no-cache --select E9,F "$py" || fail "$f: ruff reported issues"
    fi
done

((failures == 0)) || exit 1
