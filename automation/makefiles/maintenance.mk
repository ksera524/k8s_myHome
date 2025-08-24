# k8s_myHome Maintenance Targets
# 保守・管理関連のターゲット定義

# 全システム状態確認
status:
	$(call print_status,$(INFO),システム状態確認)
	$(call print_section,$(INFO),VM状態)
	@sudo virsh list --all 2>/dev/null || echo "libvirtが利用できません"
	$(call print_section,$(INFO),Kubernetesクラスタ状態)
	@$(call k8s_exec_safe,kubectl get nodes) || echo "Kubernetesクラスタに接続できません"
	$(call print_section,$(INFO),ArgoCD Applications状態)
	@$(call kubectl_exec,get applications -n $(ARGOCD_NAMESPACE)) 2>/dev/null || echo "ArgoCD Applicationsが確認できません"
	$(call print_section,$(INFO),LoadBalancer IP)
	@$(call kubectl_exec,get service ingress-nginx-controller -n ingress-nginx -o jsonpath='{.status.loadBalancer.ingress[0].ip}') 2>/dev/null || echo "LoadBalancer IPが取得できません"
	@echo ""
	$(call print_section,$(INFO),External Secrets状態)
	@$(call k8s_exec_safe,kubectl get externalsecrets -A | grep -v NAMESPACE | while read ns name store refresh status ready; do echo "  $$name ($$ns): $$refresh/$$status $$ready"; done) || echo "External Secrets状態が確認できません"
	@echo ""
	@echo "$(INFO) 重要なExternal Secrets詳細確認："
	@ssh -o StrictHostKeyChecking=no k8suser@$(K8S_CONTROL_PLANE_IP) 'kubectl get externalsecret github-auth-secret -n arc-systems --no-headers 2>/dev/null | awk "{print \"  github-auth-secret: \" \$$6}"' 2>/dev/null || echo "  github-auth-secret: 未確認"
	@ssh -o StrictHostKeyChecking=no k8suser@$(K8S_CONTROL_PLANE_IP) 'kubectl get externalsecret slack-secret -n sandbox --no-headers 2>/dev/null | awk "{print \"  slack-secret: \" \$$6}"' 2>/dev/null || echo "  slack-secret: 未確認"
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
	@$(call _verify_k8s_platform)
	$(call print_section,$(INFO),アプリケーション検証)
	@$(call _verify_applications)

# Kubernetesクラスタ検証（内部関数）
define _verify_k8s_cluster
	$(call k8s_exec_safe,kubectl get nodes --no-headers | grep -c Ready) | \
	awk '{if($$1>=3) print "$(CHECK) Kubernetesクラスタ正常 ("$$1" nodes Ready)"; else print "$(ERROR) Kubernetesクラスタ異常"}' || echo "$(ERROR) Kubernetesクラスタ接続失敗"
endef

# Kubernetesプラットフォーム検証（内部関数） 
define _verify_k8s_platform
	$(call k8s_exec_safe,kubectl get pods --all-namespaces | grep -E "(metallb|ingress|cert-manager|argocd|harbor)" | grep -c Running) | \
	awk '{if($$1>=10) print "$(CHECK) 基盤インフラ正常 ("$$1" pods Running)"; else print "$(ERROR) 基盤インフラ異常 ("$$1" pods Running)"}' || echo "$(ERROR) 基盤インフラ確認失敗"
endef

# アプリケーション検証（内部関数）
define _verify_applications
	slack_pods=$$($(call k8s_exec_safe,kubectl get pods -n $(HARBOR_DEFAULT_PROJECT) | grep slack | grep -c Running) || echo "0"); \
	if [ "$$slack_pods" -gt 0 ]; then \
		echo "$(CHECK) Slack アプリケーション正常 ($$slack_pods pods Running)"; \
	else \
		echo "$(ERROR) Slack アプリケーション異常 (0 pods Running)"; \
	fi || echo "$(ERROR) Slack アプリケーション確認失敗"
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
	else \
		echo "$(INFO) make allログが見つかりません"; \
		echo ""; \
	fi
	$(call print_section,$(INFO),ArgoCD初期パスワード)
	@$(call kubectl_exec,get secret argocd-initial-admin-secret -n $(ARGOCD_NAMESPACE) -o jsonpath='{.data.password}' | base64 -d) 2>/dev/null || echo "ArgoCD初期パスワードが取得できません"
	@echo ""
	@echo ""
	$(call print_section,$(INFO),GitHub認証情報状態)
	@cd $(PLATFORM_DIR) && source ../scripts/argocd/github-auth-utils.sh && show_github_credentials_status 2>/dev/null || echo "GitHub認証情報が確認できません"
	@echo ""
	$(call print_section,$(INFO),最近の重要なポッド状態)
	@$(call kubectl_exec,get pods --all-namespaces | grep -E "(argocd|harbor|actions-runner|slack)" | tail -10) 2>/dev/null || echo "ポッド状態が確認できません"
	@echo ""
	$(call print_section,$(INFO),Slack Secret状態)
	@$(call kubectl_exec,get secret slack -n $(HARBOR_DEFAULT_PROJECT) --no-headers | awk '{print "Secret slack: " $$2 " (" $$3 " keys) Age: " $$4}') 2>/dev/null || echo "Slack Secretが確認できません"
	@echo ""

