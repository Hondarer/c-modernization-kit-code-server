#!/bin/bash

# rootless podman-compose では、正しく UID のマッピングができない (userns が利用できない) ため、
# podman を直接操作する

source "$(dirname "$0")/version-config.sh" "${1:-1}"

echo "Pulling base image: ${BASE_IMAGE}..."
podman pull "$BASE_IMAGE"

BASE_IMAGE_DIGEST="$(podman image inspect "$BASE_IMAGE" --format '{{.Digest}}')"
if [[ ! "$BASE_IMAGE_DIGEST" =~ ^sha256:[a-f0-9]{64}$ ]]; then
    echo "Error: could not resolve base image digest: ${BASE_IMAGE_DIGEST}" >&2
    exit 1
fi
BASE_IMAGE_REPOSITORY="${BASE_IMAGE%:*}"
RESOLVED_BASE_IMAGE="${BASE_IMAGE_REPOSITORY}@${BASE_IMAGE_DIGEST}"
echo "Resolved base image: ${RESOLVED_BASE_IMAGE}"

echo "Building container image: ${CONTAINER_NAME}..."

# 既存のコンテナを停止
source ./stop-pod.sh

# 同名ローカルイメージの置換
podman rmi ${CONTAINER_NAME} 1>/dev/null 2>/dev/null || true
echo "Clean old container successfully."

# イメージをビルド
echo "Building image..."
podman build \
    --pull=never \
    --build-arg "BASE_IMAGE=${RESOLVED_BASE_IMAGE}" \
    --build-arg "BASE_IMAGE_DIGEST=${BASE_IMAGE_DIGEST}" \
    -t "$CONTAINER_NAME" \
    ./src/

if [ $? -ne 0 ]; then
    echo "Error: Failed to build container."
    exit 1
fi

# 登録されたイメージの表示
podman images ${CONTAINER_NAME}

echo "Container built successfully."
