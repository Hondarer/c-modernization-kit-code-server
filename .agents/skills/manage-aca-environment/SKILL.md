---
name: manage-aca-environment
description: code-server 用 Azure Container Apps 共有基盤の初期化、作成、診断、監査、削除を aca-environment.sh で安全に行う。resource group、ACR、environment、storage のライフサイクルを扱うときに使用する。
---

# Manage ACA Environment

## Workflow

1. `AGENTS.md`、`docs/azure-cli-setup.md`、`docs/azure-container-apps-publish.md`、`docs/azure-container-apps.env.example`、`aca-environment.sh` を読む。
2. `git status --short` を確認し、設定ファイルや既存変更を保全する。
3. 状態確認だけなら `./aca-environment.sh doctor` を使い、外部状態を変更しない。
4. 設定がまだ無い場合だけ `./aca-environment.sh init` を使う。生成される秘密情報を含む設定はリポジトリ外の既定パスに保持する。
5. 共有基盤の作成には `./aca-environment.sh create` を使い、再実行可能性を維持する。
6. 作成後に resource group、ACR、Container Apps environment、Azure Files storage、必須 tag を確認する。

## Destructive Operations

- 削除前に対象 subscription、resource group、関連 app と storage を読み取り操作で列挙する。
- script が要求する完全一致の確認文字列をユーザー自身から得る。推測や自動入力をしない。
- Azure の resource group 削除は非同期であり `Deleting` が続く場合がある。ローカルの待機を中断しても Azure 側の削除要求は取り消されないと説明する。
- `--purge-local-state` は秘密情報を含むローカル設定も削除するため、明示要求がある場合だけ使う。

## Safety Rules

- password、接続文字列、現在の URL を tracked document やログへ転記しない。
- Azure CLI の `containerapp` extension を明示的に管理し、必要なら warning suppression を限定的に設定する。
- Azure への変更はユーザーが作成・更新・削除を依頼した範囲に限定する。
