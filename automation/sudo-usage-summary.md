# sudo使用箇所サマリー

このドキュメントは、automation/配下でsudoコマンドを使用している主な箇所をまとめたものです。
すべてのsudoコマンドは`sudo -n`に変更され、パスワードプロンプトが表示されないようになっています。

## 主なsudo使用箇所

### 1. ホストセットアップ (host-setup/)

#### setup-host.sh
- パッケージ管理: apt update/upgrade、各種ツールインストール
- サービス管理: libvirtd、docker の起動・有効化
- ユーザー権限: libvirt、kvm、docker グループへの追加
- 証明書管理: GPGキーの追加、リポジトリの設定

#### setup-storage.sh
- ディスク管理: parted、mkfs.ext4 でのパーティション作成・フォーマット
- マウント管理: fstab編集、マウントポイント作成
- NFS設定: exportfs、nfs-kernel-server の設定・起動
- 権限設定: chown、chmod でのディレクトリ権限設定

#### verify-setup.sh
- NFSテスト: mount/umountコマンドでのNFS動作確認
- virsh操作: ネットワークの起動・自動起動設定

#### fix-missing-directories.sh
- ディレクトリ作成: mkdir でのストレージディレクトリ作成
- 権限修正: chown、chmod での権限設定
- NFS再設定: exportfs、systemctl でのNFS再設定

### 2. インフラストラクチャ (infrastructure/)

#### clean-and-deploy.sh
- VM管理: virsh list/destroy/undefine でのVM削除
- ファイル削除: /var/lib/libvirt/ 配下のイメージファイル削除
- AppArmor管理: systemctl stop/disable apparmor
- libvirt設定: qemu.conf の編集、pool管理
- サービス管理: libvirtd、virtlogd の再起動
- ネットワーク管理: virsh net-start/autostart

#### main.tf (Terraformプロビジョニング内)
※注意: これらはリモートVM内で実行されるため、-nオプションは不要
- パッケージインストール: apt、kubeadm、kubectl、kubelet
- システム設定: modprobe、sysctl
- containerd設定: config.toml の作成・編集
- kubeadm実行: クラスター初期化

### 3. プラットフォーム (platform/)

#### configure-insecure-registry.sh
- containerd設定: ディレクトリ作成、設定ファイル作成
- Docker設定: daemon.json の作成・編集
- サービス再起動: containerd、docker の再起動

#### platform-deploy.sh
- containerd設定: config.tomlのバックアップ・編集
- サービス再起動: containerd の再起動

## sudo権限が必要な主な操作カテゴリ

1. **パッケージ管理**
   - apt/apt-get によるパッケージインストール・更新
   - リポジトリ設定ファイルの編集

2. **サービス管理**
   - systemctl によるサービスの起動・停止・有効化
   - サービス設定ファイルの編集

3. **仮想化管理**
   - virsh によるVM・ネットワーク・プール管理
   - libvirt設定ファイルの編集

4. **ストレージ管理**
   - ディスクパーティション操作
   - マウント操作
   - NFS設定・エクスポート

5. **権限・セキュリティ管理**
   - ファイル・ディレクトリの所有者・権限変更
   - AppArmor設定の変更
   - ユーザーグループ管理

6. **コンテナランタイム設定**
   - containerd設定ファイルの編集
   - Docker daemon設定の編集

## sudo-keepalive.shについて

`automation/scripts/sudo-keepalive.sh`は、長時間実行されるデプロイメントプロセス中にsudo権限を維持するためのスクリプトです。
- 初回実行時のみ`sudo -v`でパスワード入力を求める（これは-nオプションを付けない唯一の箇所）
- バックグラウンドで50秒ごとに`sudo -n true`を実行して権限を維持
- make allプロセス完了後に自動停止