# code-serverの既定設定と拡張機能

初回のcode-serverプロセス起動時に、コンテナイメージへ同梱した設定と拡張機能を展開
します。コンテナ起動時のMarketplace接続は必要ありません。

## 既定設定

`src/code-server-defaults/User/settings.json`で管理します。

```json
{
  "workbench.colorTheme": "Visual Studio Dark - C++",
  "security.workspace.trust.enabled": false
}
```

code-serverのlocaleは起動引数で強制しません。日本語Language Packは初期拡張として
同梱しますが、表示言語は利用者がcode-serverの表示言語選択機能から変更します。選択内容
は利用者ごとの永続ホームへ保存されます。

## 拡張機能マニフェスト

`src/code-server-defaults/extensions.txt`へ1行に1拡張を記載します。空行と`#`以降は
無視されます。

```text
# build時点の互換最新版
MS-CEINTL.vscode-language-pack-ja

# 指定した版
ms-vscode.cpptools-themes@2.0.0
```

指定形式は次の2種類です。

| 形式 | 動作 |
|---|---|
| `publisher.extension` | code-serverがbuild時点の最新安定・互換版を解決する |
| `publisher.extension@version` | 指定版を解決し、版が一致しなければbuildを失敗させる |

バージョン未指定のエントリは、同じソースから将来buildした場合に解決版が変わる可能性が
あります。一方、完成したイメージには`resolved-extensions.txt`、VSIX、`SHA256SUMS`が
保存されるため、コンテナ起動時の内容は固定されます。

`Visual Studio Dark - C++`は`ms-vscode.cpptools-themes`が提供します。

## buildと起動

`build-pod.sh`は公開ベースイメージ
`ghcr.io/hondarer/oracle-linux-container/oracle-linux-8-dev:latest`を毎回pullします。
取得時のdigestからbuildするため、処理中に`latest`が移動しても同じbuild内ではベースが
変わりません。完成イメージには次のOCIラベルを記録します。

- `org.opencontainers.image.base.name`: digest付きの完全なimage参照
- `org.opencontainers.image.base.digest`: 解決済みの`sha256` digest

ベースの`latest`はbuild間で変化します。完成したcode-serverイメージは不変tag、image
digest、上記base digestの組み合わせで追跡します。

Docker buildでは次を行います。

1. ID、任意のversion、重複を検証する。
2. code-server自身の拡張機能resolverで互換版を決定する。
3. Open VSXから解決済み版のVSIXを取得し、メタデータとSHA-256を記録する。
4. 一時領域へVSIXを再インストールし、IDとversionを検証する。
5. 解決済みマニフェストとVSIXを`/opt/code-server-defaults`へ同梱する。

## 初回初期化

利用者の
`/home/user/.local/share/code-server/User/settings.json`を初期化完了マーカーとして扱います。

| 起動時の状態 | 動作 |
|---|---|
| `settings.json`が存在する | 設定内容、拡張manifest、導入済み拡張を確認せず、初期化処理全体をスキップする |
| `settings.json`が存在しない | イメージ内VSIXから不足拡張を導入・検証し、最後に既定`settings.json`を配置する |

`settings.json`を最後に配置するため、拡張機能の導入や検証に失敗した場合は未初期化状態の
ままとなり、次回のcode-serverプロセス起動で再試行します。初期化完了後は、利用者が
既定拡張を削除しても自動では再導入しません。また、manifestから拡張を削除して新しい
イメージを配布しても、既存利用者の拡張を自動アンインストールしません。

既定値の内容を変更する場合の通常の変更スコープは次の2ファイルです。

- 設定: `src/code-server-defaults/User/settings.json`
- 初期拡張の追加・削除・version変更: `src/code-server-defaults/extensions.txt`

変更後はイメージを再buildします。初期化処理自体の仕様を変更しない限り、runtime scriptの
変更は不要です。

## 検証

```bash
./build-pod.sh
./verify-defaults.sh
```

検証用コンテナは一時ホームを使用し、`--network none`で起動します。次を確認します。

- settings.jsonの初期配置
- 解決済みマニフェストとインストール版の一致
- VSIXのSHA-256
- 日本語Language Packとテーマの提供、およびlocaleを起動引数で強制していないこと
- 既存のclang-formatとgit-clang-formatを維持し、clangdを追加しないこと
- GHCRベース名とdigestラベルが一致すること

初期化を一度だけ実行するゲートは、次の単体テストで検証します。

```bash
./tests/code-server-bootstrap-defaults-test.sh
```

通常のローカル環境は次のコマンドで確認します。

```bash
./start-pod.sh 1
```

既存環境へ既定設定と不足する初期拡張を再適用する場合は、利用者自身が必要な内容を
バックアップしてから`settings.json`を削除し、code-serverプロセスを起動し直します。
ローカルではコンテナ再起動、AzureではRunning中なら`suspend`から`resume`、Stoppedなら
`resume`、またはRevision再起動が該当します。ブラウザの再接続だけでは初期化処理は
実行されません。

Azure上で`home`と`workspace`を含む利用者環境全体を空にする場合は、Stopped状態で
`./aca-instance.sh reset <slug>`を実行します。resetは空ディレクトリの再作成までを行い、
Appを起動しません。次回`resume`時に、Appへ現在割り当てられているイメージ内のVSIXと
設定を使ってこの初回初期化処理が実行されます。
