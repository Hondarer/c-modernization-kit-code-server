#!/bin/bash

# Resolve compatible Open VSX extensions, bundle their VSIX files and verify them.

set -euo pipefail

DEFAULTS_DIR="${1:-/opt/code-server-defaults}"
MANIFEST="${DEFAULTS_DIR}/extensions.txt"
VSIX_DIR="${DEFAULTS_DIR}/vsix"
VALIDATION_DIR="$(mktemp -d)"
trap 'rm -rf "$VALIDATION_DIR"' EXIT
RESOLVED_MANIFEST="${VSIX_DIR}/resolved-extensions.txt"

[ -f "$MANIFEST" ] || {
    echo "Error: extension manifest not found: ${MANIFEST}" >&2
    exit 1
}

mkdir -p "$VSIX_DIR"
: > "${VSIX_DIR}/SHA256SUMS"
: > "$RESOLVED_MANIFEST"

declare -A seen_extensions=()
while IFS= read -r manifest_line || [ -n "$manifest_line" ]; do
    extension_spec="${manifest_line%%#*}"
    extension_spec="$(printf '%s' "$extension_spec" | tr -d '[:space:]')"
    [ -n "$extension_spec" ] || continue

    if [[ ! "$extension_spec" =~ ^([A-Za-z0-9_-]+)\.([A-Za-z0-9_-]+)(@([A-Za-z0-9._-]+))?$ ]]; then
        echo "Error: invalid extension entry: ${manifest_line}" >&2
        exit 1
    fi

    publisher="${BASH_REMATCH[1]}"
    extension_name="${BASH_REMATCH[2]}"
    requested_version="${BASH_REMATCH[4]:-}"
    extension_id="${publisher}.${extension_name}"
    extension_key="$(printf '%s' "$extension_id" | tr '[:upper:]' '[:lower:]')"
    if [ -n "${seen_extensions[$extension_key]:-}" ]; then
        echo "Error: duplicate extension id: ${extension_id}" >&2
        exit 1
    fi
    seen_extensions[$extension_key]=1

    resolver_user_data="${VALIDATION_DIR}/resolver-user-data"
    resolver_extensions="${VALIDATION_DIR}/resolver-extensions"
    code-server \
        --user-data-dir "$resolver_user_data" \
        --extensions-dir "$resolver_extensions" \
        --install-extension "$extension_spec" \
        --force >/dev/null

    resolved_spec="$(code-server \
        --user-data-dir "$resolver_user_data" \
        --extensions-dir "$resolver_extensions" \
        --list-extensions --show-versions |
        awk -v expected="$extension_key" '
            { original=$0; value=tolower($0); sub(/@[^@]*$/, "", value) }
            value == expected { print original }
        ')"
    [ -n "$resolved_spec" ] && [ "$(printf '%s\n' "$resolved_spec" | wc -l)" -eq 1 ] || {
        echo "Error: code-server did not resolve exactly one version for ${extension_spec}." >&2
        exit 1
    }
    extension_version="${resolved_spec##*@}"
    if [ -n "$requested_version" ] && [ "$extension_version" != "$requested_version" ]; then
        echo "Error: code-server resolved ${extension_id}@${extension_version}, expected ${requested_version}." >&2
        exit 1
    fi

    metadata_url="https://open-vsx.org/api/${publisher}/${extension_name}/${extension_version}"
    metadata_file="${VALIDATION_DIR}/${extension_key}.json"
    curl -fsSL "$metadata_url" -o "$metadata_file"

    actual_id="$(jq -r '.namespace + "." + .name' "$metadata_file")"
    actual_version="$(jq -r '.version' "$metadata_file")"
    download_url="$(jq -r '.files.download' "$metadata_file")"
    if [ "$(printf '%s' "$actual_id" | tr '[:upper:]' '[:lower:]')" != "$extension_key" ] ||
        [ "$actual_version" != "$extension_version" ] || [ -z "$download_url" ] ||
        [ "$download_url" = null ]; then
        echo "Error: Open VSX metadata does not match ${extension_spec}." >&2
        exit 1
    fi

    vsix_file="${VSIX_DIR}/${extension_id}-${extension_version}.vsix"
    curl -fsSL "$download_url" -o "$vsix_file"
    (
        cd "$VSIX_DIR"
        sha256sum "$(basename "$vsix_file")" >> SHA256SUMS
    )

    code-server \
        --user-data-dir "${VALIDATION_DIR}/vsix-user-data-${extension_key}" \
        --extensions-dir "${VALIDATION_DIR}/vsix-extensions-${extension_key}" \
        --install-extension "$vsix_file" \
        --force >/dev/null

    if ! code-server \
        --user-data-dir "${VALIDATION_DIR}/vsix-user-data-${extension_key}" \
        --extensions-dir "${VALIDATION_DIR}/vsix-extensions-${extension_key}" \
        --list-extensions --show-versions |
        grep -Fqi "${extension_id}@${extension_version}"; then
        echo "Error: code-server did not install ${extension_spec}." >&2
        exit 1
    fi
    printf '%s@%s\n' "$extension_id" "$extension_version" >> "$RESOLVED_MANIFEST"
done < "$MANIFEST"

[ "${#seen_extensions[@]}" -gt 0 ] || {
    echo 'Error: extension manifest is empty.' >&2
    exit 1
}

chmod 0644 "$MANIFEST" "${VSIX_DIR}"/*.vsix "${VSIX_DIR}/SHA256SUMS" "$RESOLVED_MANIFEST"
