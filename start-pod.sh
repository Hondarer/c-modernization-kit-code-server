#!/bin/bash

# rootless podman-compose では、正しく UID のマッピングができない (userns が利用できない) ため、
# podman を直接操作する

source "$(dirname "$0")/version-config.sh" "${1:-1}"

# 既存のコンテナを停止
source ./stop-pod.sh

# コンテナイメージの存在チェック
if ! podman images | grep -q "${CONTAINER_NAME}"; then
    echo "Error: image ${CONTAINER_NAME} not found."
    echo "Please ensure ${CONTAINER_NAME} is registered before running this script (./build-pod.sh)."
    exit 1
fi

# ホストのユーザー情報を取得
# USER, UID は OS にて設定済
GID=$(id -g)

echo "Starting container ${CONTAINER_INSTANCE} with user: ${USER} (UID: ${UID}, GID: ${GID})"

# ホスト側ディレクトリ準備
mkdir -p ${STORAGE_DIR}/home_${USER}
mkdir -p ${STORAGE_DIR}/workspace

# コンテナ起動 (UID マッピング + 環境変数でユーザー情報を渡す)
# --userns=keep-id で UID と GID のマッピングを維持しつつ、
# コンテナ内で初期化操作を行いたいため、root で起動
echo "Starting container with keep-id userns..."
podman run -d \
    --name ${CONTAINER_INSTANCE} \
    --userns=keep-id \
    --user root \
    -p ${CODE_SERVER_HOST_PORT}:8080 \
    -v ${STORAGE_DIR}/home_${USER}:/home/${USER}:Z \
    -v ${STORAGE_DIR}/workspace:/workspace:Z \
    --restart unless-stopped \
    --env HOST_USER=${USER} \
    --env HOST_UID=${UID} \
    --env HOST_GID=${GID} \
    ${CONTAINER_NAME}

if [ $? -ne 0 ]; then
    echo "Error: Failed to start container."
    exit 1
fi

# 確認

echo -e "=== Container Info ==="
podman ps | grep ${CONTAINER_INSTANCE}

echo "Container ${CONTAINER_INSTANCE} started successfully. (code-server port: ${CODE_SERVER_HOST_PORT})"
echo ""
echo "接続先: http://localhost:${CODE_SERVER_HOST_PORT}"
echo "パスワードの確認 (起動直後は数秒待ってから実行してください):"
echo "  podman exec ${CONTAINER_INSTANCE} cat /home/${USER}/.config/code-server/config.yaml"
