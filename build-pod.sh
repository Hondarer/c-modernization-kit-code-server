#!/bin/bash

# rootless podman-compose では、正しく UID のマッピングができない (userns が利用できない) ため、
# podman を直接操作する

source "$(dirname "$0")/version-config.sh" "${1:-1}"

# ベースイメージ (oracle-linux-8) の存在チェック
if ! podman images | grep -q "^localhost/${BASE_IMAGE} \|^${BASE_IMAGE} "; then
    echo "Error: base image ${BASE_IMAGE} not found."
    echo "Please build it first via ~/oracle-linux-container/build-pod.sh 8"
    exit 1
fi

echo "Building container image: ${CONTAINER_NAME}..."

# 既存のコンテナを停止
source ./stop-pod.sh

# 旧イメージの削除
podman rmi ${CONTAINER_NAME} 1>/dev/null 2>/dev/null || true
echo "Clean old container successfully."

# イメージをビルド
echo "Building image..."
podman build -t ${CONTAINER_NAME} ./src/

if [ $? -ne 0 ]; then
    echo "Error: Failed to build container."
    exit 1
fi

# 登録されたイメージの表示
podman images ${CONTAINER_NAME}

echo "Container built successfully."
