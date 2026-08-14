#!/usr/bin/env bash

# Extract the first changelog section whose heading contains the requested
# version. Supports both [0.3.28] and [Mac 0.3.28] headings.

set -euo pipefail

if [[ $# -lt 1 || $# -gt 2 ]]; then
    printf 'Usage: %s VERSION [CHANGELOG_PATH]\n' "$0" >&2
    exit 2
fi

version="$1"
changelog="${2:-CHANGELOG.md}"

[[ -f "$changelog" ]] || exit 1

awk -v version="$version" '
    /^## \[/ {
        if (in_section) {
            exit
        }
        if (index($0, "[" version "]") > 0 || index($0, "[Mac " version "]") > 0) {
            in_section = 1
            found = 1
            next
        }
    }
    in_section && /^---[[:space:]]*$/ {
        exit
    }
    in_section {
        print
    }
    END {
        if (!found) {
            exit 1
        }
    }
' "$changelog"
