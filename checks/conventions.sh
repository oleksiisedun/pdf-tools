#!/bin/bash
# Repo-specific conventions from CLAUDE.md that generic linters can't see:
# stderr status helpers, script boilerplate, and dispatcher registration.

set -uo pipefail
# shellcheck source=check-helpers.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/check-helpers.sh"

tool_scripts=(tools/pdf-*.sh)
entry_scripts=(pdf-tools.sh test.sh "${tool_scripts[@]}")

# ok/warn/err must write to stderr: prompt_input_file/prompt_output_path
# return their result on stdout through $(...), so status text on stdout
# would corrupt the returned path.
for fn in ok warn err; do
    grep -Eq "^${fn}\\(\\)[[:space:]]*\\{.*>&2;?[[:space:]]*\\}" tools/common.sh ||
        fail "tools/common.sh: $fn() must write to stderr (>&2)"
done

for f in "${entry_scripts[@]}"; do
    [[ -x "$f" ]] || fail "$f: not executable"
    [[ "$(head -n1 "$f")" == "#!/bin/bash" ]] || fail "$f: first line must be #!/bin/bash"
    grep -q '^set -euo pipefail' "$f" || fail "$f: missing 'set -euo pipefail'"
done

for f in "${tool_scripts[@]}"; do
    grep -qF "source \"\$SCRIPT_DIR/common.sh\"" "$f" || fail "$f: must source common.sh"
    grep -q 'dump_log_and_die' "$f" || fail "$f: failure branch must call dump_log_and_die"
    # pdf-to-video.sh keeps its logfile inside its own scratch dir (see init_logfile).
    grep -qE '^LOGFILE=\$\(mktemp' "$f" && fail "$f: use init_logfile instead of a bare LOGFILE=\$(mktemp)"
    grep -qF "cat \"\$LOGFILE\"" "$f" && fail "$f: inline 'cat \$LOGFILE' -- use dump_log_and_die"
done

# Dispatcher: TOOL_KEYS, TOOL_LABELS and TOOL_SCRIPTS are parallel arrays.
mapfile -t keys < <(sed -n 's/^TOOL_KEYS=(\(.*\))$/\1/p' pdf-tools.sh | tr ' ' '\n')
mapfile -t registered < <(sed -n '/^TOOL_SCRIPTS=(/,/^)/p' pdf-tools.sh | grep -o 'tools/[^"]*\.sh')
label_count=$(sed -n '/^TOOL_LABELS=(/,/^)/p' pdf-tools.sh | grep -c '^ *"')

if ((${#keys[@]} == 0 || ${#registered[@]} == 0)); then
    fail "pdf-tools.sh: could not parse TOOL_KEYS/TOOL_SCRIPTS"
elif ((${#keys[@]} != ${#registered[@]} || ${#registered[@]} != label_count)); then
    fail "pdf-tools.sh: TOOL_KEYS (${#keys[@]}), TOOL_LABELS ($label_count) and TOOL_SCRIPTS (${#registered[@]}) differ in length"
else
    for i in "${!keys[@]}"; do
        [[ "${registered[$i]}" == "tools/${keys[$i]}.sh" ]] ||
            fail "pdf-tools.sh: TOOL_KEYS[$i] '${keys[$i]}' doesn't match TOOL_SCRIPTS[$i] '${registered[$i]}'"
    done
fi

for f in "${tool_scripts[@]}"; do
    printf '%s\n' "${registered[@]}" | grep -qx "$f" || fail "$f: not registered in pdf-tools.sh"
done

# Python payloads live in tools/py/pdf-<name>.py next to their owning
# tools/pdf-<name>.sh, never in heredocs (which no linter looks inside).
for py in tools/py/*.py; do
    [[ -f "tools/$(basename "$py" .py).sh" ]] || fail "$py: no matching tools/$(basename "$py" .py).sh"
done
for f in tools/*.sh; do
    ! grep -q "<< 'PYEOF'" "$f" || fail "$f: embedded Python heredoc -- move it to tools/py/"
done

((failures == 0)) || exit 1
