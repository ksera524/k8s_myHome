# Harbor Certificate Fix for GitHub Actions

## Problem
GitHub Actions workflows fail when trying to `docker login` to Harbor at IP address `192.168.122.100` with the error:
```
failed to verify certificate: x509: cannot validate certificate for 192.168.122.100 because it doesn't contain any IP SANs
```

## Root Cause
Harbor's TLS certificate only includes the hostname `harbor.local` in the Subject Alternative Names (SAN) field, but not the IP address `192.168.122.100`. When GitHub Actions tries to connect using the IP address, certificate validation fails.

## Solution Overview
1. **Create new Harbor certificate** with both hostname and IP address in SAN field
2. **Deploy DaemonSet** to distribute Harbor's CA certificate to all nodes
3. **Configure Docker trust** on all nodes to trust Harbor's certificate
4. **Update GitHub Actions workflow** to remove insecure registry configuration

## Files Created
- `infra/cert-manager/harbor-certificate.yaml` - Certificate with IP SAN
- `infra/harbor-ca-trust.yaml` - DaemonSet for CA trust distribution
- `infra/harbor-cert-app.yaml` - ArgoCD applications for deployment
- `automation/phase4/harbor-cert-fix.sh` - Deployment script

## Deployment Steps

### 1. Apply the Certificate Fix
```bash
cd automation/phase4
./harbor-cert-fix.sh
```

### 2. Verify Certificate
```bash
# Check certificate details
kubectl get certificate harbor-tls-cert -n harbor -o yaml

# Verify IP SAN is included
kubectl get secret harbor-tls-secret -n harbor -o jsonpath='{.data.tls\.crt}' | base64 -d | openssl x509 -text -noout | grep -A5 "Subject Alternative Name"
```

### 3. Verify DaemonSet Deployment
```bash
# Check DaemonSet status
kubectl get daemonset harbor-ca-trust -n kube-system

# Check pods on all nodes
kubectl get pods -n kube-system -l app=harbor-ca-trust -o wide
```

### 4. Test Docker Login
```bash
# From any node or GitHub Actions runner
docker login 192.168.122.100 -u admin
# Should now work without certificate errors
```

## How It Works

### Certificate Configuration
The new certificate includes:
- **Common Name**: harbor.local
- **DNS Names**: harbor.local  
- **IP Addresses**: 192.168.122.100
- **Usages**: digital signature, key encipherment, server auth

### CA Trust Distribution
The DaemonSet:
- Runs on all nodes using `hostNetwork: true`
- Extracts Harbor's CA certificate from the TLS secret
- Installs it in `/etc/ssl/certs/` for system trust
- Configures Docker-specific trust in `/etc/docker/certs.d/`
- Monitors for certificate updates and automatically reinstalls

### Docker Configuration
For each registry endpoint, the DaemonSet creates:
```
/etc/docker/certs.d/192.168.122.100/ca.crt
/etc/docker/certs.d/harbor.local/ca.crt
```

## GitHub Actions Changes
The workflow no longer needs insecure registry configuration:
```yaml
# OLD (removed)
- name: Setup Docker for Harbor
  run: |
    sudo tee /etc/docker/daemon.json <<EOL
    {
      "insecure-registries": ["192.168.122.100"]
    }
    EOL

# NEW
- name: Verify Harbor certificate trust
  run: |
    echo "Checking Harbor certificate trust..."
    docker info | grep -i "insecure" || echo "No insecure registries configured"
```

## Verification Commands

### Check Certificate SAN
```bash
kubectl get secret harbor-tls-secret -n harbor -o jsonpath='{.data.tls\.crt}' | base64 -d | openssl x509 -text -noout | grep -A10 "Subject Alternative Name"
```

Expected output should include:
```
X509v3 Subject Alternative Name:
    DNS:harbor.local, IP Address:192.168.122.100
```

### Verify CA Trust on Nodes
```bash
# Check system trust store
ls -la /etc/ssl/certs/harbor-ca.crt

# Check Docker trust configuration
ls -la /etc/docker/certs.d/192.168.122.100/ca.crt
ls -la /etc/docker/certs.d/harbor.local/ca.crt
```

### Test Connection
```bash
# Test HTTPS connection with proper certificate validation
curl -v https://192.168.122.100/api/v2.0/systeminfo

# Test Docker login
docker login 192.168.122.100 -u admin
```

## Troubleshooting

### Certificate Not Ready
```bash
kubectl describe certificate harbor-tls-cert -n harbor
kubectl describe certificaterequest -n harbor
```

### DaemonSet Issues
```bash
kubectl logs daemonset/harbor-ca-trust -n kube-system
kubectl describe daemonset harbor-ca-trust -n kube-system
```

### Docker Login Still Fails
```bash
# Check if CA certificate is properly installed
docker exec <runner-pod> ls -la /etc/docker/certs.d/192.168.122.100/
docker exec <runner-pod> cat /etc/docker/certs.d/192.168.122.100/ca.crt
```

## Security Notes
- This solution uses self-signed certificates appropriate for internal development environments
- The DaemonSet runs with privileged access to install system certificates
- For production environments, consider using proper CA-signed certificates
- The solution maintains security by properly validating certificates instead of using insecure registries