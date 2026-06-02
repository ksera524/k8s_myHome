# k8s_myHome Makefile (task runner)

.DEFAULT_GOAL := help

.PHONY: help all phase1 phase2 bootstrap phase3 phase4 phase5 vm k8s gitops-prep gitops-apps verify recover diagrams validate validate-local
.PHONY: upgrade upgrade-safe upgrade-precheck upgrade-control-plane upgrade-workers upgrade-postcheck
.PHONY: containerd-precheck containerd-safe

help:
	@echo "k8s_myHome task runner"
	@echo ""
	@echo "Phases:"
	@echo "  make all                 - phase1 -> phase2 -> bootstrap -> phase5を順番に実行"
	@echo "  make phase1 / make vm     - VMの構成"
	@echo "  make phase2 / make k8s    - k8sの構成"
	@echo "  make bootstrap            - GitOps bootstrap（ArgoCD + root Application）"
	@echo "  make phase3 / make gitops-prep  - bootstrap互換入口"
	@echo "  make phase4 / make gitops-apps  - root Application再適用"
	@echo "  make phase5 / make verify       - 確認"
	@echo "  make validate                   - Dockerized NixでCI相当の検証"
	@echo "  make validate-local             - ローカル導入済みtoolchainで検証"
	@echo "  make recover                    - Ubuntu再起動後のk8s復旧"
	@echo "  make diagrams                   - クラスタ全体構成図を生成 (cluster-diagram.png)"

all:
	@./automation/scripts/run.sh all

phase1 vm:
	@./automation/scripts/run.sh phase1

phase2 k8s:
	@./automation/scripts/run.sh phase2

bootstrap:
	@./automation/scripts/run.sh bootstrap

phase3 gitops-prep:
	@./automation/scripts/run.sh phase3

phase4 gitops-apps:
	@./automation/scripts/run.sh phase4

phase5 verify:
	@./automation/scripts/run.sh phase5

validate:
	@docker run --rm -v "$$PWD":/work -w /work nixos/nix:2.24.11 nix --extra-experimental-features 'nix-command flakes' develop path:/work#default --command automation/scripts/ci/validate.sh

validate-local:
	@automation/scripts/ci/validate.sh

recover:
	@./automation/scripts/recover-after-reboot.sh

diagrams:
	@./automation/scripts/generate-cluster-diagram.sh

upgrade:
	@./automation/scripts/run.sh upgrade

upgrade-safe:
	@./automation/scripts/run.sh upgrade-safe

upgrade-precheck:
	@./automation/scripts/run.sh upgrade-precheck

upgrade-control-plane:
	@./automation/scripts/run.sh upgrade-control-plane

upgrade-workers:
	@./automation/scripts/run.sh upgrade-workers

upgrade-postcheck:
	@./automation/scripts/run.sh upgrade-postcheck

containerd-precheck:
	@./automation/scripts/run.sh containerd-precheck

containerd-safe:
	@./automation/scripts/run.sh containerd-safe
