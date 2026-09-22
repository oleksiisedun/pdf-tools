#!/bin/bash
# Shared helpers for pdf-tools scripts. Sourced, never executed directly.

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# The signer's Python environment, shared by tools/pdf-signer.sh and test.sh
# (the unit tests import the same packages).
# shellcheck disable=SC2034 # used by the scripts that source this file
SIGNER_VENV_DIR="$HOME/.pdf-signer-venv"
# shellcheck disable=SC2034 # used by the scripts that source this file
SIGNER_PACKAGES=(pymupdf pytesseract pillow)

# ok/warn/err write to stderr (not stdout) because prompt_output_path() below
# is called via command substitution ($(...)); if these wrote to stdout their
# text would get captured into the caller's return value instead of the path.
ok() { echo -e "${GREEN}✔ $1${NC}" >&2; }
warn() { echo -e "${YELLOW}⚠ $1${NC}" >&2; }
err() { echo -e "${RED}✘ $1${NC}" >&2; }

# Strip surrounding quotes and unescape spaces (from drag & drop)
clean_path() {
    local p="$1"
    p="${p/#\~/$HOME}"
    p="${p#\'}"
    p="${p%\'}"
    p="${p#\"}"
    p="${p%\"}"
    p="${p//\\ / }"
    echo "$p"
}

# init_logfile
# Sets LOGFILE to a fresh tempfile and removes it on any exit (success,
# failure, or Ctrl-C). Every tool that captures an external command's output
# calls this instead of a bare mktemp. Tools that install their own EXIT trap
# (pdf-to-video.sh) place LOGFILE inside their scratch directory instead.
init_logfile() {
    LOGFILE=$(mktemp)
    # shellcheck disable=SC2064 # LOGFILE is set once, expand it now
    trap "rm -f '$LOGFILE'" EXIT
}

# dump_log_and_die <label> <logfile>
# Prints "<label> failed. Full log:" followed by the logfile contents, then
# exits 1. Used by every tool that runs an external command into a logfile.
dump_log_and_die() {
    local label="$1" logfile="$2"
    err "$label failed. Full log:"
    echo ""
    cat "$logfile"
    exit 1
}

# report_size_comparison <input-file> <output-file>
# Prints the standard "Done!" success message plus an input/output size
# comparison. Used by tools that transform a PDF in place (compressor,
# contrast-enhancer).
report_size_comparison() {
    local input="$1" output="$2"
    local input_size output_size
    input_size=$(du -sh "$input" | cut -f1)
    output_size=$(du -sh "$output" | cut -f1)
    ok "Done! Output saved to: $(realpath "$output")"
    echo ""
    echo "  Input size:  $input_size"
    echo "  Output size: $output_size"
}

# prompt_number <prompt-text> <default> [regex] [error-message]
# Prompts for a numeric value, applying the default on empty input, and
# loops on invalid input until it matches regex (default: non-negative
# integer or decimal).
prompt_number() {
    local prompt="$1" default="$2" regex="${3:-^[0-9]+(\.[0-9]+)?$}" error_msg="${4:-Enter a valid number.}" value
    read -rp "$prompt" value
    value="${value:-$default}"
    while [[ ! "$value" =~ $regex ]]; do
        err "$error_msg"
        read -rp "$prompt" value
        value="${value:-$default}"
    done
    echo "$value"
}

draw_progress() {
    local current=$1 total=$2 label="${3:-page}" width=40
    local percent=$((current * 100 / total))
    local filled=$((current * width / total))
    local bar="" i
    for ((i = 0; i < filled; i++)); do bar+="█"; done
    for ((i = filled; i < width; i++)); do bar+="░"; done
    printf "\r  \033[0;32m[%s]\033[0m %3d%%  %s %d / %d" "$bar" "$percent" "$label" "$current" "$total"
}

