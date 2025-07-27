# k8s_myHome Automation Makefile
# 全自動デプロイとフェーズ別実行コマンド

# カラー定義
GREEN := \033[0;32m
YELLOW := \033[1;33m
RED := \033[0;31m
NC := \033[0m

# 設定
PROJECT_ROOT := $(shell pwd)
HOST_SETUP_DIR := $(PROJECT_ROOT)/host-setup
INFRASTRUCTURE_DIR := $(PROJECT_ROOT)/infrastructure
PLATFORM_DIR := $(PROJECT_ROOT)/platform

.PHONY: help all deploy host-setup infrastructure platform vm-deploy vm-k8s-deploy k8s-cluster k8s-infrastructure clean verify status logs check-automation-readiness wait-for-k8s-cluster wait-for-external-secrets

# デフォルトターゲット
help:
	@echo "$(GREEN)k8s_myHome Automation Commands$(NC)"
	@echo ""
	@echo "$(YELLOW)■ 全自動デプロイ$(NC)"
	@echo "  make all                 - 完全自動デプロイ (全ステップ)"
	@echo "  make deploy              - 完全自動デプロイ (allと同じ)"
	@echo ""
	@echo "$(YELLOW)■ ステップ別実行$(NC)"
	@echo "  make host-setup          - ホストマシンセットアップ"
	@echo "  make infrastructure      - VM作成+Kubernetesクラスタ構築"
	@echo "  make platform            - Kubernetesプラットフォーム構築"
	@echo ""
	@echo "$(YELLOW)■ 個別操作$(NC)"
	@echo "  make add-runner REPO=<name>  - GitHub Actions Runner追加"
	@echo "  make setup-arc               - Actions Runner Controller設定"
	@echo "  make harbor-cert-fix         - Harbor証明書修正"
	@echo ""
	@echo "$(YELLOW)■ 状態確認・管理$(NC)"
	@echo "  make status              - 全システム状態確認"
	@echo "  make verify              - 全フェーズ検証"
	@echo "  make logs                - 重要なログ表示"
	@echo "  make clean               - 全システムクリーンアップ"
	@echo ""
	@echo "$(YELLOW)■ 使用例$(NC)"
	@echo "  make all                 # 完全自動デプロイ"
	@echo "  make host-setup infrastructure  # ホストセットアップとインフラ構築のみ"
	@echo "  make add-runner REPO=my-project  # Runner追加"
	@echo ""

# 全自動デプロイ (全ステップ)
all: check-automation-readiness host-setup infrastructure platform
	@echo "$(GREEN)✅ 全ステップのデプロイが完了しました$(NC)"
	@echo ""
	@$(MAKE) status

# deployはallのエイリアス
deploy: all

# ホストマシンセットアップ
host-setup:
	@echo "$(GREEN)🚀 ホストマシンセットアップ開始$(NC)"
	@cd $(HOST_SETUP_DIR) && ./setup-host.sh
	@echo "$(YELLOW)⚠️  グループメンバーシップの更新のため、権限を再確認します$(NC)"
	@if ! groups | grep -q libvirt; then \
		echo "$(YELLOW)libvirtグループが有効化されていません。sg libvirtで実行します...$(NC)"; \
		sg libvirt -c "cd $(HOST_SETUP_DIR) && ./setup-storage.sh"; \
		sg libvirt -c "cd $(HOST_SETUP_DIR) && ./verify-setup.sh"; \
	else \
		echo "$(GREEN)libvirtグループが有効です。続行します...$(NC)"; \
		cd $(HOST_SETUP_DIR) && ./setup-storage.sh; \
		cd $(HOST_SETUP_DIR) && ./verify-setup.sh; \
	fi
	@echo "$(GREEN)✅ ホストマシンセットアップ完了$(NC)"

# インフラストラクチャ構築 (VM + Kubernetesクラスタ)
infrastructure:
	@echo "$(GREEN)🚀 インフラストラクチャ構築開始 (VM + Kubernetesクラスタ)$(NC)"
	@cd $(INFRASTRUCTURE_DIR) && ./clean-and-deploy.sh
	@echo "$(YELLOW)🕐 クラスタ準備完了を確認しています...$(NC)"
	@$(MAKE) wait-for-k8s-cluster
	@echo "$(GREEN)✅ インフラストラクチャ構築完了$(NC)"

# Kubernetesプラットフォーム構築
platform:
	@echo "$(GREEN)🚀 Kubernetesプラットフォーム構築開始$(NC)"
	@cd $(PLATFORM_DIR) && ./phase4-deploy.sh
	@echo "$(YELLOW)🕐 External Secrets同期確認中...$(NC)"
	@$(MAKE) wait-for-external-secrets
	@echo "$(GREEN)✅ Kubernetesプラットフォーム構築完了$(NC)"

# 後方互換性用（非推奨）
vm-deploy: infrastructure
	@echo "$(YELLOW)⚠️  vm-deployは非推奨です。infrastructureを使用してください$(NC)"

vm-k8s-deploy: infrastructure
	@echo "$(YELLOW)⚠️  vm-k8s-deployは非推奨です。infrastructureを使用してください$(NC)"

k8s-cluster: infrastructure
	@echo "$(YELLOW)⚠️  k8s-clusterは非推奨です。infrastructureを使用してください$(NC)"

k8s-infrastructure: platform
	@echo "$(YELLOW)⚠️  k8s-infrastructureは非推奨です。platformを使用してください$(NC)"

# GitHub Actions Runner追加
add-runner:
	@if [ -z "$(REPO)" ]; then \
		echo "$(RED)❌ エラー: REPO変数が必要です$(NC)"; \
		echo "使用方法: make add-runner REPO=repository-name"; \
		exit 1; \
	fi
	@echo "$(GREEN)🚀 GitHub Actions Runner追加: $(REPO)$(NC)"
	@cd $(PLATFORM_DIR) && ./add-runner.sh $(REPO)
	@echo "$(GREEN)✅ Runner追加完了$(NC)"

# Actions Runner Controller設定
setup-arc:
	@echo "$(GREEN)🚀 Actions Runner Controller設定開始$(NC)"
	@cd $(PLATFORM_DIR) && ./setup-arc.sh
	@echo "$(GREEN)✅ ARC設定完了$(NC)"

# Harbor証明書修正
harbor-cert-fix:
	@echo "$(GREEN)🚀 Harbor証明書修正開始$(NC)"
	@cd $(PLATFORM_DIR) && ./harbor-cert-fix.sh
	@echo "$(GREEN)✅ Harbor証明書修正完了$(NC)"

# 全システム状態確認
status:
	@echo "$(GREEN)📊 システム状態確認$(NC)"
	@echo ""
	@echo "$(YELLOW)■ VM状態$(NC)"
	@sudo virsh list --all 2>/dev/null || echo "libvirtが利用できません"
	@echo ""
	@echo "$(YELLOW)■ Kubernetesクラスタ状態$(NC)"
	@ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 k8suser@192.168.122.10 'kubectl get nodes' 2>/dev/null || echo "Kubernetesクラスタに接続できません"
	@echo ""
	@echo "$(YELLOW)■ ArgoCD Applications状態$(NC)"
	@ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 k8suser@192.168.122.10 'kubectl get applications -n argocd' 2>/dev/null || echo "ArgoCD Applicationsが確認できません"
	@echo ""
	@echo "$(YELLOW)■ LoadBalancer IP$(NC)"
	@ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 k8suser@192.168.122.10 'kubectl -n ingress-nginx get service ingress-nginx-controller -o jsonpath="{.status.loadBalancer.ingress[0].ip}"' 2>/dev/null || echo "LoadBalancer IPが取得できません"
	@echo ""

# 全フェーズ検証
verify:
	@echo "$(GREEN)🔍 全フェーズ検証開始$(NC)"
	@echo ""
	@echo "$(YELLOW)■ ホストセットアップ検証$(NC)"
	@cd $(HOST_SETUP_DIR) && ./verify-setup.sh 2>/dev/null || echo "ホストセットアップ検証失敗"
	@echo ""
	@echo "$(YELLOW)■ インフラストラクチャ検証$(NC)"
	@cd $(INFRASTRUCTURE_DIR) && terraform plan -out=tfplan >/dev/null 2>&1 && echo "✅ Terraform状態正常" || echo "❌ Terraform状態異常"
	@echo ""
	@echo "$(YELLOW)■ Kubernetesクラスタ稼働検証$(NC)"
	@ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 k8suser@192.168.122.10 'kubectl get nodes --no-headers | grep -c Ready' 2>/dev/null | \
		awk '{if($$1>=3) print "✅ Kubernetesクラスタ正常 ("$$1" nodes Ready)"; else print "❌ Kubernetesクラスタ異常"}' || echo "❌ Kubernetesクラスタ接続失敗"
	@echo ""
	@echo "$(YELLOW)■ Kubernetesプラットフォーム検証$(NC)"
	@ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 k8suser@192.168.122.10 'kubectl get pods --all-namespaces | grep -E "(metallb|ingress|cert-manager|argocd|harbor)" | grep -c Running' 2>/dev/null | \
		awk '{if($$1>=10) print "✅ 基盤インフラ正常 ("$$1" pods Running)"; else print "❌ 基盤インフラ異常 ("$$1" pods Running)"}' || echo "❌ 基盤インフラ確認失敗"

# 重要なログ表示
logs:
	@echo "$(GREEN)📋 重要なログ表示$(NC)"
	@echo ""
	@echo "$(YELLOW)■ ArgoCD初期パスワード$(NC)"
	@ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 k8suser@192.168.122.10 'kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d' 2>/dev/null || echo "ArgoCD初期パスワードが取得できません"
	@echo ""
	@echo ""
	@echo "$(YELLOW)■ GitHub認証情報状態$(NC)"
	@cd $(PLATFORM_DIR) && source ./github-auth-utils.sh && show_github_credentials_status 2>/dev/null || echo "GitHub認証情報が確認できません"
	@echo ""
	@echo "$(YELLOW)■ 最近の重要なポッド状態$(NC)"
	@ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 k8suser@192.168.122.10 'kubectl get pods --all-namespaces | grep -E "(argocd|harbor|actions-runner)" | tail -10' 2>/dev/null || echo "ポッド状態が確認できません"

# 自動化実行の事前チェック
check-automation-readiness:
	@echo "$(GREEN)🔍 自動化実行の事前チェック$(NC)"
	@echo "$(YELLOW)■ 実行環境確認$(NC)"
	@if [ "$(shell whoami)" = "root" ]; then \
		echo "$(RED)❌ エラー: rootユーザーでは実行できません$(NC)"; \
		exit 1; \
	fi
	@if [ ! -d "$(PROJECT_ROOT)" ]; then \
		echo "$(RED)❌ エラー: プロジェクトルートが見つかりません$(NC)"; \
		exit 1; \
	fi
	@echo "$(GREEN)✅ 事前チェック完了$(NC)"


# Kubernetesクラスタ準備完了待機
wait-for-k8s-cluster:
	@echo "$(YELLOW)🕐 Kubernetesクラスタ準備完了を待機中...$(NC)"
	@timeout=300; \
	while [ $$timeout -gt 0 ]; do \
		ready_nodes=$$(ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 k8suser@192.168.122.10 'kubectl get nodes --no-headers 2>/dev/null | grep -c Ready' 2>/dev/null || echo "0"); \
		if [ "$$ready_nodes" -ge 3 ]; then \
			echo "$(GREEN)✅ Kubernetesクラスタ準備完了 ($$ready_nodes nodes Ready)$(NC)"; \
			break; \
		fi; \
		echo "Ready ノード数: $$ready_nodes/3 - あと $$timeout 秒待機..."; \
		sleep 10; \
		timeout=$$((timeout - 10)); \
	done; \
	if [ $$timeout -le 0 ]; then \
		echo "$(RED)❌ Kubernetesクラスタ準備がタイムアウトしました$(NC)"; \
		exit 1; \
	fi

# External Secrets同期完了待機
wait-for-external-secrets:
	@echo "$(YELLOW)🕐 External Secrets同期完了を待機中...$(NC)"
	@timeout=180; \
	github_secret_ready=false; \
	while [ $$timeout -gt 0 ]; do \
		if ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 k8suser@192.168.122.10 'kubectl get externalsecret github-auth-secret -n arc-systems' >/dev/null 2>&1; then \
			github_ready=$$(ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 'kubectl get externalsecret github-auth-secret -n arc-systems -o jsonpath="{.status.conditions[?(@.type==\"Ready\")].status}"' 2>/dev/null || echo "False"); \
			if [ "$$github_ready" = "True" ]; then \
				echo "$(GREEN)✅ GitHub External Secret準備完了$(NC)"; \
				github_secret_ready=true; \
				break; \
			fi; \
		fi; \
		echo "GitHub External Secret待機中... (残り $$timeout 秒)"; \
		sleep 10; \
		timeout=$$((timeout - 10)); \
	done; \
	if [ "$$github_secret_ready" = "false" ]; then \
		echo "$(YELLOW)⚠️ GitHub External Secret準備がタイムアウトしました（フォールバック動作します）$(NC)"; \
	fi

# 全システムクリーンアップ
clean:
	@echo "$(RED)⚠️  全システムをクリーンアップします$(NC)"
	@echo "この操作は以下を削除します:"
	@echo "  - 全VM"
	@echo "  - Terraformリソース"
	@echo "  - GitHub認証情報"
	@echo ""
	@bash -c 'read -p "続行しますか？ (y/N): " -r REPLY; \
	if [ "$$REPLY" = "y" ] || [ "$$REPLY" = "Y" ]; then \
		echo "$(YELLOW)クリーンアップ開始...$(NC)"; \
		sudo virsh list --all | grep k8s | awk '"'"'{print $$2}'"'"' | xargs -I {} sudo virsh destroy {} 2>/dev/null || true; \
		sudo virsh list --all | grep k8s | awk '"'"'{print $$2}'"'"' | xargs -I {} sudo virsh undefine {} 2>/dev/null || true; \
		cd $(INFRASTRUCTURE_DIR) && terraform destroy -auto-approve 2>/dev/null || true; \
		cd $(PLATFORM_DIR) && source ./github-auth-utils.sh && clear_github_credentials 2>/dev/null || true; \
		echo "$(GREEN)✅ クリーンアップ完了$(NC)"; \
	else \
		echo "$(YELLOW)クリーンアップをキャンセルしました$(NC)"; \
	fi'

# 後方互換性のためのエイリアス
.PHONY: phase1 phase2 phase3 phase4 phase2-3
phase1: host-setup
phase2-3: infrastructure
phase4: platform

# 非推奨エイリアス
phase2: infrastructure
	@echo "$(YELLOW)⚠️  phase2は統合されました。infrastructureが実行されます$(NC)"
phase3: infrastructure
	@echo "$(YELLOW)⚠️  phase3は統合されました。infrastructureが実行されます$(NC)"

# 開発用ターゲット
.PHONY: dev-info dev-ssh dev-argocd dev-harbor

# 開発用情報表示
dev-info:
	@echo "$(GREEN)🔧 開発用情報$(NC)"
	@echo ""
	@echo "$(YELLOW)■ 重要なURL$(NC)"
	@echo "ArgoCD: https://argocd.local (LoadBalancer) または kubectl port-forward svc/argocd-server -n argocd 8080:443"
	@echo "Harbor: https://harbor.local (LoadBalancer) または kubectl port-forward svc/harbor-core -n harbor 8081:80"
	@echo ""
	@echo "$(YELLOW)■ SSH接続$(NC)"
	@echo "Control Plane: ssh k8suser@192.168.122.10"
	@echo "Worker Node 1: ssh k8suser@192.168.122.11"
	@echo "Worker Node 2: ssh k8suser@192.168.122.12"
	@echo ""
	@echo "$(YELLOW)■ よく使うコマンド$(NC)"
	@echo "kubectl get pods --all-namespaces"
	@echo "kubectl -n argocd get applications"
	@echo "kubectl -n harbor get pods"

# Control Planeへの簡単SSH
dev-ssh:
	@ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10

# ArgoCD Port Forward
dev-argocd:
	@echo "$(GREEN)🌐 ArgoCD Port Forward開始 (localhost:8080)$(NC)"
	@ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 'kubectl port-forward svc/argocd-server -n argocd 8080:443'

# Harbor Port Forward
dev-harbor:
	@echo "$(GREEN)🌐 Harbor Port Forward開始 (localhost:8081)$(NC)"
	@ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 'kubectl port-forward svc/harbor-core -n harbor 8081:80'