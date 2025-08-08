# k8s_myHome Deployment Targets
# デプロイメント関連のターゲット定義

# 全自動デプロイ
all: check-automation-readiness host-setup infrastructure platform post-deployment setup-github-actions
	@echo "$(CHECK) 全ステップのデプロイが完了しました"
	@$(MAKE) status

# deployはallのエイリアス
deploy: all

# ホストマシンセットアップ
host-setup:
	@echo "$(ROCKET) ホストマシンセットアップ開始"
	$(call execute_with_settings,$(HOST_SETUP_DIR),./setup-host.sh)
	@$(MAKE) _host-setup-storage
	@echo "$(CHECK) ホストマシンセットアップ完了"

# ストレージセットアップ（内部ターゲット）
_host-setup-storage:
	@echo "$(WARNING) グループメンバーシップの更新のため権限を再確認します"
	@if ! groups | grep -q libvirt; then \
		echo "$(WARNING) libvirtグループが有効化されていません"; \
		echo "sg libvirtで実行が必要な場合があります"; \
	fi
	@if ! groups | grep -q libvirt; then \
		echo "$(INFO) sg libvirtで実行します..."; \
		if [ -f "$(SETTINGS_FILE)" ]; then \
			sg libvirt -c 'bash -c "source $(SETTINGS_LOADER) load && cd $(HOST_SETUP_DIR) && ./setup-storage.sh"'; \
			sg libvirt -c 'bash -c "source $(SETTINGS_LOADER) load && cd $(HOST_SETUP_DIR) && ./verify-setup.sh"'; \
		else \
			sg libvirt -c "cd $(HOST_SETUP_DIR) && ./setup-storage.sh"; \
			sg libvirt -c "cd $(HOST_SETUP_DIR) && ./verify-setup.sh"; \
		fi; \
	else \
		echo "$(CHECK) libvirtグループが有効です。続行します..."; \
		if [ -f "$(SETTINGS_FILE)" ]; then \
			bash -c 'source "$(SETTINGS_LOADER)" load && cd $(HOST_SETUP_DIR) && ./setup-storage.sh'; \
			bash -c 'source "$(SETTINGS_LOADER)" load && cd $(HOST_SETUP_DIR) && ./verify-setup.sh'; \
		else \
			cd $(HOST_SETUP_DIR) && ./setup-storage.sh; \
			cd $(HOST_SETUP_DIR) && ./verify-setup.sh; \
		fi; \
	fi

# インフラストラクチャ構築
infrastructure:
	@echo "$(ROCKET) インフラストラクチャ構築開始 (VM + Kubernetesクラスタ)"
	$(call execute_with_settings,$(INFRASTRUCTURE_DIR),./clean-and-deploy.sh)
	@echo "$(INFO) クラスタ準備完了を確認しています..."
	@$(MAKE) wait-for-k8s-cluster
	@echo "$(CHECK) インフラストラクチャ構築完了"

# Kubernetesプラットフォーム構築
platform:
	@echo "$(ROCKET) Kubernetesプラットフォーム構築開始"
	@bash -c 'source "$(SETTINGS_LOADER)" load && cd $(PLATFORM_DIR) && NON_INTERACTIVE=true ./platform-deploy.sh' || echo "$(WARNING) Platform構築で一部警告が発生しましたが続行します"
	@echo "$(INFO) App-of-Appsデプロイ強制実行中..."
	@$(MAKE) _deploy-app-of-apps || echo "$(WARNING) App-of-Appsデプロイで警告が発生しましたが続行します"
	@echo "$(INFO) External Secrets同期確認中..."
	@$(MAKE) wait-for-external-secrets || echo "$(WARNING) External Secrets同期で一部警告が発生しましたが続行します"
	@echo "$(GEAR) ArgoCD GitHub OAuth設定中..."
	@bash -c 'source "$(SETTINGS_LOADER)" load && cd $(PLATFORM_DIR) && NON_INTERACTIVE=true ../scripts/argocd/setup-argocd-github-oauth.sh' || echo "$(WARNING) ArgoCD GitHub OAuth設定で警告が発生しましたが続行します"
	@echo "$(CHECK) Kubernetesプラットフォーム構築完了"

