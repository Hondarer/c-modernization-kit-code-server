#!/bin/bash

# rootless podman-compose では、正しく UID のマッピングができない (userns が利用できない) ため、
# podman を直接操作する

# 他スクリプトから source される場合は既に設定済み
if [ -z "${CONTAINER_INSTANCE}" ]; then
    source "$(dirname "$0")/version-config.sh" "${1:-1}"
fi

# 既存のコンテナを停止・削除
podman stop ${CONTAINER_INSTANCE} 1>/dev/null 2>/dev/null || true
podman rm ${CONTAINER_INSTANCE} 1>/dev/null 2>/dev/null || true

echo "Container ${CONTAINER_INSTANCE} stopped successfully."
