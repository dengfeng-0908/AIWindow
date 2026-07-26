#!/bin/bash

set -euo pipefail

repository_root="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
cd "$repository_root"

if ! command -v rg >/dev/null 2>&1; then
    echo "ERROR: ripgrep (rg) is required." >&2
    exit 2
fi

audit_failed=0

report_content_matches() {
    local label="$1"
    local pattern="$2"
    local matches
    matches="$(rg -l --hidden \
        --glob '!.git/**' \
        --glob '!DerivedData/**' \
        --glob '!build/**' \
        --glob '!*.xcresult/**' \
        -- "$pattern" . || true)"
    if [[ -n "$matches" ]]; then
        echo "FAIL: $label" >&2
        echo "$matches" >&2
        audit_failed=1
    fi
}

report_paths() {
    local label="$1"
    local matches="$2"
    if [[ -n "$matches" ]]; then
        echo "FAIL: $label" >&2
        echo "$matches" >&2
        audit_failed=1
    fi
}

team_pattern='DEVELOPMENT_''TEAM[[:space:]]*='
local_path_pattern='/Users''/|/var/folders''/'
private_key_pattern='BEGIN (RSA |EC |OPENSSH )?PRIVATE'' KEY'
token_pattern='sk-''[A-Za-z0-9_-]{20,}|gh[pousr]_''[A-Za-z0-9]{20,}|AKIA''[A-Z0-9]{16}'
bearer_pattern='Bearer[[:space:]]+[A-Za-z0-9._~+/-]{12,}'
email_pattern='[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+[.][A-Za-z]{2,}'
uuid_pattern='[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}'
device_pattern='0000[0-9A-Fa-f]{4}-[0-9A-Fa-f]{16}'

report_content_matches "Apple Team setting is present" "$team_pattern"
report_content_matches "absolute local path is present" "$local_path_pattern"
report_content_matches "private key material is present" "$private_key_pattern"
report_content_matches "known credential token pattern is present" "$token_pattern"
report_content_matches "hard-coded bearer token is present" "$bearer_pattern"
report_content_matches "email address is present" "$email_pattern"
report_content_matches "UUID-like identifier is present" "$uuid_pattern"
report_content_matches "Apple device identifier pattern is present" "$device_pattern"

release_files="$(git ls-files --cached --others --exclude-standard)"

local_state="$(printf '%s\n' "$release_files" | rg \
    '(^|/)([.]DS_Store|[^/]*[.]xcuserstate|[^/]*[.]xcresult(/|$)|[^/]*[.](mobileprovision|provisionprofile|p12|p8|pem|key|cer|der)|[^/]*[.](sqlite|sqlite3|db)|[.]env([.]|$))' \
    | rg -v '(^|/)[.]env[.]example$' \
    || true)"
report_paths "local state or sensitive file is present" "$local_state"

user_data="$(printf '%s\n' "$release_files" | rg '(^|/)xcuserdata/' || true)"
report_paths "Xcode user-data directory is present" "$user_data"

symlinks="$(
    while IFS= read -r file; do
        if [[ -n "$file" && -L "$file" ]]; then
            printf '%s\n' "$file"
        fi
    done <<< "$release_files"
)"
report_paths "symbolic link is present" "$symlinks"

unexpected_media="$(printf '%s\n' "$release_files" \
    | rg -i '[.](png|jpe?g|gif|webp|pdf|zip)$' \
    | rg -v '^apps/ios/AIWindow/Resources/Assets[.]xcassets/AppIcon[.]appiconset/AppIcon[.]png$' \
    || true)"
report_paths "unexpected media or archive requires provenance review" "$unexpected_media"

for required_file in LICENSE NOTICE.md SECURITY.md README.md .gitattributes; do
    if [[ ! -f "$required_file" ]]; then
        echo "FAIL: missing required public file: $required_file" >&2
        audit_failed=1
    fi
done

if [[ -f .gitattributes ]]; then
    for internal_file in PROJECT_STATUS.md 工作交接.md docs/migration.md; do
        export_value="$(git check-attr export-ignore -- "$internal_file" 2>/dev/null \
            | awk -F': ' '{print $3}')"
        if [[ "$export_value" != "set" ]]; then
            echo "FAIL: $internal_file is not marked export-ignore" >&2
            audit_failed=1
        fi
    done
fi

if [[ "$audit_failed" -ne 0 ]]; then
    echo "Public release audit failed." >&2
    exit 1
fi

echo "Public release audit passed."
