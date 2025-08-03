# Phase 1: 各種アプリケーションinstall

Ubuntu 24.04 LTSホストマシンでk8s環境構築のための準備スクリプト集

## スクリプト一覧

### 1. setup-host.sh
ホストマシンの基本セットアップを行います。

**実行内容:**
- システムパッケージの更新
- QEMU/KVM + libvirtのインストール
- 開発・自動化ツールのインストール（Terraform, Ansible, Docker, kubectl, Helm）
- ユーザーの必要なグループへの追加
- 各種サービスの有効化と開始
- 仮想化サポートの確認
- **Helmセットアップ（新規）**: Helmインストールと共通repositoryの追加

**実行方法:**
```bash
chmod +x automation/scripts/setup-host.sh
./automation/scripts/setup-host.sh
```

**実行後の注意:**
- ログアウト・ログインしてグループメンバーシップを更新する必要があります

### 2. setup-storage.sh
外部USB ストレージの設定を行います。

**実行内容:**
- USB外部ストレージデバイスの検出
- パーティション作成（必要に応じて）
- 永続マウント設定（/etc/fstab）
- k8s用ディレクトリ構造の作成
- NFSサーバーのインストールと設定
- 各アプリケーション用ディレクトリの作成

**実行方法:**
```bash
chmod +x automation/scripts/setup-storage.sh
./automation/scripts/setup-storage.sh
```

**注意事項:**
- 外部USBストレージが接続されている必要があります
- 対話式でストレージデバイスを選択します
- データが消失する可能性があるため、重要なデータのバックアップを取ってください

### 3. verify-setup.sh
Phase 1のセットアップが正常に完了したかを検証します。

**検証項目:**
- 必要なパッケージのインストール確認
- 仮想化サポートの確認
- サービスの動作確認
- ユーザー権限の確認
- ストレージ設定の確認
- NFS設定の確認
- ネットワーク接続の確認

**実行方法:**
```bash
chmod +x automation/scripts/verify-setup.sh
./automation/scripts/verify-setup.sh
```

**出力:**
- 検証結果のコンソール出力
- 詳細なレポートファイル（/tmp/k8s-setup-readiness-*.txt）

### 4. setup-helm.sh
Helmとよく使用されるHelm repositoryのセットアップを行います。

**実行内容:**
- ローカルホストとKubernetesクラスターでのHelmインストール
- External Secrets、Harbor、Actions Runner ControllerのHelmリポジトリ追加
- リポジトリ情報の更新

**実行方法:**
```bash
./automation/host-setup/setup-helm.sh
```

**注意事項:**
- setup-host.sh実行時に自動実行されます
- Kubernetesクラスターが稼働していない段階では警告が表示されますが正常です

### 5. fix-missing-directories.sh
setup-storage.sh実行後に不足していた設定を補う修正スクリプトです。

**実行内容:**
- 不足ディレクトリの作成
- 正しい権限設定
- NFSエクスポート設定の確認・修正
- libvirtdサービスの確認・起動

**実行方法:**
```bash
chmod +x automation/scripts/fix-missing-directories.sh
./automation/scripts/fix-missing-directories.sh
```

## 実行順序

1. **setup-host.sh** を実行
2. ログアウト・ログイン（グループメンバーシップ更新）
3. **setup-storage.sh** を実行
4. **verify-setup.sh** で検証
5. 問題があれば **fix-missing-directories.sh** で修正

## ディレクトリ構造

セットアップ完了後、以下のディレクトリ構造が作成されます：

```
/mnt/k8s-storage/
├── nfs-share/                 # NFS共有ディレクトリ
├── local-volumes/             # ローカルボリューム用
│   ├── factorio/
│   ├── cloudflared/
│   ├── hitomi/
│   ├── pepup/
│   ├── rss/
│   ├── s3s/
│   └── slack/
└── k8s-storage-config.yaml    # ストレージ設定情報
```

## 次のステップ

Phase 1完了後は、Phase 2（VM構築）に進みます：

```bash
cd automation/terraform
terraform init
terraform plan
terraform apply
```

## トラブルシューティング

### よくある問題

1. **仮想化が有効でない**
   - BIOS/UEFIで仮想化機能を有効にする
   - Intel VT-x / AMD-V の確認

2. **グループメンバーシップが反映されない**
   - ログアウト・ログインが必要
   - または `newgrp libvirt && newgrp docker` を実行

3. **ストレージデバイスが認識されない**
   - `lsblk` や `fdisk -l` でデバイス確認
   - USBデバイスの再接続

4. **NFS設定が失敗する**
   - ファイアウォール設定の確認
   - `/etc/exports` の設定確認

### ログ確認

```bash
# サービス状態確認
systemctl status libvirtd
systemctl status docker
systemctl status nfs-kernel-server

# ログ確認
journalctl -u libvirtd
journalctl -u docker
journalctl -u nfs-kernel-server
```