#!/bin/bash

# ============================================================
#  pdf-tools.sh
#  Single entry point for all pdf-tools scripts.
#  Usage:
#    ./pdf-tools.sh                 interactive menu
#    ./pdf-tools.sh <tool>          run one tool directly and exit
#    ./pdf-tools.sh -h|--help       show usage
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")" &>/dev/null && pwd)"
source "$SCRIPT_DIR/tools/common.sh"

TOOL_KEYS=(pdf-a5-print pdf-compressor pdf-contrast-enhancer pdf-to-video pdf-signer)
TOOL_LABELS=(
    "Combine two A5 PDFs onto one A4 landscape page"
    "Compress a PDF with Ghostscript"
    "Increase PDF contrast and sharpness"
    "Convert a PDF presentation to a slideshow video"
    "Stamp a signature image next to a signer's name in a scanned PDF"
)
TOOL_SCRIPTS=(
    "$SCRIPT_DIR/tools/pdf-a5-print.sh"
    "$SCRIPT_DIR/tools/pdf-compressor.sh"
    "$SCRIPT_DIR/tools/pdf-contrast-enhancer.sh"
    "$SCRIPT_DIR/tools/pdf-to-video.sh"
    "$SCRIPT_DIR/tools/pdf-signer.sh"
)

print_tool_list() {
    local i
    for i in "${!TOOL_KEYS[@]}"; do
        printf "  %d) %-23s %s\n" "$((i + 1))" "${TOOL_KEYS[$i]}" "${TOOL_LABELS[$i]}"
    done
}

print_usage() {
    echo "Usage: $(basename "$0") [tool]"
    echo ""
    echo "With no arguments, shows an interactive menu."
    echo "Available tools:"
    print_tool_list
}

# resolve_tool <key-or-number> -- echoes the matching index (0-based), or
# returns 1 if there's no match.
resolve_tool() {
    local query="$1" i
    if [[ "$query" =~ ^[0-9]+$ ]] && ((query >= 1 && query <= ${#TOOL_KEYS[@]})); then
        echo "$((query - 1))"
        return 0
    fi
    for i in "${!TOOL_KEYS[@]}"; do
        if [[ "${TOOL_KEYS[$i]}" == "$query" ]]; then
            echo "$i"
            return 0
        fi
    done
    return 1
}

run_tool() {
    local idx="$1"
    "${TOOL_SCRIPTS[$idx]}"
}

show_menu() {
    echo ""
    echo "Select a tool:"
    print_tool_list
    echo "  q) Quit"
    echo ""
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    print_usage
    exit 0
fi

if [[ -n "${1:-}" ]]; then
    if idx=$(resolve_tool "$1"); then
        run_tool "$idx"
        exit $?
    else
        err "Unknown tool: $1"
        echo ""
        print_usage
        exit 1
    fi
fi

while true; do
    show_menu
    read -rp "Choice: " CHOICE
    if [[ "$CHOICE" =~ ^[Qq]$ ]]; then
        break
    fi
    if idx=$(resolve_tool "$CHOICE"); then
        echo ""
        set +e
        run_tool "$idx"
        set -e
    else
        err "Invalid choice: $CHOICE"
    fi
done
