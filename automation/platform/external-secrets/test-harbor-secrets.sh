#!/bin/bash

# External Secrets による Harbor 認証情報テストスクリプト
# External Secrets の動作確認とSecret内容の検証を行う

set -euo pipefail

# カラー設定
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_debug() {
    echo -e "${BLUE}[DEBUG]${NC} $1"
}

print_test_result() {
    if [ $1 -eq 0 ]; then
        echo -e "  ${GREEN}✓${NC} $2"
    else
        echo -e "  ${RED}✗${NC} $2"
    fi
}

print_status "=== External Secrets Harbor 認証情報テスト ==="

FAILED_TESTS=0

# 1. External Secrets Operator 動作確認
print_status "1. External Secrets Operator 動作確認"

# ESO Pod チェック
kubectl get pods -n external-secrets-system | grep -q "external-secrets.*Running"
print_test_result $? "External Secrets Operator Pod が Running 状態"
if [ $? -ne 0 ]; then ((FAILED_TESTS++)); fi

# CRD チェック
kubectl get crd externalsecrets.external-secrets.io >/dev/null 2>&1
print_test_result $? "ExternalSecret CRD が存在"
if [ $? -ne 0 ]; then ((FAILED_TESTS++)); fi

kubectl get crd secretstores.external-secrets.io >/dev/null 2>&1
print_test_result $? "SecretStore CRD が存在"
if [ $? -ne 0 ]; then ((FAILED_TESTS++)); fi

# 2. Pulumi Access Token 確認
print_status "2. Pulumi Access Token 確認"

kubectl get secret pulumi-access-token -n external-secrets-system >/dev/null 2>&1
print_test_result $? "Pulumi Access Token が external-secrets-system namespace に存在"
if [ $? -ne 0 ]; then ((FAILED_TESTS++)); fi

kubectl get secret pulumi-access-token -n harbor >/dev/null 2>&1
print_test_result $? "Pulumi Access Token が harbor namespace に存在"
if [ $? -ne 0 ]; then ((FAILED_TESTS++)); fi

# 3. SecretStore 動作確認
print_status "3. SecretStore 動作確認"

kubectl get secretstore pulumi-esc-store -n harbor >/dev/null 2>&1
print_test_result $? "SecretStore 'pulumi-esc-store' が harbor namespace に存在"
if [ $? -ne 0 ]; then ((FAILED_TESTS++)); fi

# SecretStore が Ready 状態かチェック
SECRETSTORE_STATUS=$(kubectl get secretstore pulumi-esc-store -n harbor -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "Unknown")
if [ "$SECRETSTORE_STATUS" = "True" ]; then
    print_test_result 0 "SecretStore が Ready 状態"
else
    print_test_result 1 "SecretStore が Ready 状態 (現在: $SECRETSTORE_STATUS)"
    ((FAILED_TESTS++))
fi

# 4. ExternalSecret 同期確認
print_status "4. ExternalSecret 同期確認"

# Harbor Admin Secret
kubectl get externalsecret harbor-admin-secret -n harbor >/dev/null 2>&1
print_test_result $? "ExternalSecret 'harbor-admin-secret' が存在"
if [ $? -ne 0 ]; then ((FAILED_TESTS++)); fi

ADMIN_SECRET_STATUS=$(kubectl get externalsecret harbor-admin-secret -n harbor -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "Unknown")
if [ "$ADMIN_SECRET_STATUS" = "True" ]; then
    print_test_result 0 "harbor-admin-secret が Ready 状態"
else
    print_test_result 1 "harbor-admin-secret が Ready 状態 (現在: $ADMIN_SECRET_STATUS)"
    ((FAILED_TESTS++))
fi

# Harbor Registry Secret
kubectl get externalsecret harbor-registry-secret -n arc-systems >/dev/null 2>&1
print_test_result $? "ExternalSecret 'harbor-registry-secret' が存在"
if [ $? -ne 0 ]; then ((FAILED_TESTS++)); fi

# 5. 作成されたSecret確認
print_status "5. 作成されたSecret確認"

# Harbor Admin Secret
kubectl get secret harbor-admin-secret -n harbor >/dev/null 2>&1
print_test_result $? "Secret 'harbor-admin-secret' が harbor namespace に存在"
if [ $? -ne 0 ]; then ((FAILED_TESTS++)); fi

# Harbor Registry Secret
kubectl get secret harbor-registry-secret -n arc-systems >/dev/null 2>&1
print_test_result $? "Secret 'harbor-registry-secret' が arc-systems namespace に存在"
if [ $? -ne 0 ]; then ((FAILED_TESTS++)); fi

