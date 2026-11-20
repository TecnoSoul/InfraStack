#!/bin/bash
#=============================================================================
# InfraStack - Private data leak check
# Searches tracked files for strings that must not be published (real hosts,
# public IPs, client names). The strings live in a gitignored file, one fixed
# string per line ('#' starts a comment), so the list itself is never committed.
#
# Usage: bash tests/check-private-data.sh [patterns-file]
#        (default patterns file: .private/patterns.txt)
# Exit:  0 = clean or no patterns file, 1 = matches found
#=============================================================================

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRASTACK_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PATTERNS_FILE="${1:-$INFRASTACK_ROOT/.private/patterns.txt}"

if [[ ! -f "$PATTERNS_FILE" ]]; then
    echo "[SKIP] No patterns file at $PATTERNS_FILE"
    exit 0
fi

patterns=$(grep -vE '^\s*(#|$)' "$PATTERNS_FILE")
if [[ -z "$patterns" ]]; then
    echo "[SKIP] Patterns file is empty"
    exit 0
fi

# CHANGELOG.md is checked too: history entries must stay generic as well
if matches=$(git -C "$INFRASTACK_ROOT" grep -n -I -i -F -f <(echo "$patterns")); then
    echo "[FAIL] Private data found in tracked files:"
    echo "$matches"
    exit 1
fi

echo "[PASS] No private data in tracked files ($(echo "$patterns" | wc -l) patterns)"
exit 0
