# k8s_myHome Makefile
# Kubernetes home infrastructure automation
# This delegates all commands to automation/Makefile

# すべてのターゲットをautomation/Makefileに委譲
%:
	@$(MAKE) -C automation $@

# デフォルトターゲット
.DEFAULT_GOAL := help