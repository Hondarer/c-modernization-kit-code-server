# ドキュメント

Azure Container Appsへの公開は、次の順番で参照します。

1. [Azure CLIセットアップ](azure-cli-setup.md)
2. [Azure Container Apps公開・運用](azure-container-apps-publish.md)
3. [Azure Container Apps複数利用者運用](azure-container-apps-multi-instance.md)
4. [code-serverの既定設定と拡張機能](code-server-defaults.md)

ランブックから使用する再現用ファイル:

- [`azure-container-apps.env.example`](azure-container-apps.env.example):
  リソース名をシェル間で再利用するための変数ファイル。Secretは含まない。
- [`azure-container-apps-persistent.yaml.template`](azure-container-apps-persistent.yaml.template):
  `/home/user`と`/workspace`をAzure Filesへ永続化するContainer App定義。
- [`../aca-instance.sh`](../aca-instance.sh):
  URL、パスワード、永続領域が独立したAppをスラッグ単位で作成・休止・再開・管理するCLI。
- [`../aca-environment.sh`](../aca-environment.sh):
  共有Azure基盤の初期化、作成、イメージ公開、監査、削除を行うCLI。

実際のAzure CLI認証情報、公開用パスワード、展開済み変数ファイルは
`$HOME/.azure`に置き、リポジトリには追加しません。

## Agent向けタスク経路

| 目的 | Skill | 主な文書 |
|---|---|---|
| ローカルイメージのbuild・検証 | `build-code-server-image` | `code-server-defaults.md` |
| Azure共有基盤の管理 | `manage-aca-environment` | `azure-container-apps-publish.md` |
| 利用者別Appの管理 | `manage-aca-instances` | `azure-container-apps-multi-instance.md` |
| Azureへの新image展開 | `release-code-server-aca` | 上記Azure文書2件 |

全タスクで`../AGENTS.md`の不変条件と安全規則を優先します。
