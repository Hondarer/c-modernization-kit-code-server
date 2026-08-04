---
name: manage-aca-instances
description: 利用者ごとに固有 URL、password、Azure Files share を持つ code-server Container App を作成・確認・更新・休止・再開・永続データ取得・初期化・password rotation・削除する。単純な replica 増加ではない分離 instance やライフサイクル状態を扱うときに使用する。
---

# Manage ACA Instances

## Workflow

1. `AGENTS.md`、`docs/azure-container-apps-multi-instance.md`、`docs/azure-container-apps-persistent.yaml.template`、`aca-instance.sh` を読む。
2. `./aca-environment.sh doctor` で共有基盤と CLI 前提を確認する。
3. instance slug が script の制約を満たし、既存利用者と衝突しないことを確認する。
4. `./aca-instance.sh create <slug>` で、1利用者につき1 Container App、1 password、1 file share を作成する。
   必要なら明示オプションで固定1 replicaまたはHTTP scale-to-zeroを選択する。
   AppのCPU・memoryは外部configから適用し、既定は4.0 vCPU / 8Giとする。init Jobは
   1.0 vCPU / 2Giのままにする。
5. 変更前に `show` または `list` で provisioning/running status を確認し、受付可能な操作を `docs/azure-container-apps-multi-instance.md` の状態表で判断する。
6. 未利用時は `suspend`、再利用時は `resume` を使う。Stopped の instance を他の command で暗黙に起動しない。
7. 更新は instance ごとに順番に行う。Stopped の instance は明示的に resume してから更新し、検証後に必要なら再度 suspend する。
8. 永続データをローカルへ退避するときは`download <slug> [PATH]`を使う。整合性が必要なら先に`suspend`し、完了後に必要なら`resume`する。
9. 利用者環境全体の初期化は、必要なら`download`した後、Stoppedで`reset <slug>`を実行する。reset後もStoppedであり、次の明示的な`resume`でAppの現在イメージに同梱されたdefaultsを適用する。
10. password 変更は `rotate-password`、削除は `delete` の専用操作を使う。

## Verification

- 正しい password の `/login` が HTTP 302、誤った password と他 instance の password が HTTP 200 になることを確認する。
- instance ごとの marker file が再起動後も残り、別 instance から見えないことを確認する。
- revision mode はsingle、max replicaは1であることを確認する。スケーリング無効時はmin 1、
  有効時は設定したmin/cooldownとHTTP rule、現在のreplica数を確認する。
- AppのCPU・memoryが外部configの目標値と一致し、init Jobが1.0 vCPU / 2Giであることを確認する。
- `list`の`Running / 0 replicas`はscale-to-zeroであり、明示的な`Stopped`とは区別する。
- suspend 後は `Succeeded / Stopped`、resume 後は `Succeeded / Running` と `/healthz` 成功を確認する。resume 後も marker file が保持されることを確認する。
- downloadしたtar.gzがmode 600で、`home/`と`workspace/`の両方を含むことを確認する。これは論理的な内容のexportであり、Azure Filesのsnapshotやmetadata backupとして扱わない。
- resetは`Succeeded / Stopped`でだけ実行し、`reset <slug>`の確認を省略しない。Appを自動起動せず、空の`home`と`workspace`を再作成したことを確認する。
- `az containerapp exec` は TTY を要求する。429 は一時的制限として待って再試行し、停止済み replica の 500 は新しい replica を特定して再試行する。

## Secret Handling

- `list` と `show` は password を表示し得る。共有ログ、CI ログ、ドキュメント作成目的では実行しない。
- URL と password の実値は tracked file に書かない。
- downloadではstorage keyを引数やログに出さず、既存の出力先を上書きしない。生成されたarchiveにも利用者データが含まれるため共有や保管先を制限する。
- resetは自動backupもrollbackも行わない。途中失敗時はStoppedを維持し、原因解消後に同じresetを再実行する。
- 削除前に正確な instance slug と対象 App/share を確認し、script の完全一致確認を省略しない。
