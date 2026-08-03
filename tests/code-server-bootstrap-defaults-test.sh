#!/bin/bash

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_DIR="$(mktemp -d)"
trap 'rm -rf "$TEST_DIR"' EXIT

mkdir -p \
    "$TEST_DIR/bin" \
    "$TEST_DIR/defaults/User" \
    "$TEST_DIR/defaults/Machine" \
    "$TEST_DIR/defaults/vsix"
export MOCK_CODE_SERVER_LOG="$TEST_DIR/code-server.log"
export MOCK_FAIL_INSTALL=false

cat > "$TEST_DIR/bin/runuser" <<'EOF'
#!/bin/bash
set -euo pipefail
while [ "$#" -gt 0 ] && [ "$1" != "--" ]; do
    shift
done
[ "$#" -gt 0 ] || exit 1
shift
exec "$@"
EOF

cat > "$TEST_DIR/bin/code-server" <<'EOF'
#!/bin/bash
set -euo pipefail
printf '%s\n' "$*" >> "$MOCK_CODE_SERVER_LOG"
extensions_dir=''
install_spec=''
list=false
while [ "$#" -gt 0 ]; do
    case "$1" in
        --extensions-dir) extensions_dir="$2"; shift 2 ;;
        --user-data-dir) shift 2 ;;
        --install-extension) install_spec="$2"; shift 2 ;;
        --list-extensions) list=true; shift ;;
        --show-versions|--force) shift ;;
        *) shift ;;
    esac
done
mkdir -p "$extensions_dir"
state="$extensions_dir/.installed"
if [ -n "$install_spec" ]; then
    [ "$MOCK_FAIL_INSTALL" != true ] || exit 1
    filename="$(basename "$install_spec" .vsix)"
    version="${filename##*-}"
    extension_id="${filename%-${version}}"
    printf '%s@%s\n' "$extension_id" "$version" >> "$state"
fi
if [ "$list" = true ] && [ -f "$state" ]; then
    sort -fu "$state"
fi
EOF
chmod +x "$TEST_DIR/bin/runuser" "$TEST_DIR/bin/code-server"
export PATH="$TEST_DIR/bin:$PATH"

printf '%s\n' '{"workbench.colorTheme":"Visual Studio Dark - C++"}' \
    > "$TEST_DIR/defaults/User/settings.json"
printf '%s\n' '{"plantuml.jar":"/usr/local/bin/plantuml.jar"}' \
    > "$TEST_DIR/defaults/Machine/settings.json"
printf 'vsix\n' > "$TEST_DIR/defaults/vsix/Example.theme-1.0.0.vsix"
printf '%s\n' 'Example.theme@1.0.0' > "$TEST_DIR/defaults/vsix/resolved-extensions.txt"

run_bootstrap() {
    local user_data_dir="$1"
    CODE_SERVER_DEFAULTS_DIR="$TEST_DIR/defaults" \
    CODE_SERVER_USER_DATA_DIR="$user_data_dir" \
    HOST_USER=user \
    HOST_UID="$(id -u)" \
    HOST_GID="$(id -g)" \
        "$REPO_DIR/src/code-server-bootstrap-defaults.sh"
}

user_data="$TEST_DIR/user-data"
run_bootstrap "$user_data" >/dev/null
cmp "$TEST_DIR/defaults/User/settings.json" "$user_data/User/settings.json"
cmp "$TEST_DIR/defaults/Machine/settings.json" "$user_data/Machine/settings.json"
grep -Fqix 'Example.theme@1.0.0' "$user_data/extensions/.installed"
grep -Fq -- '--install-extension' "$MOCK_CODE_SERVER_LOG"

# Existing settings.json is the only gate. Do not inspect the manifest or repair extensions.
rm -f "$user_data/extensions/.installed"
rm -f "$user_data/Machine/settings.json"
mv "$TEST_DIR/defaults/vsix/resolved-extensions.txt" "$TEST_DIR/resolved-extensions.saved"
mv "$TEST_DIR/defaults/Machine/settings.json" "$TEST_DIR/machine-settings.saved"
before_calls="$(wc -l < "$MOCK_CODE_SERVER_LOG")"
run_bootstrap "$user_data" >/dev/null
after_calls="$(wc -l < "$MOCK_CODE_SERVER_LOG")"
test "$before_calls" = "$after_calls"
test ! -e "$user_data/extensions/.installed"
test ! -e "$user_data/Machine/settings.json"

# Removing settings.json opts into initialization on the next process start.
mv "$TEST_DIR/resolved-extensions.saved" "$TEST_DIR/defaults/vsix/resolved-extensions.txt"
mv "$TEST_DIR/machine-settings.saved" "$TEST_DIR/defaults/Machine/settings.json"
rm -f "$user_data/User/settings.json"
run_bootstrap "$user_data" >/dev/null
grep -Fqix 'Example.theme@1.0.0' "$user_data/extensions/.installed"
test -f "$user_data/User/settings.json"
cmp "$TEST_DIR/defaults/Machine/settings.json" "$user_data/Machine/settings.json"

# A failed extension installation must not create the completion marker.
failed_user_data="$TEST_DIR/failed-user-data"
export MOCK_FAIL_INSTALL=true
if run_bootstrap "$failed_user_data" >/dev/null 2>&1; then
    echo 'bootstrap unexpectedly succeeded after an extension installation failure' >&2
    exit 1
fi
test ! -e "$failed_user_data/User/settings.json"
test ! -e "$failed_user_data/Machine/settings.json"

echo 'code-server bootstrap defaults tests: PASS'
