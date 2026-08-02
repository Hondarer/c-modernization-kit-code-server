# Oracle Linux 8.10 への Azure CLI セットアップ

MicrosoftのRPMリポジトリから`dnf`を使ってAzure CLIをインストールします。

## 対象環境

対象はx86_64版Oracle Linux 8です。Microsoftの公式手順はRHEL 8を対象としているため、
RHEL 8向けのEL8 RPMを利用します。導入可能な最新版と依存関係は`dnf`に解決させます。

環境を確認します。

```bash
cat /etc/os-release
uname -m
dnf --version
```

## インストール

この操作には `sudo` 権限と、`https://packages.microsoft.com` への接続が必要です。

1. Microsoft リポジトリの署名鍵をインポートします。

   ```bash
   sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc
   ```

2. Microsoft の RHEL 8 向けリポジトリ設定を追加します。

   ```bash
   sudo dnf install -y \
       https://packages.microsoft.com/config/rhel/8/packages-microsoft-prod.rpm
   ```

3. 利用可能なAzure CLIパッケージを確認します。

   ```bash
   dnf list --showduplicates azure-cli
   ```

4. Azure CLIをインストールします。Python 3.12などの依存パッケージも `dnf` が同時に解決します。

   ```bash
   sudo dnf install -y azure-cli
   ```

## 動作確認

インストールされたパッケージとAzure CLIのバージョンを確認します。

```bash
rpm -q azure-cli python3.12
az version
```

両パッケージのバージョンが表示され、`az version` がエラーなくJSONを出力すればセットアップ完了です。

## Azureへのログイン

ブラウザを直接起動しにくいcode-server環境では、デバイスコード認証を利用します。

```bash
az login --use-device-code
```

コマンドに表示されたURLをブラウザで開き、同じく表示されたコードを入力します。ログイン後は次のコマンドで選択中のサブスクリプションを確認できます。

```bash
az account show --output table
```

ログイン状態が失効した場合も、同じ `az login --use-device-code` を再実行します。

Azure CLIの認証情報や設定は `$HOME/.azure` に保存されます。このディレクトリをGitへ追加したり、他の利用者と共有したりしないでください。

Container Apps管理には拡張機能を導入します。

```bash
az extension add --name containerapp --upgrade
```

`aca-instance.sh suspend/resume`は通常App用のstable REST APIをAzure CLI本体の`az rest`で
呼び出します。`az containerapp job start/stop`はJob専用のため代用できません。追加SDKの
導入は不要です。

管理スクリプトは通常の拡張機能警告を抑制します。診断時に警告を含む全出力を確認する
場合は、対象コマンドへ`AZURE_CORE_ONLY_SHOW_ERRORS=false`を付けます。

## 更新

Microsoft リポジトリからAzure CLIを更新します。

```bash
sudo dnf update -y azure-cli
az version
```

## アンインストール

Azure CLI本体を削除する場合は、次のコマンドを実行します。

```bash
sudo dnf remove azure-cli
```

Microsoft リポジトリを他のパッケージでも利用している可能性があるため、`packages-microsoft-prod` は通常そのまま残します。不要であることを確認できた場合に限り、次のコマンドで削除します。

```bash
sudo dnf remove packages-microsoft-prod
```

認証情報も不要な場合は、`$HOME/.azure` の内容を確認してから手動で削除してください。

## 参考資料

- [Linux に Azure CLI をインストールする - Microsoft Learn](https://learn.microsoft.com/ja-jp/cli/azure/install-azure-cli-linux?view=azure-cli-latest)
- [Installing Python - Oracle Linux 8](https://docs.oracle.com/en/operating-systems/oracle-linux/8/python/python-InstallingPython.html)
