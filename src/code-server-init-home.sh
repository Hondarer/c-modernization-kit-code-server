#!/bin/bash

# code-server の home/workspace 初期化スクリプト
# ユーザー/グループ作成、所有権修正、home初期化、config.yaml生成、既定拡張の導入までを
# 行う。code-server-entrypoint.sh から呼ばれるほか、Azure Container Apps の
# init Job からも単独で呼ばれる (拡張機能の再展開はAzure Filesでは時間がかかるため、
# ingress・startup probe付きのAppを起動する前に、別Jobとして完了させておく)。

# 環境変数からユーザー情報を取得
HOST_USER=${HOST_USER:-user}
HOST_UID=${HOST_UID:-1000}
HOST_GID=${HOST_GID:-1000}

# code-server は PASSWORD と HASHED_PASSWORD の両方が指定された場合、
# hashed-password を優先する。設定ミスを見逃さないよう、このコンテナでは
# どちらか一方だけを許可する。
if [ -n "${PASSWORD:-}" ] && [ -n "${HASHED_PASSWORD:-}" ]; then
    echo "Error: PASSWORD and HASHED_PASSWORD cannot be set at the same time." >&2
    exit 1
fi

echo "Creating user: ${HOST_USER} (UID: ${HOST_UID}, GID: ${HOST_GID})"

# グループの作成 (存在しない場合)
if ! getent group "${HOST_GID}" >/dev/null 2>&1; then
    groupadd -g "${HOST_GID}" "${HOST_USER}"
    echo "Created group: ${HOST_USER} (GID: ${HOST_GID})"
else
    EXISTING_GROUP=$(getent group "${HOST_GID}" | cut -d: -f1)
    echo "Group GID ${HOST_GID} already exists as: ${EXISTING_GROUP}"
    # 既存グループ名が HOST_USER と異なる場合、グループ名を変更
    if [ "${EXISTING_GROUP}" != "${HOST_USER}" ]; then
        groupmod -n "${HOST_USER}" "${EXISTING_GROUP}"
        echo "Renamed group ${EXISTING_GROUP} to ${HOST_USER}"
    fi
fi

# ユーザーの作成 (存在しない場合)
if ! getent passwd "${HOST_UID}" >/dev/null 2>&1; then
    useradd -u "${HOST_UID}" -g "${HOST_GID}" -G wheel -d "/home/${HOST_USER}" -m -s /bin/bash "${HOST_USER}"
    echo "Created user: ${HOST_USER} (UID: ${HOST_UID})"
else
    EXISTING_USER=$(getent passwd "${HOST_UID}" | cut -d: -f1)
    echo "User UID ${HOST_UID} already exists as: ${EXISTING_USER}"
    # 既存ユーザー名が HOST_USER と異なる場合、ユーザー名を変更
    if [ "${EXISTING_USER}" != "${HOST_USER}" ]; then
        usermod -l "${HOST_USER}" "${EXISTING_USER}"
        usermod -d "/home/${HOST_USER}" -m "${HOST_USER}"
        echo "Renamed user ${EXISTING_USER} to ${HOST_USER}"
    fi

    # wheel グループ所属チェックと追加
    if ! id -nG "${HOST_USER}" | grep -qw wheel; then
        usermod -aG wheel "${HOST_USER}"
        echo "Added ${HOST_USER} to wheel group"
    fi
fi

# パスワードの設定 (sudo 用。code-server 自体の認証とは別)
echo "${HOST_USER}:${HOST_USER}_passwd" | chpasswd
echo "Set local password for ${HOST_USER}."

# ホームディレクトリの所有権を確認・修正
if [ -d "/home/${HOST_USER}" ]; then
    current_uid=$(stat -c "%u" "/home/${HOST_USER}")
    current_gid=$(stat -c "%g" "/home/${HOST_USER}")
    if [ "$current_uid" -ne "$HOST_UID" ] || [ "$current_gid" -ne "$HOST_GID" ]; then
        chown "${HOST_UID}:${HOST_GID}" "/home/${HOST_USER}"
    fi
