ARG BASE_IMAGE=ghcr.io/hondarer/oracle-linux-container/oracle-linux-8-dev:latest
FROM ${BASE_IMAGE}

ARG BASE_IMAGE
ARG BASE_IMAGE_DIGEST=unknown
ARG CODE_SERVER_VERSION=4.131.0

# メタデータラベル
LABEL org.opencontainers.image.title="Oracle Linux 8 + code-server"
LABEL org.opencontainers.image.description="oracle-linux-8 development container extended with code-server for browser-based VS Code access"
LABEL org.opencontainers.image.base.name="${BASE_IMAGE}"
LABEL org.opencontainers.image.base.digest="${BASE_IMAGE_DIGEST}"

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

# code-serverの既定設定と解決済みversionの拡張機能をイメージへ同梱する。
# 拡張はbuild時にOpen VSXから取得・インストール検証し、runtimeでは
# イメージ内のVSIXだけを使用する。
ADD code-server-defaults /opt/code-server-defaults
ADD install-default-extensions.sh /usr/local/bin
RUN chown -R root:root /opt/code-server-defaults \
        /usr/local/bin/install-default-extensions.sh && \
    chmod 0755 /usr/local/bin/install-default-extensions.sh && \
    /usr/local/bin/install-default-extensions.sh && \
    rm -f /root/.config/code-server/config.yaml

# エントリーポイント用スクリプトの配置
ADD code-server-entrypoint.sh code-server-bootstrap-defaults.sh /usr/local/bin/
RUN chown root:root /usr/local/bin/code-server-entrypoint.sh \
        /usr/local/bin/code-server-bootstrap-defaults.sh && \
    chmod 0755 /usr/local/bin/code-server-entrypoint.sh \
        /usr/local/bin/code-server-bootstrap-defaults.sh

# エントリーポイントの設定 (ベースイメージの sshd 起動用 ENTRYPOINT を上書きする)
# ログはコンテナの標準出力へ送り、Podman / Container Apps 側で収集する。
# パイプを介さないことで、終了コードと停止シグナルを正しく伝播させる。
ENTRYPOINT ["/usr/local/bin/code-server-entrypoint.sh"]
