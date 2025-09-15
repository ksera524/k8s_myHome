# maintenance.mk - メンテナンスと検証用ターゲット
include makefiles/variables.mk
include makefiles/functions.mk

# 全システム状態確認
status:
	$(call print_status,$(INFO),システム状態確認)
	$(call print_section,$(INFO),VM状態)
	@virsh list --all 2>/dev/null || echo "libvirtが利用できません（権限不足の場合はsudo make statusを実行）"
	$(call print_section,$(INFO),Kubernetesクラスタ状態)
	@$(call k8s_exec_safe,kubectl get nodes) || echo "Kubernetesクラスタに接続できません"
	$(call print_section,$(INFO),ArgoCD Applications状態)
	@ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 'kubectl get applications -n argocd --no-headers 2>/dev/null | awk '"'"'{print $$1 " (" $$2 "/" $$3 ")"}'"'"'' || echo "ArgoCD Applicationsが確認できません"
	$(call print_section,$(INFO),LoadBalancer IP)
	@ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 'IP=$$(kubectl get service ingress-nginx-controller -n ingress-nginx -o jsonpath="{.status.loadBalancer.ingress[0].ip}" 2>/dev/null); if [ -n "$$IP" ]; then echo $$IP; else kubectl get service ingress-nginx-controller -n ingress-nginx 2>/dev/null | grep -v NAME | awk "{if(\$$4==\"<pending>\") print \"LoadBalancer IP割り当て待機中\"; else print \"LoadBalancer IPが取得できません\"}"; fi' || echo "LoadBalancer IPが取得できません"
	@echo ""
	$(call print_section,$(INFO),External Secrets状態)
	@count=$$(ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 'kubectl get externalsecrets -A --no-headers 2>/dev/null | wc -l' || echo "0"); \
	if [ "$$count" -gt 0 ]; then \
		ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 'kubectl get externalsecrets -A --no-headers 2>/dev/null | head -10 | while read ns name store rest; do status=$$(echo $$rest | awk "{print \$$NF}"); echo "  $$name ($$ns): $$status"; done'; \
	else \
		echo "  External Secretsはまだ作成されていません"; \
	fi
	@echo ""
	$(call print_section,$(INFO),GitHub Actions Runner ScaleSets)
	@runner_count=$$(ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 'helm list -n arc-systems 2>/dev/null | grep -c runners' || echo "0"); \
	if [ "$$runner_count" -gt 0 ]; then \
		echo "  合計 $$runner_count Runner ScaleSet(s) が稼働中:"; \
		echo ""; \
		ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 'helm list -n arc-systems 2>/dev/null | grep runners | while read name ns rev updated status chart app; do \
			repo=$$(echo $$name | sed "s/-runners$$//"); \
			min=$$(helm get values $$name -n arc-systems 2>/dev/null | grep "^minRunners:" | awk "{print \$$2}"); \
			max=$$(helm get values $$name -n arc-systems 2>/dev/null | grep "^maxRunners:" | awk "{print \$$2}"); \
			running=$$(kubectl get pods -n arc-systems -l app.kubernetes.io/instance=$$name 2>/dev/null | grep -c "runner-" || echo "0"); \
			echo "  • $$repo:"; \
			echo "    - ScaleSet: $$name"; \
			echo "    - 設定: minRunners=$$min, maxRunners=$$max"; \
			echo "    - 稼働中のRunner: $$running"; \
			echo ""; \
		done' || echo "  Runner ScaleSet情報の取得に失敗しました"; \
	else \
		echo "  Runner ScaleSetsはまだ作成されていません"; \
		echo "  'make add-runners-all' でsettings.tomlから一括作成できます"; \
	fi
	@echo ""

# 全フェーズ検証
verify:
	$(call print_section,$(DEBUG),全フェーズ検証開始)
	$(call print_section,$(INFO),ホストセットアップ検証)
	@cd $(HOST_SETUP_DIR) && ./verify-setup.sh 2>/dev/null || echo "ホストセットアップ検証失敗"
	$(call print_section,$(INFO),インフラストラクチャ検証)
	@cd $(INFRASTRUCTURE_DIR) && terraform plan -out=tfplan >/dev/null 2>&1 && echo "$(CHECK) Terraform状態正常" || echo "$(ERROR) Terraform状態異常"
	$(call print_section,$(INFO),Kubernetesクラスタ稼働検証)
	@$(call _verify_k8s_cluster)
	$(call print_section,$(INFO),Kubernetesプラットフォーム検証)
	@$(call _verify_platform)
	$(call print_section,$(INFO),アプリケーション検証)
	@$(call _verify_applications)

