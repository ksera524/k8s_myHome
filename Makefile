# k8s_myHome Makefile
# Kubernetes home infrastructure automation

.PHONY: all clean add-runner help redeploy-k8s redeploy-platform

# デフォルトターゲット
help:
	@echo "k8s_myHome - Kubernetes Home Infrastructure"
	@echo ""
	@echo "利用可能なコマンド:"
	@echo "  make all              - 完全なインフラストラクチャを構築"
	@echo "  make redeploy-k8s     - K8sクラスターのみ再構築（VMはそのまま）"
	@echo "  make redeploy-platform - プラットフォームのみ再デプロイ"
	@echo "  make add-runner       - GitHub Actions Runner を追加 (REPO=リポジトリ名)"
	@echo "  make clean            - インフラストラクチャを削除"
	@echo "  make help             - このヘルプを表示"
	@echo ""
	@echo "例:"
	@echo "  make add-runner REPO=my-awesome-project"
	@echo "  make redeploy-k8s     # テスト時の短縮デプロイ"

# 完全なインフラストラクチャ構築
all:
	@echo "=== k8s_myHome 完全構築開始 ==="
	@echo "Phase 1: ホストセットアップ"
	cd automation/host-setup && ./setup-host.sh
	cd automation/host-setup && ./setup-storage.sh
	cd automation/host-setup && ./verify-setup.sh
	@echo ""
	@echo "Phase 2-3: インフラストラクチャ構築（VM + Kubernetes）"
	cd automation/infrastructure && ./clean-and-deploy.sh
	@echo ""
	@echo "Phase 4: プラットフォーム構築"
	cd automation/platform && ./platform-deploy.sh
	@echo ""
	@echo "=== 構築完了 ==="

# GitHub Actions Runner 追加
add-runner:
ifndef REPO
	@echo "エラー: REPO パラメータが必要です"
	@echo "使用方法: make add-runner REPO=your-repository-name"
	@exit 1
else
	@echo "=== GitHub Actions Runner 追加: $(REPO) ==="
	cd automation/scripts/github-actions && ./add-runner.sh $(REPO)
endif

# Kubernetesクラスターのみ再構築（VMはそのまま）
redeploy-k8s:
	@echo "=== Kubernetesクラスター再構築（VMはそのまま） ==="
	@echo "既存のVMを使用してKubernetesクラスターを再構築します"
	cd automation/infrastructure && ./redeploy-k8s-only.sh
	@echo ""
	@echo "=== Kubernetesクラスター再構築完了 ==="

# プラットフォームのみ再デプロイ
redeploy-platform:
	@echo "=== プラットフォーム再デプロイ ==="
	@echo "既存のKubernetesクラスターにプラットフォームを再デプロイします"
	cd automation/platform && ./platform-deploy.sh
	@echo ""
	@echo "=== プラットフォーム再デプロイ完了 ==="

# クリーンアップ
clean:
	@echo "=== インフラストラクチャ削除 ==="
	@echo "警告: これによりすべてのVMとデータが削除されます"
	@echo "続行するには Ctrl+C でキャンセル、Enter で続行"
	@read confirm
	cd automation/infrastructure && terraform destroy -auto-approve