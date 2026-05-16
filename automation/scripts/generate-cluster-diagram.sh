#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
OUTPUT_FILE="$ROOT_DIR/cluster-diagram.png"

# 共通関数読み込み
source "$SCRIPT_DIR/common-logging.sh"
source "$SCRIPT_DIR/common-ssh.sh"

check_dependencies() {
  if ! command -v ssh >/dev/null 2>&1; then
    log_error "ssh コマンドが見つかりません"
    exit 1
  fi

  if command -v kube-diagrams >/dev/null 2>&1; then
    DIAGRAM_MODE="local"
    log_status "kube-diagrams (ローカル) を使用します"
    return 0
  fi

  if command -v docker >/dev/null 2>&1; then
    DIAGRAM_MODE="docker"
    log_status "kube-diagrams (Docker) を使用します"
    return 0
  fi

  log_error "kube-diagrams も docker も見つかりません"
  log_error "例: pip install KubeDiagrams または docker install を実施してください"
  exit 1
}

append_resource_yaml() {
  local resource="$1"
  local temp_yaml="$2"
  local fetched

  if fetched="$(k8s_ssh_control "kubectl get $resource --all-namespaces -o yaml" 2>/dev/null)"; then
    printf "%s\n" "$fetched" >> "$temp_yaml"
    printf "%s\n" "---" >> "$temp_yaml"
    log_info "取得成功: $resource"
  else
    log_warning "取得スキップ: $resource (未導入または取得不可)"
  fi
}

generate_diagram() {
  local input_yaml="$1"

  case "$DIAGRAM_MODE" in
    local)
      kube-diagrams - -o "$OUTPUT_FILE" < "$input_yaml"
      ;;
    docker)
      docker run --rm -i -v "$ROOT_DIR:/work" philippemerle/kubediagrams \
        kube-diagrams - -o /work/cluster-diagram.png < "$input_yaml"
      ;;
    *)
      log_error "不正な DIAGRAM_MODE: $DIAGRAM_MODE"
      exit 1
      ;;
  esac
}

main() {
  local temp_yaml
  temp_yaml="$(mktemp)"
  trap "rm -f '$temp_yaml'" EXIT

  check_dependencies

  log_status "クラスタ構成情報の収集中..."

  # Pod/ReplicaSet を大量に含めると図が巨大化するため、主要リソースを選択して収集する
  append_resource_yaml "namespaces,nodes,deployments,statefulsets,daemonsets,services,configmaps,secrets,serviceaccounts" "$temp_yaml"
  append_resource_yaml "ingress,networkpolicy,pvc,pv,storageclasses" "$temp_yaml"
  append_resource_yaml "applications.argoproj.io" "$temp_yaml"
  append_resource_yaml "certificates.cert-manager.io,issuers.cert-manager.io,clusterissuers.cert-manager.io" "$temp_yaml"
  append_resource_yaml "externalsecrets.external-secrets.io,secretstores.external-secrets.io,clustersecretstores.external-secrets.io" "$temp_yaml"
  append_resource_yaml "gateways.gateway.networking.k8s.io,httproutes.gateway.networking.k8s.io" "$temp_yaml"

  if [[ ! -s "$temp_yaml" ]]; then
    log_error "YAML データ取得に失敗しました。SSH 接続や kubectl 権限を確認してください"
    exit 1
  fi

  log_status "構成図を生成中..."
  generate_diagram "$temp_yaml"

  if [[ -f "$OUTPUT_FILE" ]]; then
    local size
    size="$(wc -c < "$OUTPUT_FILE")"
    log_success "構成図を生成しました: $OUTPUT_FILE (${size} bytes)"
  else
    log_error "構成図の生成に失敗しました: $OUTPUT_FILE"
    exit 1
  fi
}

main "$@"
