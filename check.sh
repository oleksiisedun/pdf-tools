#!/bin/bash
# Runs every static check (no network, no PDF tools needed) and exits
# non-zero if any fail. Set CI=1 to make missing optional tools
# (shellcheck, shfmt, ruff, pyright) a failure instead of a skipped check.

set -uo pipefail
# shellcheck source=checks/check-helpers.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/checks/check-helpers.sh"

sh_files=(pdf-tools.sh check.sh test.sh tools/*.sh checks/*.sh)

echo "==> bash -n"
for f in "${sh_files[@]}"; do
    bash -n "$f" || fail "Syntax error in $f"
done

echo "==> shellcheck"
if optional_bin shellcheck "sudo apt install shellcheck"; then
    shellcheck -x --source-path=SCRIPTDIR "${sh_files[@]}" || fail "shellcheck reported issues"
fi

echo "==> shfmt"
if optional_bin shfmt "sudo apt install shfmt"; then
    shfmt -d "${sh_files[@]}" || fail "shfmt: run 'shfmt -w' on the files above"
fi

echo "==> conventions"
checks/conventions.sh || failures=$((failures + 1))

echo "==> Python"
checks/python.sh || failures=$((failures + 1))

echo ""
if ((failures > 0)); then
    err "$failures check(s) failed"
    exit 1
fi
ok "All checks passed"
