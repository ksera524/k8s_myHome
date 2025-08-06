# k8s_myHome Common Functions
# 共通処理とマクロ定義

# 設定ファイル読み込みマクロ
define load_settings
	@if [ -f "$(SETTINGS_FILE)" ]; then \
		echo "$(INFO) settings.tomlを読み込み中..."; \
		source "$(SETTINGS_LOADER)" load 2>/dev/null || true; \
	else \
		echo "$(WARNING) settings.tomlが見つかりません"; \
		echo "   $(SETTINGS_FILE)を作成して設定を自動化できます"; \
	fi
endef

# 設定付きでスクリプト実行
define execute_with_settings
	@if [ -f "$(SETTINGS_FILE)" ]; then \
		bash -c 'source "$(SETTINGS_LOADER)" load && cd $(1) && $(2)'; \
	else \
		cd $(1) && $(2); \
	fi
endef

# SSH経由でのコマンド実行
define k8s_exec
	ssh $(SSH_OPTS) $(K8S_USER)@$(K8S_CONTROL_PLANE_IP) '$(1)'
endef

# SSH経由での安全なコマンド実行（エラー無視）
define k8s_exec_safe
	ssh $(SSH_OPTS) $(K8S_USER)@$(K8S_CONTROL_PLANE_IP) '$(1)' 2>/dev/null || echo "$(WARNING) コマンド実行で警告が発生しましたが続行します"
endef

# kubectlコマンド実行
define kubectl_exec
	$(call k8s_exec,kubectl $(1))
endef

# ArgoCD同期強制実行
define force_argocd_sync
	@if $(call kubectl_exec,get application applications -n $(ARGOCD_NAMESPACE)) >/dev/null 2>&1; then \
		$(call kubectl_exec,patch application applications -n $(ARGOCD_NAMESPACE) --type merge -p "{\"metadata\":{\"annotations\":{\"argocd.argoproj.io/refresh\":\"hard\"}}}"); \
	else \
		echo "$(WARNING) ArgoCD Application 'applications' が存在しません。App-of-Apps デプロイが必要です"; \
	fi
endef

# ステータス出力マクロ
define print_status
	@echo "$(1) $(2)"
endef

define print_section
	@echo ""
	@echo "$(1) $(2)"
	@echo ""
endef

# libvirtグループチェック
define check_libvirt_group
	@if ! groups | grep -q libvirt; then \
		echo "$(WARNING) libvirtグループが有効化されていません"; \
		echo "sg libvirtで実行が必要な場合があります"; \
	fi
endef

# クラスタ接続確認
define check_k8s_connectivity
	@if ! $(call k8s_exec_safe,kubectl get nodes) >/dev/null 2>&1; then \
		echo "$(WARNING) Kubernetesクラスタに接続できません"; \
		return 1; \
	fi
endef

# ヘルプセクション出力
define help_section
	@echo "$(1)"
	@echo "$(2)"
	@echo ""
endef