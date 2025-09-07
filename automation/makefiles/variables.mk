# k8s_myHome Variables
# 共通変数と設定値の定義

# プロジェクト基本設定
PROJECT_ROOT := $(shell pwd)
PROJECT_NAME := k8s_myHome

# ディレクトリ構造
HOST_SETUP_DIR := $(PROJECT_ROOT)/host-setup
INFRASTRUCTURE_DIR := $(PROJECT_ROOT)/infrastructure
PLATFORM_DIR := $(PROJECT_ROOT)/platform
SCRIPTS_DIR := $(PROJECT_ROOT)/scripts
MANIFESTS_DIR := $(PROJECT_ROOT)/manifests/resources

# 設定ファイル
SETTINGS_FILE := $(PROJECT_ROOT)/settings.toml
COMMON_COLORS := $(SCRIPTS_DIR)/common-colors.sh
SETTINGS_LOADER := $(SCRIPTS_DIR)/settings-loader.sh

# settings.tomlから設定を読み込み
ifneq ($(wildcard $(SETTINGS_FILE)),)
    -include $(shell source $(SETTINGS_LOADER) load >/dev/null 2>&1 && env | grep -E '^(K8S_|HARBOR_|ARGOCD_|METALLB_)' | sed 's/^/export /')
endif

# Kubernetes クラスタ設定（settings.tomlで上書き可能）
K8S_CONTROL_PLANE_IP ?= 192.168.122.10
K8S_WORKER_1_IP ?= 192.168.122.11
K8S_WORKER_2_IP ?= 192.168.122.12
K8S_USER ?= k8suser
HARBOR_IP ?= 192.168.122.100
INGRESS_IP ?= 192.168.122.101
ARGOCD_IP ?= 192.168.122.102

# SSH設定
SSH_OPTS := -o StrictHostKeyChecking=no -o BatchMode=yes -o LogLevel=ERROR -o ConnectTimeout=5

# タイムアウト設定
K8S_CLUSTER_TIMEOUT := 300
EXTERNAL_SECRETS_TIMEOUT := 180
GITOPS_SYNC_WAIT := 15

# Harbor設定
HARBOR_NAMESPACE := harbor
HARBOR_DEFAULT_PROJECT := sandbox

# ArgoCD設定  
ARGOCD_NAMESPACE := argocd
ARC_NAMESPACE := arc-systems

# カラー定義（絵文字ベース - 統一）
ROCKET := 🚀
CHECK := ✅
WARNING := ⚠️
ERROR := ❌
INFO := ℹ️
DEBUG := 🔍
GEAR := 🔧
CLOUD := ☁️
RECYCLE := 🔄

# エクスポート（シェルスクリプト用）
export PROJECT_ROOT
export K8S_CONTROL_PLANE_IP
export K8S_USER
export SSH_OPTS