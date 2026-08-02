---
name: release-code-server-aca
description: 検証済み code-server image を ACR へ publish し、Running・Stopped 状態を持つ複数の利用者別 Azure Container Apps へ順次 rollout して認証・永続化を検証する。Azure release、image 更新、停止中 instance を含む rollout 時に使用する。
---

# Release code-server to ACA

## Preflight

1. `AGENTS.md`、`docs/code-server-defaults.md`、`docs/azure-container-apps-publish.md`、`docs/azure-container-apps-multi-instance.md` と関連 script を読む。
2. `git status --short`、`./aca-environment.sh doctor`、ローカル image の検証結果を確認する。
3. Azure へ変更する対象 instance と順序を明確にする。診断や説明だけの依頼では publish/update しない。

## Release Workflow

1. `./aca-environment.sh publish` で image を build して ACR に push し、一意な tag と digest を記録する。初回の大きな pull/push は数分かかり得るため、処理中に同じ command を重複実行しない。
2. 最初の instance だけを新 image へ更新する。
3. revision が正常になったこと、正しい password と誤った password の HTTP 応答、既存 marker、設定、拡張機能を確認する。
4. 最初の instance が合格した後でのみ次の instance を更新し、同じ検証を繰り返す。
5. 全 instance が新 digest で正常動作してから、不要な旧 ACR image の削除を検討する。
6. build でローカルコンテナが停止した場合は、必要に応じて `./start-pod.sh 1` で復旧する。

Stopped の instance は update を受け付けない。対象に含める場合は `resume`、`update`、検証の順に実行し、元の運用状態へ戻す必要があれば検証後に `suspend` する。停止中のまま旧 image を参照する instance を更新対象外にする場合、その image は保持する。

## Failure Handling

- 失敗した instance で停止し、後続 instance を更新しない。旧 image を削除しない。
- single revision 切替中は旧 revision が `Active`、traffic 0、`Deprovisioning` になる場合がある。新 revision の readiness と traffic を基準に判定する。
- `az containerapp exec` の 429 は待って再試行する。停止済み replica に対する 500 は現在の replica を取り直す。
- rollout で instance 固有の URL、password、file share を変更しない。
- lifecycle の受付操作は `docs/azure-container-apps-multi-instance.md` の状態表に従い、Stopped や Progressing の instance へ update を強行しない。

## Completion Criteria

- 対象 instance が同一の意図した image digest を参照する。
- 更新対象外の Stopped instance が参照する旧 image を ACR に保持する。
- 各 instance の認証分離と永続データが維持される。
- 実 URL、password、subscription 情報などの一時値を tracked docs に残さない。
