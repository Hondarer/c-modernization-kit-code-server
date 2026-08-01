# ベースイメージ: oracle-linux-container (~/oracle-linux-container) の
# ./build-pod.sh 8 でローカルビルド済みの Podman イメージを前提とする。
# 現時点では OL8 のみを対象とし、OL_VERSION のような切り替えは行わない
# (将来的に oracle-linux-container 同様のバージョン切り替えに拡張可能)。
FROM oracle-linux-8

ARG CODE_SERVER_VERSION=4.131.0

# メタデータラベル
LABEL org.opencontainers.image.title="Oracle Linux 8 + code-server PoC"
LABEL org.opencontainers.image.description="oracle-linux-8 development container extended with code-server for browser-based VS Code access"
LABEL org.opencontainers.image.base.name="oracle-linux-8"

# code-server の Web UI ポートを公開する宣言
EXPOSE 8080

# code-server のインストール
# Oracle Linux 向けの公式 RPM/COPR リポジトリが存在せず、install.sh の
# 自動検出 rpm 経路も動作保証がないため、Node 込みで自己完結する
# standalone 方式を採用する (systemd にも依存しない)。
# バージョンは再現性のため固定する。
RUN curl -fsSL https://code-server.dev/install.sh | sh -s -- \
        --method=standalone \
        --prefix=/usr/local \
        --version=${CODE_SERVER_VERSION}

# エントリーポイント用スクリプトの配置
ADD code-server-entrypoint.sh /usr/local/bin
RUN chown root:root /usr/local/bin/code-server-entrypoint.sh && \
    chmod 0755 /usr/local/bin/code-server-entrypoint.sh

# エントリーポイントの設定 (ベースイメージの sshd 起動用 ENTRYPOINT を上書きする)
ENTRYPOINT ["/bin/sh", "-c", "/usr/local/bin/code-server-entrypoint.sh 2>&1 | tee /var/log/code-server-entrypoint.log"]
