#!/bin/bash
# Test script for Harbor push functionality

set -e

echo "=== Testing Harbor Push Functionality ==="

# Get Harbor credentials from Kubernetes
echo "Getting Harbor credentials..."
HARBOR_PASSWORD=$(ssh -o StrictHostKeyChecking=no k8suser@192.168.122.10 'kubectl get secret harbor-admin-secret -n harbor -o jsonpath="{.data.password}" | base64 -d')

# Test with skopeo
echo "Testing push with skopeo..."
echo "Creating test image..."
docker pull alpine:latest 2>/dev/null || true
docker tag alpine:latest test-image:latest

# Save image
docker save test-image:latest > /tmp/test-image.tar

# Check if harbor.local is in /etc/hosts
if ! grep -q "harbor.local" /etc/hosts 2>/dev/null; then
  echo "Note: harbor.local not in /etc/hosts, using IP directly"
  HARBOR_HOST="192.168.122.100"
else
  HARBOR_HOST="harbor.local"
fi

# Push with skopeo
echo "Pushing to Harbor at ${HARBOR_HOST}..."
skopeo copy --insecure-policy --dest-tls-verify=false \
  --dest-creds="admin:${HARBOR_PASSWORD}" \
  docker-archive:/tmp/test-image.tar \
  docker://${HARBOR_HOST}:80/sandbox/test-image:latest

if [ $? -eq 0 ]; then
  echo "✅ SUCCESS: Image pushed to Harbor successfully!"
else
  echo "❌ FAILED: Could not push image to Harbor"
  exit 1
fi

# Cleanup
rm -f /tmp/test-image.tar
docker rmi test-image:latest 2>/dev/null || true

echo "=== Test Complete ==="