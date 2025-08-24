# k8s_myHome Automation Makefile
# リファクタリング版 - モジュール化されたMakefile

# シェルをbashに設定
SHELL := /bin/bash

# 共通設定とモジュールをインクルード
include makefiles/variables.mk
include makefiles/functions.mk
include makefiles/deployment.mk
include makefiles/operations.mk
include makefiles/maintenance.mk

# 全PHONYターゲット宣言
.PHONY: help all deploy host-setup infrastructure platform post-deployment setup-github-actions _setup-github-actions-conditional fix-github-oauth
.PHONY: add-runner setup-arc harbor-cert-fix setup-slack-secret load-settings
.PHONY: check-automation-readiness wait-for-k8s-cluster wait-for-external-secrets
.PHONY: status verify logs clean
.PHONY: dev-info dev-ssh dev-argocd dev-harbor
.PHONY: vm-deploy vm-k8s-deploy k8s-cluster k8s-infrastructure
.PHONY: phase1 phase2 phase3 phase4 phase2-3
.PHONY: _sudo-keepalive _sudo-cleanup _all-internal

# デフォルトターゲット - ヘルプ表示
help:
	@echo "$(ROCKET) k8s_myHome Automation Commands"
	@echo ""
	@echo "$(GEAR) 全自動デプロイ"
	@echo "  make all                 - 完全自動デプロイ (全ステップ)"
	@echo "  make deploy              - 完全自動デプロイ (allと同じ)"
	@echo ""
	@echo "$(INFO) ステップ別実行"
	@echo "  make host-setup          - ホストマシンセットアップ"
	@echo "  make infrastructure      - VM作成+Kubernetesクラスタ構築"
	@echo "  make platform            - Kubernetesプラットフォーム構築"
	@echo ""
	@echo "$(ROCKET) 個別操作"
	@echo "  make add-runner REPO=<name>  - GitHub Actions Runner追加"
	@echo "  make setup-arc               - Actions Runner Controller設定"
	@echo "  make harbor-cert-fix         - Harbor証明書修正"
	@echo "  make setup-slack-secret      - Slack Secret手動設定"
	@echo ""
	@echo "$(DEBUG) 状態確認・管理"
	@echo "  make status              - 全システム状態確認"
	@echo "  make verify              - 全フェーズ検証"
	@echo "  make logs                - 重要なログ表示"
	@echo "  make clean               - 全システムクリーンアップ"
	@echo ""
	@echo "$(GEAR) 開発用"
	@echo "  make dev-info            - 開発用情報表示"
	@echo "  make dev-ssh             - Control PlaneへSSH"
	@echo "  make dev-argocd          - ArgoCD Port Forward"
	@echo "  make dev-harbor          - Harbor Port Forward"
	@echo ""
	@echo "$(INFO) 使用例"
	@echo "  make all                 # 完全自動デプロイ"
	@echo "  make host-setup infrastructure  # ホストセットアップとインフラ構築のみ"
	@echo "  make add-runner REPO=my-project  # Runner追加"

# バージョン情報
version:
	@echo "k8s_myHome Automation Makefile"
	@echo "Version: 2.0 (Refactored)"
	@echo "Project: $(PROJECT_NAME)"
	@echo "Root: $(PROJECT_ROOT)"

# 設定確認
config:
	$(call print_section,$(INFO),設定情報)
	@echo "Project Root: $(PROJECT_ROOT)"
	@echo "Settings File: $(SETTINGS_FILE)"
	@echo "K8s Control Plane: $(K8S_CONTROL_PLANE_IP)"
	@echo "K8s Workers: $(K8S_WORKER_1_IP), $(K8S_WORKER_2_IP)"
	@echo "Harbor Namespace: $(HARBOR_NAMESPACE)"
	@echo "ArgoCD Namespace: $(ARGOCD_NAMESPACE)"
	@echo "ARC Namespace: $(ARC_NAMESPACE)"
	$(call print_section,$(CHECK),Makefileモジュール)
	@echo "Variables: $(wildcard makefiles/variables.mk)"
	@echo "Functions: $(wildcard makefiles/functions.mk)"
	@echo "Deployment: $(wildcard makefiles/deployment.mk)"
	@echo "Operations: $(wildcard makefiles/operations.mk)"
	@echo "Maintenance: $(wildcard makefiles/maintenance.mk)"

# クイックスタートガイド
quickstart:
	$(call print_section,$(ROCKET),k8s_myHome クイックスタートガイド)
	@echo "1. 初回セットアップ（全自動）:"
	@echo "   make all"
	@echo ""
	@echo "2. ステップ別実行:"
	@echo "   make host-setup"
	@echo "   make infrastructure"
	@echo "   make platform"
	@echo ""
	@echo "3. GitHub Actions Runner追加:"
	@echo "   make add-runner REPO=your-repo-name"
	@echo ""
	@echo "4. システム状態確認:"
	@echo "   make status"
	@echo ""
	@echo "5. 完全クリーンアップ:"
	@echo "   make clean"
	@echo ""
	$(call print_status,$(INFO),詳細は 'make help' または 'make dev-info' を参照)