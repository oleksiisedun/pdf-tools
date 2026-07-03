#!/bin/bash
# Shared helpers for pdf-tools scripts. Sourced, never executed directly.

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# ok/warn/err write to stderr (not stdout) because prompt_output_path() below
# is called via command substitution ($(...)); if these wrote to stdout their
# text would get captured into the caller's return value instead of the path.
ok()   { echo -e "${GREEN}✔ $1${NC}" >&2; }
warn() { echo -e "${YELLOW}⚠ $1${NC}" >&2; }
err()  { echo -e "${RED}✘ $1${NC}" >&2; }

# Strip surrounding quotes and unescape spaces (from drag & drop)
clean_path() {
    local p="$1"
    p="${p/#\~/$HOME}"
    p="${p#\'}" ; p="${p%\'}"
    p="${p#\"}" ; p="${p%\"}"
    p="${p//\\ / }"
    echo "$p"
}

draw_progress() {
    local current=$1 total=$2 width=40
    local percent=$(( current * 100 / total ))
    local filled=$(( current * width / total ))
    local bar="" i
    for ((i=0; i<filled; i++)); do bar+="█"; done
    for ((i=filled; i<width; i++)); do bar+="░"; done
    printf "\r  \033[0;32m[%s]\033[0m %3d%%  page %d / %d" "$bar" "$percent" "$current" "$total"
}

# require_bin <binary> <apt-package> [label]
# Simple "binary must exist or bail" dependency check. Only for the
# single-binary case (pdfjam, gs) -- contrast-enhancer's multi-package
# auto-install + venv bootstrap is different in kind and stays inline.
require_bin() {
    local bin="$1" apt_pkg="$2" label="${3:-$bin}"
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

# prompt_output_path <default-filename>
# Prompts for an output filename, enforces .pdf extension, loops on
# overwrite-confirmation if the target already exists.
prompt_output_path() {
    local default="$1" output answer
    read -rp "Enter output file name [$default]: " output
    output="${output/#\~/$HOME}"
    output="${output:-$default}"
    [[ "$output" != *.pdf ]] && output="${output}.pdf"

    while [[ -f "$output" ]]; do
        warn "File already exists: $output"
        read -rp "Overwrite? [y/n] or enter a new name: " answer
        if [[ "$answer" =~ ^[Yy]$ ]]; then
            break
        elif [[ -z "$answer" || "$answer" =~ ^[Nn]$ ]]; then
            read -rp "Enter a new output file name: " output
            output="${output/#\~/$HOME}"
            [[ "$output" != *.pdf ]] && output="${output}.pdf"
        else
            output=$(clean_path "$answer")
            [[ "$output" != *.pdf ]] && output="${output}.pdf"
        fi
    done
    echo "$output"
}
