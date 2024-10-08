## 各種コマンド
```bash
#cert-manager によって管理される SSL/TLS 証明書を確認
kubectl get certificates
#新しい証明書の発行や更新のリクエストを確認
kubectl get certificaterequests
#ドメインの所有権を証明するために cert-manager が作成するチャレンジを確認
kubectl get challenges
```