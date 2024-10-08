# install
```bash
curl -sfL https://get.k3s.io | sh -
```

# 確認
```bash
sudo systemctl status k3s
```

# k3s kubectl
```bash
sudo k3s kubectl get nodes
```

# kubectl設定
```bash
sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
sudo chown $USER:$USER ~/.kube/config
chmod 600 ~/.kube/config
cat ~/.kube/config | grep server # serverの値がhttps://127.0.0.1:6443のはず
export KUBECONFIG=~/.kube/config
kubectl get nodes
```