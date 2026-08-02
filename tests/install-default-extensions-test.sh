#!/bin/bash

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_DIR="$(mktemp -d)"
trap 'rm -rf "$TEST_DIR"' EXIT
mkdir -p "$TEST_DIR/bin"

cat > "$TEST_DIR/bin/code-server" <<'EOF'
#!/bin/bash
set -euo pipefail
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
    case "$install_spec" in
        *.vsix)
            filename="$(basename "$install_spec" .vsix)"
            version="${filename##*-}"
            id="${filename%-${version}}"
            resolved="${id}@${version}"
            ;;
        *@*) resolved="$install_spec" ;;
        *) resolved="${install_spec}@9.9.0" ;;
    esac
    printf '%s\n' "$resolved" >> "$state"
fi
if [ "$list" = true ] && [ -f "$state" ]; then
    sort -fu "$state"
fi
EOF
chmod +x "$TEST_DIR/bin/code-server"

cat > "$TEST_DIR/bin/curl" <<'EOF'
#!/bin/bash
set -euo pipefail
output=''
url=''
while [ "$#" -gt 0 ]; do
    case "$1" in
        -o) output="$2"; shift 2 ;;
        -*) shift ;;
        *) url="$1"; shift ;;
    esac
done
case "$url" in
    https://open-vsx.org/api/Example/dynamic/9.9.0)
        printf '%s\n' '{"namespace":"Example","name":"dynamic","version":"9.9.0","files":{"download":"https://download/dynamic.vsix"}}' > "$output"
        ;;
    https://open-vsx.org/api/Example/fixed/2.0.0)
        printf '%s\n' '{"namespace":"Example","name":"fixed","version":"2.0.0","files":{"download":"https://download/fixed.vsix"}}' > "$output"
        ;;
    https://download/*.vsix) printf 'vsix:%s\n' "$url" > "$output" ;;
    *) echo "unexpected URL: $url" >&2; exit 1 ;;
esac
EOF
chmod +x "$TEST_DIR/bin/curl"
export PATH="$TEST_DIR/bin:$PATH"

defaults="$TEST_DIR/defaults"
mkdir -p "$defaults"
cat > "$defaults/extensions.txt" <<'EOF'
# compatible latest
Example.dynamic
Example.fixed@2.0.0
EOF
"$REPO_DIR/src/install-default-extensions.sh" "$defaults"
grep -Fqix 'Example.dynamic@9.9.0' "$defaults/vsix/resolved-extensions.txt"
grep -Fqix 'Example.fixed@2.0.0' "$defaults/vsix/resolved-extensions.txt"
(cd "$defaults/vsix" && sha256sum -c SHA256SUMS >/dev/null)

printf 'invalid entry\n' > "$defaults/extensions.txt"
if "$REPO_DIR/src/install-default-extensions.sh" "$defaults" >/dev/null 2>&1; then
    echo 'invalid extension entry was accepted' >&2
    exit 1
fi

cat > "$defaults/extensions.txt" <<'EOF'
Example.dynamic
example.DYNAMIC@9.9.0
EOF
if "$REPO_DIR/src/install-default-extensions.sh" "$defaults" >/dev/null 2>&1; then
    echo 'duplicate extension id was accepted' >&2
    exit 1
fi

echo 'default extension installer tests: PASS'
