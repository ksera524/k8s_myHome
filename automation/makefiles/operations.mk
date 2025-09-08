# k8s_myHome Operations Targets
# 運用・操作関連のターゲット定義

# GitHub Actions Runner追加
add-runner:
	@if [ -z "$(REPO)" ]; then \
		echo "$(ERROR) REPO変数が必要です"; \
		echo "使用方法: make add-runner REPO=repository-name"; \
		exit 1; \
	fi
	$(call print_status,$(ROCKET),GitHub Actions Runner追加 (公式ARC対応): $(REPO))
	@cd $(SCRIPTS_DIR)/github-actions && ./add-runner.sh $(REPO)
	$(call print_status,$(CHECK),Runner追加完了)

# Actions Runner Controller設定 - deployment.mkに移動済み

# Harbor設定修正
harbor-fix:
	$(call print_status,$(ROCKET),Harbor設定修正)
	@ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 '\
		echo "Harbor EXT_ENDPOINT修正中..." && \
		kubectl patch cm harbor-core -n harbor --type json -p "[{\"op\": \"replace\", \"path\": \"/data/EXT_ENDPOINT\", \"value\": \"http://harbor.local\"}]" && \
		kubectl rollout restart deployment/harbor-core -n harbor && \
		kubectl rollout status deployment/harbor-core -n harbor --timeout=120s && \
		HARBOR_PASSWORD=$$(kubectl get secret harbor-admin-secret -n harbor -o jsonpath="{.data.password}" | base64 -d) && \
		kubectl create secret generic harbor-auth \
			--namespace=arc-systems \
			--from-literal=HARBOR_URL="harbor.local" \
			--from-literal=HARBOR_USERNAME="admin" \
			--from-literal=HARBOR_PASSWORD="$${HARBOR_PASSWORD}" \
			--from-literal=HARBOR_PROJECT="sandbox" \
			--dry-run=client -o yaml | kubectl apply -f - && \
		echo "✓ Harbor設定修正完了"'
	$(call print_status,$(CHECK),Harbor設定修正完了)

# Harbor証明書修正（skopeo対応により不要）
harbor-cert-fix:
	$(call print_status,$(INFO),skopeo対応によりHarbor証明書修正は不要です)
	@echo "skopeoアプローチ（--dest-tls-verify=false）により証明書問題は自動解決されます"

# Slack Secret手動設定
setup-slack-secret:
	$(call print_status,$(ROCKET),Slack Secret手動設定開始)
	@cd $(PLATFORM_DIR)/external-secrets && ./deploy-slack-secrets.sh
	$(call print_status,$(CHECK),Slack Secret設定完了)

# 設定ファイル読み込み
load-settings:
	$(call print_status,$(INFO),設定ファイル読み込み中...)
	$(call load_settings)
	$(call print_status,$(CHECK),設定ファイル読み込み完了)

# 前提条件チェック
check-prerequisites:
	@if [[ $$(id -u) -eq 0 ]]; then \
		echo "$(ERROR) rootユーザーでは実行できません"; \
		exit 1; \
	fi
	@if [ ! -d "$(PROJECT_ROOT)" ]; then \
		echo "$(ERROR) プロジェクトルートが見つかりません: $(PROJECT_ROOT)"; \
		exit 1; \
	fi

# 自動化実行の事前チェック
check-automation-readiness: check-prerequisites
	@echo "$(DEBUG) 自動化実行の事前チェック"
	@echo ""
	@echo "$(INFO) 実行環境確認"
	@echo ""
	@echo "$(CHECK) 事前チェック完了"

# Kubernetesクラスタ準備完了待機
wait-for-k8s-cluster:
	$(call print_status,$(INFO),Kubernetesクラスタ準備完了を待機中...)
	@timeout=$(K8S_CLUSTER_TIMEOUT); \
	while [ $$timeout -gt 0 ]; do \
		ready_nodes=$$($(call k8s_exec_safe,kubectl get nodes --no-headers 2>/dev/null | grep -c Ready) 2>/dev/null || echo "0"); \
		if [ "$$ready_nodes" -ge 3 ]; then \
			echo "$(CHECK) Kubernetesクラスタ準備完了 ($$ready_nodes nodes Ready)"; \
			break; \
		fi; \
		echo "Ready ノード数: $$ready_nodes/3 - あと $$timeout 秒待機..."; \
		sleep 10; \
		timeout=$$((timeout - 10)); \
	done; \
	if [ $$timeout -le 0 ]; then \
		echo "$(ERROR) Kubernetesクラスタ準備がタイムアウトしました"; \
		exit 1; \
	fi

# GitHub External Secret同期完了待機（削除：External Secrets Operatorが自動同期するため不要）
# External Secrets Operatorは20秒間隔で自動的に同期を行い、
# GitOpsパターンにより必要なシークレットは自動的に作成される

# 削除された複雑な内部関数（簡素化のため）