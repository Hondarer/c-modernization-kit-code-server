#!/bin/bash

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_DIR="$(mktemp -d)"
trap 'rm -rf "$TEST_DIR"' EXIT

mkdir -p "$TEST_DIR/bin" "$TEST_DIR/home"
export HOME="$TEST_DIR/home"
export MOCK_LOG="$TEST_DIR/az.log"
export MOCK_DIR="$TEST_DIR/state"
mkdir -p "$MOCK_DIR"
CONFIG_FILE="$HOME/.azure/code-server-aca.env"

"$REPO_DIR/aca-environment.sh" --config "$CONFIG_FILE" init >/dev/null
test "$(stat -c '%a' "$CONFIG_FILE")" = 600
grep -q '^RESOURCE_GROUP=rg-code-server$' "$CONFIG_FILE"
grep -q '^ENVIRONMENT_NAME=cae-code-server$' "$CONFIG_FILE"
grep -Eq '^SUFFIX=[a-f0-9]{6}$' "$CONFIG_FILE"
if "$REPO_DIR/aca-environment.sh" --config "$CONFIG_FILE" init >/dev/null 2>&1; then
    echo 'init overwrote an existing config' >&2
    exit 1
fi

cat > "$TEST_DIR/bin/az" <<'EOF'
#!/bin/bash
set -e
printf '%s\n' "$*" >> "$MOCK_LOG"
joined=" $* "

case "$joined" in
    *" provider register "*|*" tag create "*|*" role assignment create "*) exit 0 ;;
    *" group create "*) touch "$MOCK_DIR/group"; exit 0 ;;
    *" group show "*) [ -f "$MOCK_DIR/group" ] && echo 'rg-code-server Succeeded japaneast'; exit $? ;;
    *" group delete "*) touch "$MOCK_DIR/deleted"; rm -f "$MOCK_DIR/group"; exit 0 ;;
    *" role assignment list "*) echo 0; exit 0 ;;
    *" resource list "*) exit 0 ;;
esac
[ "$1 $2" != "account show" ] || { echo 'test-subscription test-id test-tenant'; exit 0; }

if [[ "$joined" == *" acr create "* ]]; then touch "$MOCK_DIR/acr"; exit 0; fi
if [[ "$joined" == *" acr show "* ]]; then
    [ -f "$MOCK_DIR/acr" ] || exit 1
    [[ "$joined" == *"loginServer"* ]] && echo 'acrtest.azurecr.io' || echo '/subscriptions/test/acr'
    exit 0
fi
if [[ "$joined" == *" identity create "* ]]; then touch "$MOCK_DIR/identity"; exit 0; fi
if [[ "$joined" == *" identity show "* ]]; then
    [ -f "$MOCK_DIR/identity" ] || exit 1
    if [[ "$joined" == *"principalId"* ]]; then echo 'principal-test'; else echo '/subscriptions/test/identity'; fi
    exit 0
fi
if [[ "$joined" == *" storage account create "* ]]; then touch "$MOCK_DIR/storage"; exit 0; fi
if [[ "$joined" == *" storage account show "* ]]; then
    [ -f "$MOCK_DIR/storage" ] || exit 1
    echo '/subscriptions/test/storage'
    exit 0
fi
if [[ "$joined" == *" containerapp env create "* ]]; then touch "$MOCK_DIR/environment"; exit 0; fi
if [[ "$joined" == *" containerapp env show "* ]]; then
    [ -f "$MOCK_DIR/environment" ] || exit 1
    echo '/subscriptions/test/environment'
    exit 0
fi
exit 0
EOF
chmod +x "$TEST_DIR/bin/az"
export PATH="$TEST_DIR/bin:$PATH"

"$REPO_DIR/aca-environment.sh" --config "$CONFIG_FILE" create >/dev/null
"$REPO_DIR/aca-environment.sh" --config "$CONFIG_FILE" create >/dev/null
test "$(grep -c '^acr create ' "$MOCK_LOG")" = 1
test "$(grep -c '^identity create ' "$MOCK_LOG")" = 1
test "$(grep -c '^storage account create ' "$MOCK_LOG")" = 1
test "$(grep -c '^containerapp env create ' "$MOCK_LOG")" = 1

mkdir -p "$HOME/.azure/code-server-aca/instances/alice"
printf 'secret\n' > "$HOME/.azure/code-server-aca/instances/alice/password"
if printf 'wrong-name\n' | "$REPO_DIR/aca-environment.sh" --config "$CONFIG_FILE" \
    delete --purge-local-state >/dev/null 2>&1; then
    echo 'delete accepted the wrong confirmation' >&2
    exit 1
fi
test -f "$CONFIG_FILE"
printf 'rg-code-server\n' | "$REPO_DIR/aca-environment.sh" --config "$CONFIG_FILE" \
    delete --purge-local-state >/dev/null
test -f "$MOCK_DIR/deleted"
test ! -e "$CONFIG_FILE"
test ! -e "$HOME/.azure/code-server-aca/instances"

echo 'aca-environment tests: PASS'
