#!/bin/bash
# Test script for Harbor accessibility

echo "=== Testing Harbor Accessibility ==="

# Test 1: Access via IP
echo "Test 1: Accessing Harbor via IP (192.168.122.100)..."
curl -s -o /dev/null -w "HTTP Status: %{http_code}\n" http://192.168.122.100/api/v2.0/systeminfo

# Test 2: Access via harbor.local (requires /etc/hosts entry or DNS)
echo -e "\nTest 2: Accessing Harbor via harbor.local..."
curl -s -o /dev/null -w "HTTP Status: %{http_code}\n" -H "Host: harbor.local" http://192.168.122.100/api/v2.0/systeminfo

# Test 3: Check Bearer token endpoint
echo -e "\nTest 3: Checking token endpoint with harbor.local..."
HARBOR_PASSWORD=$(ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 'kubectl get secret harbor-admin-secret -n harbor -o jsonpath="{.data.password}" | base64 -d')
curl -s -o /dev/null -w "HTTP Status: %{http_code}\n" -u "admin:${HARBOR_PASSWORD}" -H "Host: harbor.local" http://192.168.122.100/service/token?service=harbor-registry

# Test 4: Check EXT_ENDPOINT configuration
echo -e "\nTest 4: Checking current EXT_ENDPOINT configuration..."
ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 'echo "ConfigMap EXT_ENDPOINT: $(kubectl get cm harbor-core -n harbor -o jsonpath=\"{.data.EXT_ENDPOINT}\")"'
ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 'echo "Deployment ENV EXT_ENDPOINT: $(kubectl get deployment harbor-core -n harbor -o jsonpath=\"{.spec.template.spec.containers[0].env[?(@.name==\\\"EXT_ENDPOINT\\\")].value}\")"'

echo -e "\n=== Test Complete ===\n"
echo "Summary:"
echo "- If HTTP Status 200: Harbor is accessible"
echo "- If HTTP Status 404: Harbor is not routing correctly"  
echo "- ConfigMap should show: http://harbor.local"
echo "- Deployment ENV should show: http://harbor.local"