# App-of-Apps強制デプロイ（内部ターゲット）
_deploy-app-of-apps:
	@echo "$(ROCKET) App-of-Apps GitOps デプロイ強制実行"
	@if $(call kubectl_exec,get namespace argocd) >/dev/null 2>&1; then \
		echo "$(CHECK) ArgoCD namespace確認済み"; \
		if ! $(call kubectl_exec,get application infrastructure -n argocd) >/dev/null 2>&1; then \
			echo "$(INFO) App-of-Apps適用中..."; \
			if $(call kubectl_exec,apply -f /tmp/app-of-apps.yaml); then \
				echo "$(CHECK) App-of-Apps デプロイ成功"; \
				$(call kubectl_exec,get applications -n argocd --no-headers) | awk '{print "  - " $$1 " (" $$2 "/" $$3 ")"}' || true; \
			else \
				echo "$(WARNING) App-of-Apps デプロイで問題が発生しました"; \
			fi; \
		else \
			echo "$(CHECK) App-of-Apps は既に存在しています"; \
		fi; \
	else \
		echo "$(WARNING) ArgoCD namespaceが見つかりません"; \
	fi

# ポストデプロイメント処理
post-deployment:
	$(call print_section,$(GEAR),ポストデプロイメント: GitOps同期とGitHub OAuth設定確認中...)
	@sleep $(GITOPS_SYNC_WAIT)  # GitOps同期待機
	$(call print_status,$(RECYCLE),External Secrets設定強制同期中...)
	$(call force_argocd_sync)
	@sleep 10  # ArgoCD同期待機
	$(call print_status,$(CLOUD),ArgoCD App-of-Apps同期でCloudflaredアプリケーション確認中...)
	$(call force_argocd_sync)
	@sleep 5
	@$(MAKE) _check-cloudflared-app
	@bash -c 'source "$(SETTINGS_LOADER)" load && cd $(PLATFORM_DIR) && NON_INTERACTIVE=true ../scripts/argocd/setup-argocd-github-oauth.sh' || echo "$(WARNING) ArgoCD GitHub OAuth設定で警告が発生しましたが続行します"
	$(call print_status,$(CHECK),ポストデプロイメント完了)

# GitHub Actionsセットアップ
setup-github-actions:
	$(call print_section,$(ROCKET),GitHub Actions Runner Controller セットアップ中...)
	@$(MAKE) _setup-github-actions-conditional
	$(call print_status,$(CHECK),GitHub Actionsセットアップ完了)

# GitHub Actions条件付きセットアップ（内部ターゲット）
_setup-github-actions-conditional:
	@$(SCRIPTS_DIR)/setup-github-actions.sh

# Cloudflaredアプリケーション確認（内部ターゲット）
_check-cloudflared-app:
	@if $(call kubectl_exec,get application cloudflared -n $(ARGOCD_NAMESPACE)) >/dev/null 2>&1; then \
		echo "$(CHECK) CloudflaredアプリケーションはArgoCD経由で管理されています"; \
	else \
		echo "$(WARNING) Cloudflaredアプリケーションの同期待機中（ArgoCD App-of-Apps経由）"; \
	fi

# ArgoCD GitHub OAuth修復
fix-github-oauth:
	$(call print_status,$(GEAR),ArgoCD GitHub OAuth設定修復中)
	@cd $(PLATFORM_DIR) && ../scripts/argocd/fix-argocd-github-oauth.sh || echo "$(WARNING) GitHub OAuth修復で警告が発生しましたが続行します"
	$(call print_status,$(CHECK),ArgoCD GitHub OAuth設定修復完了)

# 後方互換性用（非推奨）
vm-deploy: infrastructure
	@echo "$(WARNING) vm-deployは非推奨です。infrastructureを使用してください"

vm-k8s-deploy: infrastructure
	@echo "$(WARNING) vm-k8s-deployは非推奨です。infrastructureを使用してください"

k8s-cluster: infrastructure
	@echo "$(WARNING) k8s-clusterは非推奨です。infrastructureを使用してください"

k8s-infrastructure: platform
	@echo "$(WARNING) k8s-infrastructureは非推奨です。platformを使用してください"

# 後方互換性のためのフェーズエイリアス
.PHONY: phase1 phase2 phase3 phase4 phase2-3
phase1: host-setup
phase2-3: infrastructure
phase4: platform

# 非推奨エイリアス
phase2: infrastructure
	@echo "$(WARNING) phase2は統合されました。infrastructureが実行されます"

phase3: infrastructure
	@echo "$(WARNING) phase3は統合されました。infrastructureが実行されます"