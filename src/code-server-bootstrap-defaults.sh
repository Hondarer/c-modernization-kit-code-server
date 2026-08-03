#!/bin/bash

# Initialize default settings and extensions once, using User/settings.json as the completion marker.

set -euo pipefail

HOST_USER="${HOST_USER:-user}"
HOST_UID="${HOST_UID:-1000}"
HOST_GID="${HOST_GID:-1000}"
DEFAULTS_DIR="${CODE_SERVER_DEFAULTS_DIR:-/opt/code-server-defaults}"
USER_HOME="/home/${HOST_USER}"
USER_DATA_DIR="${CODE_SERVER_USER_DATA_DIR:-${USER_HOME}/.local/share/code-server}"
USER_EXTENSIONS_DIR="${USER_DATA_DIR}/extensions"
DEFAULT_SETTINGS="${DEFAULTS_DIR}/User/settings.json"
USER_SETTINGS="${USER_DATA_DIR}/User/settings.json"
DEFAULT_MACHINE_SETTINGS="${DEFAULTS_DIR}/Machine/settings.json"
MACHINE_SETTINGS="${USER_DATA_DIR}/Machine/settings.json"
MANIFEST="${DEFAULTS_DIR}/vsix/resolved-extensions.txt"

[ ! -e "$USER_SETTINGS" ] || {
    echo "Default code-server setup already completed; keeping existing settings and extensions."
    exit 0
}

[ -f "$DEFAULT_SETTINGS" ] || {
    echo "Error: default settings not found: ${DEFAULT_SETTINGS}" >&2
    exit 1
}
[ -f "$DEFAULT_MACHINE_SETTINGS" ] || {
    echo "Error: default settings not found: ${DEFAULT_MACHINE_SETTINGS}" >&2
    exit 1
}
[ -f "$MANIFEST" ] || {
    echo "Error: resolved default extension manifest not found: ${MANIFEST}" >&2
    exit 1
}

mkdir -p "${USER_DATA_DIR}/User" "${USER_DATA_DIR}/Machine" "$USER_EXTENSIONS_DIR"
for directory in \
    "$USER_DATA_DIR" \
    "${USER_DATA_DIR}/User" \
    "${USER_DATA_DIR}/Machine" \
    "$USER_EXTENSIONS_DIR"; do
    if [ "$(stat -c '%u:%g' "$directory")" != "${HOST_UID}:${HOST_GID}" ]; then
        chown "${HOST_UID}:${HOST_GID}" "$directory"
    fi
done

installed_extensions="$(runuser -u "$HOST_USER" -- env \
    HOME="$USER_HOME" USER="$HOST_USER" LOGNAME="$HOST_USER" \
    code-server --user-data-dir "$USER_DATA_DIR" --extensions-dir "$USER_EXTENSIONS_DIR" \
    --list-extensions --show-versions)"

while IFS= read -r manifest_line || [ -n "$manifest_line" ]; do
    extension_spec="${manifest_line%%#*}"
    extension_spec="$(printf '%s' "$extension_spec" | tr -d '[:space:]')"
    [ -n "$extension_spec" ] || continue
    extension_id="${extension_spec%@*}"
    extension_version="${extension_spec##*@}"

    if printf '%s\n' "$installed_extensions" |
        sed 's/@.*$//' | grep -Fqix "$extension_id"; then
        continue
    fi

    vsix_file="${DEFAULTS_DIR}/vsix/${extension_id}-${extension_version}.vsix"
    [ -f "$vsix_file" ] || {
        echo "Error: bundled VSIX not found: ${vsix_file}" >&2
        exit 1
    }
    runuser -u "$HOST_USER" -- env \
        HOME="$USER_HOME" USER="$HOST_USER" LOGNAME="$HOST_USER" \
        code-server --user-data-dir "$USER_DATA_DIR" --extensions-dir "$USER_EXTENSIONS_DIR" \
        --install-extension "$vsix_file" --force >/dev/null
    echo "Installed default code-server extension: ${extension_spec}"
done < "$MANIFEST"

final_extensions="$(runuser -u "$HOST_USER" -- env \
    HOME="$USER_HOME" USER="$HOST_USER" LOGNAME="$HOST_USER" \
    code-server --user-data-dir "$USER_DATA_DIR" --extensions-dir "$USER_EXTENSIONS_DIR" \
    --list-extensions --show-versions)"
while IFS= read -r manifest_line || [ -n "$manifest_line" ]; do
    extension_spec="${manifest_line%%#*}"
    extension_spec="$(printf '%s' "$extension_spec" | tr -d '[:space:]')"
    [ -n "$extension_spec" ] || continue
    extension_id="${extension_spec%@*}"
    printf '%s\n' "$final_extensions" | sed 's/@.*$//' | grep -Fqix "$extension_id" || {
        echo "Error: default extension is not installed: ${extension_id}" >&2
        exit 1
    }
done < "$MANIFEST"

# User/settings.json is the completion marker. Stage both settings files only after every extension
# has been verified, then publish Machine settings before publishing the marker last. An interrupted
# or failed initialization is therefore retried on the next code-server process start.
machine_settings_tmp="${MACHINE_SETTINGS}.tmp.$$"
user_settings_tmp="${USER_SETTINGS}.tmp.$$"
trap 'rm -f "${machine_settings_tmp:-}" "${user_settings_tmp:-}"' EXIT
cp "$DEFAULT_MACHINE_SETTINGS" "$machine_settings_tmp"
cp "$DEFAULT_SETTINGS" "$user_settings_tmp"
chmod 0644 "$machine_settings_tmp" "$user_settings_tmp"
for settings_tmp in "$machine_settings_tmp" "$user_settings_tmp"; do
    if [ "$(stat -c '%u:%g' "$settings_tmp")" != "${HOST_UID}:${HOST_GID}" ]; then
        chown "${HOST_UID}:${HOST_GID}" "$settings_tmp"
    fi
done
mv -f "$machine_settings_tmp" "$MACHINE_SETTINGS"
echo "Installed default code-server setting: Machine/settings.json"
mv -f "$user_settings_tmp" "$USER_SETTINGS"
trap - EXIT
echo "Installed default code-server setting: User/settings.json"