fi

# ワークスペースディレクトリの所有権を確認・修正
if [ -d "/workspace" ]; then
    current_uid=$(stat -c "%u" "/workspace")
    current_gid=$(stat -c "%g" "/workspace")
    if [ "$current_uid" -ne "$HOST_UID" ] || [ "$current_gid" -ne "$HOST_GID" ]; then
        chown "${HOST_UID}:${HOST_GID}" "/workspace"
    fi
fi

# USER_HOME が空 (~/.ssh は評価対象から除く) の場合に初期ファイルを配置
if [ -z "$(find /home/${HOST_USER} -mindepth 1 -not -path "/home/${HOST_USER}/.ssh/*" -not -name ".ssh" -print -quit 2>/dev/null)" ]; then
    echo "Initializing home for ${HOST_USER}..."

    cd /tmp
    rm -rf temp_home
    mkdir temp_home
    cd temp_home
    cp -a /etc/skel/. .

    echo export LANG=ja_JP.UTF-8 >> .bashrc

    echo 'export PATH="$HOME/.node_modules/bin:$PATH"' >> .bashrc
    echo "prefix=/home/${HOST_USER}/.node_modules" >> .npmrc
    mkdir -p .node_modules/bin

    cd /tmp
    chown -R "${HOST_UID}:${HOST_GID}" temp_home
    chmod 700 temp_home

    cp -rp /tmp/temp_home/. /home/${HOST_USER}/.
    rm -rf /tmp/temp_home
fi

# code-server の設定ディレクトリ・設定ファイルを準備
# code-server は --bind-addr 等を CLI 引数で渡しても、自動生成される
# config.yaml のデフォルト値 (bind-addr: 127.0.0.1:8080) は書き換わらないため
# (実際の待受けは CLI 引数が優先され 0.0.0.0:8080 になるが、config.yaml の
# 表示だけが 127.0.0.1 のまま残り紛らわしい)、ここで config.yaml 自体に
# 正しい bind-addr を書き込み、CLI 引数には頼らないようにする。
# PASSWORD / HASHED_PASSWORD が環境変数で指定されている場合は、Secret を
# config.yaml に複製しない。未指定のローカル起動だけ、初回パスワードを
# 自動生成して config.yaml に書き込む (--auth none は使わない)。
CODE_SERVER_CONFIG_DIR="/home/${HOST_USER}/.config/code-server"
CODE_SERVER_CONFIG="${CODE_SERVER_CONFIG_DIR}/config.yaml"
mkdir -p "${CODE_SERVER_CONFIG_DIR}"
if [ ! -f "${CODE_SERVER_CONFIG}" ]; then
    cat > "${CODE_SERVER_CONFIG}" <<EOF
bind-addr: 0.0.0.0:8080
auth: password
cert: false
EOF

    if [ -z "${PASSWORD:-}" ] && [ -z "${HASHED_PASSWORD:-}" ]; then
        GENERATED_PASSWORD=$(head -c12 /dev/urandom | od -An -tx1 | tr -d ' \n')
        echo "password: ${GENERATED_PASSWORD}" >> "${CODE_SERVER_CONFIG}"
    fi
fi

# Azure Files (SMB) では uid/gid をマウントオプションで固定するため、所有者が
# 既に一致していれば chown を実行しない。ローカル bind mount では従来通り、
# root が作成した設定ディレクトリをユーザー所有へ変更する。
config_uid=$(stat -c "%u" "${CODE_SERVER_CONFIG_DIR}")
config_gid=$(stat -c "%g" "${CODE_SERVER_CONFIG_DIR}")
if [ "${config_uid}" -ne "${HOST_UID}" ] || [ "${config_gid}" -ne "${HOST_GID}" ]; then
    chown -R "${HOST_UID}:${HOST_GID}" "/home/${HOST_USER}/.config"
fi

# イメージに同梱した既定設定と拡張機能を、不足している場合だけ配置する。
/usr/local/bin/code-server-bootstrap-defaults.sh

echo "Home initialization complete for ${HOST_USER}."
