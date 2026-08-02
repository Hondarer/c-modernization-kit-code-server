#!/bin/bash

# version-config.sh - code-server コンテナの共通設定
#
# 使用方法:
#   source ./version-config.sh [INSTANCE_NUM]
#
# 引数:
#   INSTANCE_NUM - インスタンス番号 (デフォルト: 1)
#
# 設定される変数:
#   INSTANCE_NUM, CONTAINER_NAME, CONTAINER_INSTANCE,
#   CODE_SERVER_HOST_PORT, STORAGE_DIR, BASE_IMAGE

# 既に設定済みの場合はスキップ (build-pod.sh から stop-pod.sh を source する場合など)
if [ -n "${CONTAINER_NAME}" ] && [ -z "${1}" ]; then
    return 0 2>/dev/null || true
fi

INSTANCE_NUM="${1:-1}"

# インスタンス番号の検証
if ! [ "${INSTANCE_NUM}" -ge 1 ] 2>/dev/null; then
    echo "Error: Invalid instance number: ${INSTANCE_NUM}"
    echo "Instance number must be a positive integer."
    exit 1
fi

CONTAINER_NAME="code-server-ol8"
CONTAINER_INSTANCE="${CONTAINER_NAME}_${INSTANCE_NUM}"

# ポート番号: 8080 + (INSTANCE_NUM - 1)
# oracle-linux-container の SSH ポート帯 (40000+) とは衝突しない
CODE_SERVER_HOST_PORT=$((8080 + INSTANCE_NUM - 1))

STORAGE_DIR="./storage/${INSTANCE_NUM}"
BASE_IMAGE="${BASE_IMAGE:-ghcr.io/hondarer/oracle-linux-container/oracle-linux-8-dev:latest}"