# Kubernetesクラスタ検証（内部関数）
define _verify_k8s_cluster
	node_count=$$(ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 'kubectl get nodes --no-headers | grep -c Ready' 2>/dev/null || echo "0"); \
	echo $$node_count; \
	if [ "$${node_count:-0}" -eq 3 ]; then \
		echo "$(CHECK) Kubernetesクラスタ正常 (3 nodes Ready)"; \
	else \
		echo "$(ERROR) Kubernetesクラスタ異常 ($$node_count nodes Ready)"; \
	fi
endef

# プラットフォーム検証（内部関数）
define _verify_platform
	ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 'kubectl get pods --all-namespaces | grep -E "(metallb|ingress-nginx|cert-manager|external-secrets|argocd|harbor)" | grep Running | wc -l' | \
	awk '{if($$1>=10) print "$(CHECK) 基盤インフラ正常 ("$$1" pods Running)"; else print "$(ERROR) 基盤インフラ異常 ("$$1" pods Running)"}' || echo "$(ERROR) 基盤インフラ確認失敗"
endef

# アプリケーション検証（内部関数）
define _verify_applications
	slack_pods=$$(ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 'kubectl get pods -n $(HARBOR_DEFAULT_PROJECT) 2>/dev/null | grep slack | grep -c Running' || echo "0"); \
	if [ "$${slack_pods:-0}" -gt 0 ]; then \
		echo "$(CHECK) Slack アプリケーション正常 ($$slack_pods pods Running)"; \
	else \
		echo "$(ERROR) Slack アプリケーション異常 (0 pods Running)"; \
	fi
endef

# 重要なログ表示
logs:
	$(call print_section,$(INFO),重要なログ表示)
	@if [ -f "$(PROJECT_ROOT)/make-all.log" ]; then \
		echo "$(INFO) 最新のmake allログ (最後の100行):"; \
		echo "$(INFO) ログファイル: $(PROJECT_ROOT)/make-all.log"; \
		echo ""; \
		tail -n 100 $(PROJECT_ROOT)/make-all.log; \
		echo ""; \
		echo "$(INFO) 完全なログは以下で確認:"; \
		echo "cat $(PROJECT_ROOT)/make-all.log"; \
	else \
		echo "$(WARNING) make-all.log が見つかりません"; \
	fi
	@echo ""
	$(call print_section,$(INFO),GitHub認証情報状態)
	@cd $(PLATFORM_DIR) && source ../scripts/argocd/github-auth-utils.sh && show_github_credentials_status 2>/dev/null || echo "GitHub認証情報が確認できません"
	@echo ""
	$(call print_section,$(INFO),最近の重要なポッド状態)
	@$(call k8s_exec_safe,kubectl get pods --all-namespaces | grep -vE "(Running|Completed)" | head -20) || echo "ポッド状態が確認できません"
	@echo ""

# 問題診断
diagnose:
	$(call print_section,$(DEBUG),問題診断開始)
	$(call print_section,$(WARNING),問題のあるPods)
	@$(call k8s_exec_safe,kubectl get pods --all-namespaces | grep -vE "(Running|Completed)" | head -20) || echo "問題のあるPodsが確認できません"
	@echo ""
	$(call print_section,$(WARNING),Pending状態のPVC)
	@$(call k8s_exec_safe,kubectl get pvc --all-namespaces | grep Pending) || echo "Pending状態のPVCはありません"
	@echo ""
	$(call print_section,$(WARNING),最近のイベント)
	@$(call k8s_exec_safe,kubectl get events --all-namespaces --sort-by='.lastTimestamp' | tail -20) || echo "イベントが確認できません"
	@echo ""
	$(call print_section,$(WARNING),ArgoCD同期エラー)
	@$(call k8s_exec_safe,kubectl get applications -n argocd -o json | jq -r '.items[] | select(.status.sync.status != "Synced") | "\(.metadata.name): \(.status.sync.status) - \(.status.conditions[0].message // \"No message\")"') || echo "ArgoCD同期エラーが確認できません"

# クリーンアップ
clean-logs:
	$(call print_section,$(WARNING),ログファイルクリーンアップ)
	@rm -f $(PROJECT_ROOT)/*.log
	@rm -f $(PROJECT_ROOT)/automation/*.log
	@rm -f /tmp/k8s-*.log
	@echo "$(CHECK) ログファイルを削除しました"

# 削除されたターゲット（簡素化のため）
# clean-github-auth: GitHub認証情報削除
# argocd-sync: ArgoCD手動同期

# GitHub認証情報削除（内部関数）
define _clean_github_auth
	cd $(PLATFORM_DIR) && source ../scripts/argocd/github-auth-utils.sh && clear_github_credentials 2>/dev/null || true
endef

# ArgoCD同期実行（内部関数）
define _sync_argocd
	$(call kubectl_exec,patch application applications -n argocd --type merge -p '{"metadata":{"annotations":{"argocd.argoproj.io/refresh":"hard"}}}') || true
endef