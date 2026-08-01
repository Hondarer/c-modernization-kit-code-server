# c-modernization-kit-code-server

[oracle-linux-container](https://github.com/hondarer/oracle-linux-container) の開発コンテナに
[code-server](https://github.com/coder/code-server) (ブラウザ経由の VS Code) を追加する PoC (Proof of Concept) リポジトリです。

短期目標として、code-server を含む追加イメージをローカルで生成・実行し、Web ブラウザから接続できることを確認します。

## 前提条件

- Podman が利用可能であること
- [oracle-linux-container](https://github.com/hondarer/oracle-linux-container) をローカルに clone し、
  `./build-pod.sh 8` を実行して `oracle-linux-8` イメージがビルド済みであること

```bash
podman images | grep oracle-linux-8
```

上記でイメージが表示されない場合は、先に oracle-linux-container 側でビルドしてください。

現時点では Oracle Linux 8 のみを対象としています。SSH アクセスは提供しません (code-server の Web UI のみ)。

## ビルド

```bash
./build-pod.sh
```

`oracle-linux-8` をベースに、code-server (standalone インストール) を追加したイメージ `code-server-ol8` をビルドします。

## 起動

```bash
./start-pod.sh [instance_num]
```

- `instance_num` を省略すると `1` として扱われます。複数インスタンスを起動する場合に指定してください。
- ホームディレクトリとワークスペースは `./storage/<instance_num>/home_<user>` と `./storage/<instance_num>/workspace` にマウントされます。
- 接続ポートは `8080 + (instance_num - 1)` です (インスタンス 1 なら `8080`)。

## パスワードの確認

code-server は初回起動時にパスワードを自動生成し、コンテナ内の `~/.config/code-server/config.yaml` に書き込みます。以下のコマンドで確認できます (起動直後は数秒待ってから実行してください)。

```bash
podman exec code-server-ol8_1 cat /home/$USER/.config/code-server/config.yaml
```

`password:` フィールドの値がログインパスワードです。

## ブラウザから接続

ブラウザで以下にアクセスし、上記で確認したパスワードでログインします。

```
http://localhost:8080
```

## 停止

```bash
./stop-pod.sh [instance_num]
```

## 動作確認 (CLI のみ)

ブラウザを使わずに疎通確認したい場合は以下を利用できます。

```bash
# コンテナが起動しているか
podman ps | grep code-server-ol8_1

# エントリーポイントのログ (ユーザー作成〜code-server 起動まで)
podman logs code-server-ol8_1

# code-server プロセスが root ではなく指定ユーザーで動いているか
podman exec code-server-ol8_1 ps -ef | grep code-server

# HTTP での疎通確認 (200 が返れば OK)
curl -sS -o /dev/null -w '%{http_code}\n' http://localhost:8080/login
```

## 既知の制約・将来拡張

- SSH アクセスは未対応です。必要であれば `src/code-server-entrypoint.sh` の code-server 起動前に
  `/usr/sbin/sshd -D &` を追加することで併用できます。
- Oracle Linux 8 のみを対象としています。oracle-linux-container のようなバージョン切り替え (OL8/OL10) には対応していません。
- HTTP 平文での通信のみです。`localhost` での利用を前提としており、外部公開する場合は別途 TLS 終端 (リバースプロキシ等) を用意してください。