# require_bin <binary> <apt-package> [label]
# Simple "binary must exist or bail" dependency check. Only for the
# single-binary case (pdfjam, gs) -- the Python tools detect their missing
# packages inline and hand them to apt_install_missing instead.
require_bin() {
    local bin="$1" apt_pkg="$2"
    local label="${3:-$bin}"
    if command -v "$bin" &>/dev/null; then
        ok "$label found"
    else
        err "$label not found."
        echo "" >&2
        echo "Install it with:" >&2
        echo "    sudo apt install $apt_pkg" >&2
        echo "" >&2
        exit 1
    fi
}

# python_venv_apt_pkgs
# Echoes "python3" and/or "python3-venv" (one per line), whichever the system
# is missing. Callers do: MISSING_APT+=($(python_venv_apt_pkgs))
python_venv_apt_pkgs() {
    command -v python3 >/dev/null 2>&1 || echo python3
    python3 -c "import venv" 2>/dev/null || echo "python3-venv"
}

# apt_install_missing <apt-package>...
# Installs the given packages via apt; a no-op when called with none, so
# callers can pass their (possibly empty) missing-package array unconditionally.
apt_install_missing() {
    (($# > 0)) || return 0
    warn "Installing missing packages: $*"
    sudo apt-get install -y "$@"
}

# ensure_venv <venv-dir> <pip-package>...
# Creates the venv if missing, then runs pip install every time to pick up
# dependency updates (a no-op when already current). Callers run the tool's
# Python as "<venv-dir>/bin/python". The venv lives outside the repo (under
# $HOME) so it survives across runs and clones.
ensure_venv() {
    local venv_dir="$1"
    shift
    [[ -d "$venv_dir" ]] || python3 -m venv "$venv_dir"
    "$venv_dir/bin/pip" install --quiet --upgrade pip
    "$venv_dir/bin/pip" install --quiet "$@"
    ok "Python environment ready"
}

# prompt_input_file <prompt-text> [default-on-empty]
# Loops until an existing file path is entered. If a default is passed and
# the user enters nothing, returns the default without validating it. Does
# not print an ok/found message -- callers use different wording ("File 1:",
# "Input:", etc.) so they print their own message after receiving the path.
prompt_input_file() {
    local prompt="$1" default="${2:-}" result
    while true; do
        read -rp "$prompt" result
        result=$(clean_path "$result")
        if [[ -z "$result" && -n "$default" ]]; then
            echo "$default"
            return 0
        elif [[ -f "$result" ]]; then
            echo "$result"
            return 0
        else
            err "File not found: $result"
        fi
    done
}

# ensure_extension <path> <extension>
# Echoes the path with ".<extension>" appended unless it already ends with it.
ensure_extension() {
    local path="$1" ext="$2"
    [[ "$path" == *."$ext" ]] || path="${path}.${ext}"
    echo "$path"
}

# default_output_name <input-pdf> <suffix> [extension]
# Echoes "<input-basename>_<suffix>.<extension>" (extension default: pdf),
# the default output filename every tool offers next to its input.
default_output_name() {
    local input="$1" suffix="$2" ext="${3:-pdf}"
    echo "$(basename "$input" .pdf)_${suffix}.${ext}"
}

# prompt_output_path <default-filename> [extension]
# Prompts for an output filename, enforces the given extension (default:
# pdf), loops on overwrite-confirmation if the target already exists.
prompt_output_path() {
    local default="$1" ext="${2:-pdf}" output answer
    read -rp "Enter output file name [$default]: " output
    output=$(ensure_extension "$(clean_path "${output:-$default}")" "$ext")

    while [[ -f "$output" ]]; do
        warn "File already exists: $output"
        read -rp "Overwrite? [y/n] or enter a new name: " answer
        if [[ "$answer" =~ ^[Yy]$ ]]; then
            break
        elif [[ -z "$answer" || "$answer" =~ ^[Nn]$ ]]; then
            read -rp "Enter a new output file name: " output
            output=$(ensure_extension "$(clean_path "$output")" "$ext")
        else
            output=$(ensure_extension "$(clean_path "$answer")" "$ext")
        fi
    done
    echo "$output"
}
