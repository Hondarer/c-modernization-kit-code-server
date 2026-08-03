#!/bin/bash

# code-server 用エントリーポイントスクリプト
# home/workspace の初期化 (ユーザー作成、所有権修正、既定設定・拡張機能の導入) は
# code-server-init-home.sh に切り出してある。Azure Container Apps では、この
# 初期化が完了してから ingress・startup probe付きの本Appを起動できるよう、同じ
# init-home.sh を独立した init Job としても実行する (docs/code-server-defaults.md,
# docs/azure-container-apps-multi-instance.md を参照)。

/usr/local/bin/code-server-init-home.sh

# code-server を foreground 起動 (ここでブロックされる)
# SSHは起動しない。必要であれば
#    `/usr/sbin/sshd -D &` をこの直前に追加することで併用できる。
echo "Starting code-server..."
# su --login は PASSWORD / HASHED_PASSWORD を破棄するため使用しない。
# HOME 等を明示した上で runuser により権限だけを切り替える。
HOST_USER=${HOST_USER:-user}
export HOME="/home/${HOST_USER}"
export USER="${HOST_USER}"
export LOGNAME="${HOST_USER}"
exec runuser -u "${HOST_USER}" -- code-server /workspace