# Harbor HTTP Secrets
NAMESPACES=("default" "sandbox" "production" "staging")
for namespace in "${NAMESPACES[@]}"; do
    kubectl get secret harbor-http -n "$namespace" >/dev/null 2>&1
    print_test_result $? "Secret 'harbor-http' が $namespace namespace に存在"
    if [ $? -ne 0 ]; then ((FAILED_TESTS++)); fi
done

# 6. Secret内容検証
print_status "6. Secret内容検証"

# Harbor Admin Secret の username フィールド確認
ADMIN_USERNAME=$(kubectl get secret harbor-admin-secret -n harbor -o jsonpath='{.data.username}' 2>/dev/null | base64 -d 2>/dev/null || echo "")
if [ "$ADMIN_USERNAME" = "admin" ]; then
    print_test_result 0 "harbor-admin-secret の username が正しい"
else
    print_test_result 1 "harbor-admin-secret の username が正しい (現在: '$ADMIN_USERNAME')"
    ((FAILED_TESTS++))
fi

# Harbor Admin Secret の password フィールド確認
ADMIN_PASSWORD=$(kubectl get secret harbor-admin-secret -n harbor -o jsonpath='{.data.password}' 2>/dev/null | base64 -d 2>/dev/null || echo "")
if [ -n "$ADMIN_PASSWORD" ] && [ "$ADMIN_PASSWORD" != "Harbor12345" ]; then
    print_test_result 0 "harbor-admin-secret の password が設定済み（Pulumi ESCから取得）"
else
    print_test_result 1 "harbor-admin-secret の password が設定済み（Pulumi ESCから取得）"
    ((FAILED_TESTS++))
fi

# Harbor Registry Secret の .dockerconfigjson フィールド確認
DOCKER_CONFIG=$(kubectl get secret harbor-registry-secret -n arc-systems -o jsonpath='{.data.\.dockerconfigjson}' 2>/dev/null | base64 -d 2>/dev/null || echo "")
if echo "$DOCKER_CONFIG" | grep -q "192.168.122.100" && echo "$DOCKER_CONFIG" | grep -q "admin"; then
    print_test_result 0 "harbor-registry-secret の .dockerconfigjson が正しく設定済み"
else
    print_test_result 1 "harbor-registry-secret の .dockerconfigjson が正しく設定済み"
    ((FAILED_TESTS++))
fi

# 7. automation連携確認
print_status "7. automation連携確認"

# k8s-infrastructure-deploy.sh での External Secrets 使用確認
if grep -q "external-secrets/deploy-harbor-secrets.sh" "../k8s-infrastructure-deploy.sh"; then
    print_test_result 0 "k8s-infrastructure-deploy.sh が External Secrets を使用するよう更新済み"
else
    print_test_result 1 "k8s-infrastructure-deploy.sh が External Secrets を使用するよう更新済み"
    ((FAILED_TESTS++))
fi

# deploy-harbor-secrets.sh が実行可能かチェック
if [ -x "./deploy-harbor-secrets.sh" ]; then
    print_test_result 0 "deploy-harbor-secrets.sh が実行可能"
else
    print_test_result 1 "deploy-harbor-secrets.sh が実行可能"
    ((FAILED_TESTS++))
fi

# 8. テスト結果サマリー
print_status "=== テスト結果サマリー ==="

TOTAL_TESTS=18
PASSED_TESTS=$((TOTAL_TESTS - FAILED_TESTS))

echo "実行テスト数: $TOTAL_TESTS"
echo -e "成功: ${GREEN}$PASSED_TESTS${NC}"
echo -e "失敗: ${RED}$FAILED_TESTS${NC}"

if [ $FAILED_TESTS -eq 0 ]; then
    echo -e "\n${GREEN}🎉 すべてのテストが成功しました！${NC}"
    echo -e "${GREEN}External Secrets による Harbor 認証情報管理が正常に動作しています。${NC}"
    exit 0
else
    echo -e "\n${RED}⚠️  $FAILED_TESTS 個のテストが失敗しました。${NC}"
    echo -e "${YELLOW}詳細確認コマンド:${NC}"
    echo "  kubectl get externalsecrets -A"
    echo "  kubectl describe externalsecret harbor-admin-secret -n harbor"
    echo "  kubectl get events -n harbor --sort-by=.metadata.creationTimestamp"
    echo "  kubectl logs -n external-secrets-system deployment/external-secrets --tail=20"
    echo "  kubectl get secrets -A | grep pulumi-access-token"
    echo "  kubectl describe secretstore pulumi-esc-store -n harbor"
    exit 1
fi