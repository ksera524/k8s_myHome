# Harbor insecure registry 問題の解決方法

## 問題
GitHub ActionsからHarborレジストリにpushする際の証明書エラー：
```
tls: failed to verify certificate: x509: cannot validate certificate for 192.168.122.100 because it doesn't contain any IP SANs
```

## 解決策
**craneツール + --insecureフラグ + DNS設定**

### 成功したコマンドシーケンス

```bash
# DNS解決設定
echo "192.168.122.100 harbor.local" | sudo tee -a /etc/hosts

# Craneツールインストール
curl -sL "https://github.com/google/go-containerregistry/releases/latest/download/go-containerregistry_Linux_x86_64.tar.gz" | tar xz -C /tmp
chmod +x /tmp/crane

# 認証
export CRANE_INSECURE=true
/tmp/crane auth login 192.168.122.100 -u admin -p Harbor12345 --insecure

# イメージプッシュ
docker save 192.168.122.100/sandbox/repo:latest -o /tmp/image.tar
/tmp/crane push /tmp/image.tar 192.168.122.100/sandbox/repo:latest --insecure
```

### 成功ログ例
```
2025/07/13 14:58:01 pushed blob: sha256:0325234e323fa0a4e9a411e65b9b087f5a96d212097e577fe4e1b0a276391a67
2025/07/13 14:58:03 192.168.122.100/sandbox/slack.rs:latest: digest: sha256:19bc26ec86995ab31ec7989f8365f7e8939d5dee430575214cffa58feeee79bf size: 915
```

## 重要なポイント

1. **DNS解決**: harbor.localへの名前解決が必要
2. **--insecureフラグ**: TLS証明書検証を無効化
3. **tarファイル方式**: docker saveしてからcrane pushが確実
4. **認証設定**: Docker config.jsonまたはcrane auth loginが必要

## GitHub Actions推奨設定

```yaml
- name: Harbor Push
  run: |
    echo "192.168.122.100 harbor.local" | sudo tee -a /etc/hosts
    curl -sL "https://github.com/google/go-containerregistry/releases/latest/download/go-containerregistry_Linux_x86_64.tar.gz" | tar xz -C /tmp
    chmod +x /tmp/crane
    export CRANE_INSECURE=true
    /tmp/crane auth login 192.168.122.100 -u admin -p Harbor12345 --insecure
    docker save 192.168.122.100/sandbox/${{ github.event.repository.name }}:latest -o /tmp/image.tar
    /tmp/crane push /tmp/image.tar 192.168.122.100/sandbox/${{ github.event.repository.name }}:latest --insecure
```

この方法でHarborへのinsecure pushが確実に成功します。