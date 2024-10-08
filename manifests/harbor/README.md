## 各種コマンド
```bash
#証明書を取得
sudo kubectl get secrets -n harbor harbor-nginx -o jsonpath='{.data.ca\.crt}' | base64 -d | sudo tee /usr/share/ca-certificates/harbor/harbor.crt > /dev/null
#証明書の配置
echo harbor/harbor.crt | sudo tee -a /etc/ca-certificates.conf
#証明書の読み込み
sudo update-ca-certificates
#再起動
sudo systemctl restart docker
sudo systemctl restart k3s
```

## 参考
1. [helmでHarbor](https://zenn.dev/t_ume/articles/a8ff4b41286f05)