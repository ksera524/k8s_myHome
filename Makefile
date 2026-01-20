# k8s_myHome Makefile (task runner)

.DEFAULT_GOAL := help

.PHONY: help all phase1 phase2 phase3 phase4 phase5 vm k8s gitops-prep gitops-apps verify
.PHONY: add-runner add-runners-all all-runner

help:
	@echo "k8s_myHome task runner"
	@echo ""
	@echo "Phases:"
	@echo "  make all                 - Phase 1〜5を順番に実行"
	@echo "  make phase1 / make vm     - VMの構成"
	@echo "  make phase2 / make k8s    - k8sの構成"
	@echo "  make phase3 / make gitops-prep  - GitOps準備"
	@echo "  make phase4 / make gitops-apps  - GitOpsアプリ展開"
	@echo "  make phase5 / make verify       - 確認"
	@echo ""
	@echo "Runners:"
	@echo "  make add-runner REPO=<name>     - GitHub Actions Runner追加"
	@echo "  make add-runners-all            - settings.tomlから一括Runner追加"

all:
	@./automation/scripts/run.sh all

phase1 vm:
	@./automation/scripts/run.sh phase1

phase2 k8s:
	@./automation/scripts/run.sh phase2

phase3 gitops-prep:
	@./automation/scripts/run.sh phase3

phase4 gitops-apps:
	@./automation/scripts/run.sh phase4

phase5 verify:
	@./automation/scripts/run.sh phase5

add-runner:
	@if [ -z "$(REPO)" ]; then \
		echo "REPO変数が必要です (例: make add-runner REPO=my-project)"; \
		exit 1; \
	fi
	@bash -c 'source automation/scripts/settings-loader.sh load 2>/dev/null || true; cd automation/scripts/github-actions && ./add-runner.sh "$(REPO)"'

add-runners-all:
	@bash -c 'source automation/scripts/settings-loader.sh load 2>/dev/null || true; cd automation/scripts/github-actions && ./add-runners-bulk.sh'
