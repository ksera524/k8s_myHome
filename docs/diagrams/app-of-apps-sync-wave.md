# App-of-Apps 依存関係と Sync Wave

ArgoCD の App-of-Apps 構成と Sync Wave の関係を 1 枚で把握するための図です。
`manifests/bootstrap/app-of-apps.yaml` の定義を基準にしています。

## 依存関係図

```mermaid
flowchart TD
  root["Root Application\nbootstrap/app-of-apps.yaml"]:::root

  argocdProjects["ArgoCD Projects\nwave 0"]:::wave0

  lp["Local Path Provisioner\nwave 1"]:::wave1
  core["Core (Namespaces/Storage/RBAC)\nwave 2"]:::wave2
  coredns["CoreDNS Config\nwave 2"]:::wave2

  metallb["MetalLB\nwave 3"]:::wave3
  metallbCfg["MetalLB Config\nwave 4"]:::wave4
  gwApi["Gateway API CRD\nwave 5"]:::wave5
  ngf["NGINX Gateway Fabric\nwave 6"]:::wave6
  certmgr["cert-manager\nwave 7"]:::wave7
  certcfg["cert-manager Config\nwave 7"]:::wave7
  eso["External Secrets Operator\nwave 7"]:::wave7
  gwRes["Gateway Resources\nwave 8"]:::wave8
  cfgSecrets["External Secrets Definitions\nwave 9"]:::wave9
  platform["Platform\nwave 10"]:::wave10
  imgUpdater["ArgoCD Image Updater\nwave 10"]:::wave10
  harbor["Harbor\nwave 10"]:::wave10
  tailscaleOp["Tailscale Operator\nwave 10"]:::wave10
  monitoring["Monitoring\nwave 11"]:::wave11
  userDefs["User App Definitions\nwave 11"]:::wave11
  tailscaleConn["Tailscale Connector\nwave 11"]:::wave11
  userApps["User Applications\nwave 12"]:::wave12
  harborPatch["Harbor Patch\nwave 13"]:::wave13

  root --> argocdProjects
  root --> lp
  root --> core
  root --> coredns
  root --> metallb
  root --> metallbCfg
  root --> gwApi
  root --> ngf
  root --> certmgr
  root --> certcfg
  root --> eso
  root --> gwRes
  root --> cfgSecrets
  root --> platform
  root --> imgUpdater
  root --> harbor
  root --> tailscaleOp
  root --> monitoring
  root --> userDefs
  root --> tailscaleConn
  root --> userApps
  root --> harborPatch

  argocdProjects --> lp
  argocdProjects --> core

  core --> metallb
  metallb --> metallbCfg
  metallbCfg --> gwApi
  gwApi --> ngf
  ngf --> certmgr
  certmgr --> gwRes
  eso --> cfgSecrets
  cfgSecrets --> tailscaleOp
  cfgSecrets --> monitoring
  gwRes --> platform
  gwRes --> imgUpdater
  gwRes --> harbor
  tailscaleOp --> tailscaleConn
  platform --> monitoring
  monitoring --> userDefs
  userDefs --> userApps
  userApps --> harborPatch

  subgraph user_definitions["User App Definitions (wave 11)"]
    uad_argocd["argocd-external"]:::wave11
    uad_rustfs["rustfs"]:::wave11
    uad_rustfs_ext["rustfs-external"]:::wave11
    uad_cloudflared["cloudflared"]:::wave11
    uad_hitomi["hitomi"]:::wave11
    uad_slack["slack"]:::wave11
    uad_selenium["selenium"]:::wave11
  end

  userDefs --> user_definitions

  subgraph user_applications["User Applications (wave 12)"]
    ua_argocd["argocd"]:::wave12
    ua_rustfs["rustfs"]:::wave12
    ua_cloudflared["cloudflared"]:::wave12
    ua_hitomi["hitomi"]:::wave12
    ua_slack["slack"]:::wave12
    ua_selenium["selenium"]:::wave12
  end

  userApps --> user_applications

  classDef root fill:#f2f4f7,stroke:#475467,stroke-width:1px,color:#101828
  classDef wave0 fill:#f5f3ff,stroke:#6d28d9,stroke-width:1px,color:#3b0764
  classDef wave1 fill:#ecfdf3,stroke:#027a48,stroke-width:1px,color:#054f31
  classDef wave2 fill:#eaf2ff,stroke:#175cd3,stroke-width:1px,color:#102a56
  classDef wave3 fill:#fff6ed,stroke:#c4320a,stroke-width:1px,color:#7a2e0e
  classDef wave4 fill:#fef3c7,stroke:#b45309,stroke-width:1px,color:#78350f
  classDef wave5 fill:#fef9c3,stroke:#a16207,stroke-width:1px,color:#713f12
  classDef wave6 fill:#e0f2fe,stroke:#0369a1,stroke-width:1px,color:#0c4a6e
  classDef wave7 fill:#ecfeff,stroke:#0e7490,stroke-width:1px,color:#0e3a45
  classDef wave8 fill:#e5e7eb,stroke:#374151,stroke-width:1px,color:#111827
  classDef wave9 fill:#eef2ff,stroke:#4338ca,stroke-width:1px,color:#312e81
  classDef wave10 fill:#f1f5f9,stroke:#334155,stroke-width:1px,color:#0f172a
  classDef wave11 fill:#f0fdf4,stroke:#166534,stroke-width:1px,color:#14532d
  classDef wave12 fill:#eff6ff,stroke:#1d4ed8,stroke-width:1px,color:#1e3a8a
  classDef wave13 fill:#fffbeb,stroke:#92400e,stroke-width:1px,color:#78350f
```

## Sync Wave 一覧と意味

| Wave | コンポーネント | 意味/依存関係 |
|------|----------------|--------------|
| 0 | ArgoCD Projects | AppProjectを先に作成 |
| 1 | Local Path Provisioner | 永続ボリューム基盤を先に準備 |
| 2 | Core / CoreDNS | 基本リソースとストレージ設定の土台 |
| 3 | MetalLB | LoadBalancer を提供 |
| 4 | MetalLB Config | IP プール設定を適用 |
| 5 | Gateway API CRD | Gateway API の CRD を先行適用 |
| 6 | NGINX Gateway Fabric | Gateway コントローラー本体 |
| 7 | cert-manager / cert-manager Config / External Secrets Operator | 証明書/Secret 管理を整備 |
| 8 | Gateway Resources | Gateway/共通設定を適用 |
| 9 | External Secrets Definitions | 外部連携用のExternalSecretを適用 |
| 10 | Platform / ArgoCD Image Updater / Harbor / Tailscale Operator | 基盤サービス群の展開 |
| 11 | Monitoring | 監視スタック（Grafana k8s-monitoring） |
| 11 | User App Definitions | ArgoCD Application 定義を作成 |
| 11 | Tailscale Connector | サブネットルータ（k8s内ネットワーク公開） |
| 12 | User Applications | 実アプリのマニフェスト適用 |
| 13 | Harbor Patch | Harbor 後処理パッチ |

## 参照

- `manifests/bootstrap/app-of-apps.yaml`
- `manifests/bootstrap/applications/user-apps/`