# 全システムクリーンアップ
clean:
	$(call print_status,$(WARNING),全システムをクリーンアップします)
	@echo "この操作は以下を削除します:"
	@echo "  - 全VM"
	@echo "  - Terraformリソース"
	@echo "  - GitHub認証情報"
	@echo ""
	@bash -c 'read -p "続行しますか？ (y/N): " -r REPLY; \
	if [ "$$REPLY" = "y" ] || [ "$$REPLY" = "Y" ]; then \
		echo "$(INFO) クリーンアップ開始..."; \
		$(call _clean_vms); \
		$(call _clean_terraform); \
		$(call _clean_github_auth); \
		echo "$(CHECK) クリーンアップ完了"; \
	else \
		echo "$(WARNING) クリーンアップをキャンセルしました"; \
	fi'

# VM削除（内部関数）
define _clean_vms
	sudo virsh list --all | grep k8s | awk '{print $$2}' | xargs -I {} sudo virsh destroy {} 2>/dev/null || true; \
	sudo virsh list --all | grep k8s | awk '{print $$2}' | xargs -I {} sudo virsh undefine {} 2>/dev/null || true
endef

# Terraform削除（内部関数）
define _clean_terraform
	cd $(INFRASTRUCTURE_DIR) && terraform destroy -auto-approve 2>/dev/null || true
endef

# GitHub認証情報削除（内部関数）
define _clean_github_auth
	cd $(PLATFORM_DIR) && source ../scripts/argocd/github-auth-utils.sh && clear_github_credentials 2>/dev/null || true
endef

# 開発用ターゲット
.PHONY: dev-info dev-ssh dev-argocd dev-harbor

# 開発用情報表示
dev-info:
	$(call print_section,$(GEAR),開発用情報)
	$(call print_section,$(INFO),重要なURL)
	@echo "ArgoCD: https://argocd.local (LoadBalancer) または kubectl port-forward svc/argocd-server -n $(ARGOCD_NAMESPACE) 8080:443"
	@echo "Harbor: https://harbor.local (LoadBalancer) または kubectl port-forward svc/harbor-core -n $(HARBOR_NAMESPACE) 8081:80"
	@echo ""
	$(call print_section,$(INFO),SSH接続)
	@echo "Control Plane: ssh $(K8S_USER)@$(K8S_CONTROL_PLANE_IP)"
	@echo "Worker Node 1: ssh $(K8S_USER)@$(K8S_WORKER_1_IP)"
	@echo "Worker Node 2: ssh $(K8S_USER)@$(K8S_WORKER_2_IP)"
	@echo ""
	$(call print_section,$(INFO),よく使うコマンド)
	@echo "kubectl get pods --all-namespaces"
	@echo "kubectl -n $(ARGOCD_NAMESPACE) get applications"
	@echo "kubectl -n $(HARBOR_NAMESPACE) get pods"

# Control Planeへの簡単SSH
dev-ssh:
	@ssh $(SSH_OPTS) $(K8S_USER)@$(K8S_CONTROL_PLANE_IP)

# ArgoCD Port Forward
dev-argocd:
	$(call print_status,$(CLOUD),ArgoCD Port Forward開始 (localhost:8080))
	@$(call k8s_exec,kubectl port-forward svc/argocd-server -n $(ARGOCD_NAMESPACE) 8080:443)

# Harbor Port Forward
dev-harbor:
	$(call print_status,$(CLOUD),Harbor Port Forward開始 (localhost:8081))
	@$(call k8s_exec,kubectl port-forward svc/harbor-core -n $(HARBOR_NAMESPACE) 8081:80)