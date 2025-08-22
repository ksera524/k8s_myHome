# k8s_myHome Makefile
# Kubernetes home infrastructure automation

.PHONY: all clean add-runner help

# デフォルトターゲット
help:
	@echo "k8s_myHome - Kubernetes Home Infrastructure"
	@echo ""
	@echo "利用可能なコマンド:"
	@echo "  make all         - 完全なインフラストラクチャを構築"
	@echo "  make add-runner  - GitHub Actions Runner を追加 (REPO=リポジトリ名)"
	@echo "  make clean       - インフラストラクチャを削除"
	@echo "  make help        - このヘルプを表示"
	@echo ""
	@echo "例:"
	@echo "  make add-runner REPO=my-awesome-project"

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

# クリーンアップ
clean:
	@echo "=== インフラストラクチャ削除 ==="
	@echo "警告: これによりすべてのVMとデータが削除されます"
	@echo "続行するには Ctrl+C でキャンセル、Enter で続行"
	@read confirm
	cd automation/infrastructure && terraform destroy -auto-approve