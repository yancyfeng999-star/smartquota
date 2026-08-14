#!/usr/bin/env bash

# Local, offline-friendly repository governance gate.
# It intentionally reports file names and rules only; it never prints matching
# secret-like content or user data.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

failures=0

fail() {
    printf 'open-source-check: %s\n' "$1" >&2
    failures=$((failures + 1))
}

require_file() {
    local path="$1"
    if [[ ! -s "$path" ]]; then
        fail "required file is missing or empty: $path"
    fi
}

required_files=(
    README.md
    LICENSE
    NOTICE
    SECURITY.md
    CONTRIBUTING.md
    docs/README.md
    docs/USER_GUIDE.md
    docs/DEVELOPER.md
    docs/DISTRIBUTION.md
    docs/REPOSITORY_GOVERNANCE.md
    CODE_OF_CONDUCT.md
    .github/PULL_REQUEST_TEMPLATE.md
    .github/ISSUE_TEMPLATE/bug-report.yml
    .github/ISSUE_TEMPLATE/feature-request.yml
    .github/workflows/build.yml
    .github/workflows/tests.yml
    .github/workflows/release.yml
    scripts/check-open-source-docs.sh
    scripts/extract-changelog.sh
    Apps/Mac/Sources/App/Info.plist
    Apps/Mac/Tuist/Package.swift
    Apps/Mac/Tuist/Package.resolved
)

for path in "${required_files[@]}"; do
    require_file "$path"
done

if ! grep -Fq 'Apache License' LICENSE || ! grep -Fq 'Version 2.0' LICENSE; then
    fail 'LICENSE does not contain the Apache-2.0 heading'
fi

if ! grep -Fq 'END OF TERMS AND CONDITIONS' LICENSE || ! grep -Fq 'WITHOUT WARRANTIES OR CONDITIONS' LICENSE; then
    fail 'LICENSE does not contain the complete Apache-2.0 terms and disclaimer'
fi

if ! grep -Fq 'Apps/Mac/Tuist/Package.resolved' NOTICE; then
    fail 'NOTICE does not identify the tracked dependency lockfile'
fi

if git check-ignore -q Apps/Mac/Tuist/Package.resolved; then
    fail 'Apps/Mac/Tuist/Package.resolved is still ignored'
fi

# Every resolved package identity must have a row in NOTICE. The lockfile is
# JSON, but each identity is on its own line in the SwiftPM format, so this
# parser stays dependency-free on macOS runners.
if [[ -s Apps/Mac/Tuist/Package.resolved ]]; then
    while IFS= read -r identity; do
        [[ -z "$identity" ]] && continue
        if ! grep -Fq "| \`$identity\` |" NOTICE; then
            fail "Package.resolved identity is missing from NOTICE: $identity"
        fi
    done < <(sed -n 's/^[[:space:]]*"identity"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' Apps/Mac/Tuist/Package.resolved)
fi

# Validate local Markdown links in the public entry points. External URLs,
# mailto links and in-page anchors are intentionally not network-checked here.
markdown_files=(
    README.md
    CONTRIBUTING.md
    SECURITY.md
    docs/README.md
    docs/USER_GUIDE.md
    docs/DEVELOPER.md
    docs/DISTRIBUTION.md
    docs/REPOSITORY_GOVERNANCE.md
    CODE_OF_CONDUCT.md
    PRODUCT.md
    PROJECT_STATUS.md
    CHANGELOG.md
)

for document in "${markdown_files[@]}"; do
    [[ -f "$document" ]] || continue
    while IFS= read -r link; do
        [[ -z "$link" ]] && continue
        case "$link" in
            http://*|https://*|mailto:*|//*)
                continue
                ;;
        esac

        target="${link%%#*}"
        [[ -z "$target" ]] && continue
        target="${target#<}"
        target="${target%>}"

        if [[ ! -e "$(dirname "$document")/$target" ]]; then
            fail "broken local link: $document -> $link"
        fi
    done < <(grep -Eo '\]\([^)]*\)' "$document" | sed -E 's/^\]\((.*)\)$/\1/' | sort -u)
done

# The app bundle version is the source of truth for current-version pointers.
app_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Apps/Mac/Sources/App/Info.plist 2>/dev/null || true)"
if [[ -z "$app_version" ]]; then
    fail 'could not read CFBundleShortVersionString from Info.plist'
else
    version_documents=(
        README.md
        PRODUCT.md
        PROJECT_STATUS.md
        Apps/Mac/README.md
        docs/USER_GUIDE.md
        releases/Mac/README.md
    )
    for document in "${version_documents[@]}"; do
        if ! grep -Fq "$app_version" "$document"; then
            fail "current Mac version $app_version is not referenced by $document"
        fi
    done
fi

# Keep public asset filenames free of email-shaped names. This catches a
# common way real or placeholder identity data leaks into an open-source tree.
while IFS= read -r path; do
    [[ -e "$path" ]] || continue
    filename="${path##*/}"
    if [[ "$filename" =~ @[A-Za-z][A-Za-z0-9._%+-]*\.[A-Za-z]{2,}$ ]]; then
        fail "email-shaped filename is not allowed in the repository: $path"
    fi
done < <(git ls-files -co --exclude-standard)

# High-confidence credential patterns only. Examples shorter than these
# thresholds remain available in documentation; matching file names are
# reported, never the matching line contents.
secret_pattern='-----BEGIN (RSA|EC|OPENSSH|DSA|PRIVATE) PRIVATE KEY-----|ghp_[A-Za-z0-9]{20,}|gho_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|sk-[A-Za-z0-9]{20,}'
secret_files="$(rg -l -I --hidden \
    --glob '!.git/**' \
    --glob '!Apps/Mac/.build/**' \
    --glob '!scripts/check-open-source-docs.sh' \
    -e "$secret_pattern" . 2>/dev/null || true)"
if [[ -n "$secret_files" ]]; then
    while IFS= read -r path; do
        [[ -n "$path" ]] && fail "secret-like pattern found in tracked/public text: $path"
    done <<< "$secret_files"
fi

if [[ "$failures" -ne 0 ]]; then
    printf 'open-source-check: FAILED (%s rule(s))\n' "$failures" >&2
    exit 1
fi

printf 'open-source-check: PASS (documents, links, lockfile, NOTICE, version, asset names, and secret patterns)\n'
