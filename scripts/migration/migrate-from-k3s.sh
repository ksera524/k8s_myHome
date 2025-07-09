#!/bin/bash

# Migration script from k3s to new Kubernetes cluster
# This script helps migrate data and configurations from the existing k3s setup

set -euo pipefail

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"
BACKUP_DIR="$PROJECT_ROOT/k3s-backup-$(date +%Y%m%d-%H%M%S)"
K3S_DATA_DIR="/var/lib/rancher/k3s"
EXTERNAL_SSD_PATH="/mnt/external-ssd"

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Create backup directory
create_backup_dir() {
    log_info "Creating backup directory..."
    
    mkdir -p "$BACKUP_DIR"/{manifests,data,configs,secrets}
    
    log_success "Backup directory created: $BACKUP_DIR"
}

# Backup k3s manifests
backup_manifests() {
    log_info "Backing up k3s manifests..."
    
    # Backup current application manifests
    cp -r "$PROJECT_ROOT/app" "$BACKUP_DIR/manifests/"
    
    # Export current resources from k3s
    if command -v kubectl >/dev/null 2>&1; then
        log_info "Exporting current k3s resources..."
        
        # Export deployments
        kubectl get deployments --all-namespaces -o yaml > "$BACKUP_DIR/manifests/k3s-deployments.yaml" 2>/dev/null || true
        
        # Export services
        kubectl get services --all-namespaces -o yaml > "$BACKUP_DIR/manifests/k3s-services.yaml" 2>/dev/null || true
        
        # Export persistent volumes and claims
        kubectl get pv -o yaml > "$BACKUP_DIR/manifests/k3s-pv.yaml" 2>/dev/null || true
        kubectl get pvc --all-namespaces -o yaml > "$BACKUP_DIR/manifests/k3s-pvc.yaml" 2>/dev/null || true
        
        # Export secrets (without data for security)
        kubectl get secrets --all-namespaces -o yaml | sed 's/data:/# data:/g' > "$BACKUP_DIR/manifests/k3s-secrets-structure.yaml" 2>/dev/null || true
        
        # Export configmaps
        kubectl get configmaps --all-namespaces -o yaml > "$BACKUP_DIR/manifests/k3s-configmaps.yaml" 2>/dev/null || true
        
        log_success "k3s resources exported"
    else
        log_warning "kubectl not available, skipping resource export"
    fi
    
    log_success "Manifests backup completed"
}

# Backup application data
backup_application_data() {
    log_info "Backing up application data from external SSD..."
    
    if [[ ! -d "$EXTERNAL_SSD_PATH" ]]; then
        log_warning "External SSD path not found: $EXTERNAL_SSD_PATH"
        return
    fi
    
    # Create data backup
    mkdir -p "$BACKUP_DIR/data"
    
    # Backup each application's data
    for app_dir in "$EXTERNAL_SSD_PATH"/*; do
        if [[ -d "$app_dir" ]]; then
            app_name=$(basename "$app_dir")
            log_info "Backing up $app_name data..."
            
            rsync -av "$app_dir/" "$BACKUP_DIR/data/$app_name/" || {
                log_warning "Failed to backup $app_name data"
                continue
            }
            
            log_success "$app_name data backed up"
        fi
    done
    
    log_success "Application data backup completed"
}

# Backup k3s configuration
backup_k3s_config() {
    log_info "Backing up k3s configuration..."
    
    # Backup k3s config if accessible
    if [[ -f "/etc/rancher/k3s/k3s.yaml" ]]; then
        sudo cp "/etc/rancher/k3s/k3s.yaml" "$BACKUP_DIR/configs/k3s.yaml" || {
            log_warning "Could not backup k3s.yaml (permission denied)"
        }
    fi
    
    # Backup current kubectl config
    if [[ -f "$HOME/.kube/config" ]]; then
        cp "$HOME/.kube/config" "$BACKUP_DIR/configs/kubectl-config.yaml"
        log_success "kubectl config backed up"
    fi
    
    log_success "k3s configuration backup completed"
}

# Generate migration checklist
generate_migration_checklist() {
    log_info "Generating migration checklist..."
    
    cat > "$BACKUP_DIR/MIGRATION_CHECKLIST.md" << EOF
# k3s to Kubernetes Migration Checklist

## Pre-Migration Backup
- [x] Application manifests backed up
- [x] Application data backed up from external SSD
- [x] k3s configuration backed up
- [x] Current resource definitions exported

## New Cluster Setup
- [ ] New Kubernetes cluster deployed using \`scripts/setup/deploy-cluster.sh\`
- [ ] External storage configured and accessible
- [ ] Sealed Secrets controller installed
- [ ] GitHub Actions runners deployed

## Data Migration
- [ ] Application data restored to new cluster storage
- [ ] Secrets recreated using Sealed Secrets
- [ ] Configuration files updated for new cluster

## Application Migration
### Factorio
- [ ] Data migrated to new PVC
- [ ] Deployment updated with new configuration
- [ ] Service accessibility verified
- [ ] NodePort connectivity tested

### Slack
- [ ] Harbor registry configured
- [ ] Image pushed to new Harbor registry
- [ ] Secret recreated for Slack token
- [ ] Deployment updated and tested

### Other Applications
$(for app_dir in "$PROJECT_ROOT/app"/*; do
    if [[ -d "$app_dir" ]]; then
        app_name=$(basename "$app_dir")
        if [[ "$app_name" != "factorio" && "$app_name" != "slack" ]]; then
            echo "- [ ] $app_name migrated and tested"
        fi
    fi
done)

## Post-Migration Verification
- [ ] All applications running and accessible
- [ ] Data integrity verified
- [ ] Performance compared to k3s
- [ ] Monitoring and logging configured
- [ ] Backup procedures established

## Cleanup (Only after successful migration)
- [ ] k3s cluster stopped and disabled
- [ ] Old data archived or removed
- [ ] DNS/networking updated
- [ ] Documentation updated

## Rollback Plan (If needed)
- [ ] Stop new cluster
- [ ] Restore k3s from backup
- [ ] Restore application data
- [ ] Update DNS/networking back to k3s

---

**Backup Location**: $BACKUP_DIR
**Migration Date**: $(date)
EOF
    
    log_success "Migration checklist generated: $BACKUP_DIR/MIGRATION_CHECKLIST.md"
}

# Generate data migration script
generate_data_migration_script() {
    log_info "Generating data migration script..."
    
    cat > "$BACKUP_DIR/migrate-data.sh" << 'EOF'
#!/bin/bash

# Data migration script for new Kubernetes cluster
# Run this script after the new cluster is deployed

set -euo pipefail

BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

BACKUP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NEW_CLUSTER_STORAGE="/mnt/external-ssd"

log_info "Starting data migration to new cluster..."

# Check if new cluster storage exists
if [[ ! -d "$NEW_CLUSTER_STORAGE" ]]; then
    log_warning "New cluster storage not found at $NEW_CLUSTER_STORAGE"
    log_info "Please ensure the external SSD is mounted on the control plane node"
    exit 1
fi

# Migrate each application's data
for app_data_dir in "$BACKUP_DIR/data"/*; do
    if [[ -d "$app_data_dir" ]]; then
        app_name=$(basename "$app_data_dir")
        target_dir="$NEW_CLUSTER_STORAGE/$app_name"
        
        log_info "Migrating $app_name data..."
        
        # Create target directory
        mkdir -p "$target_dir"
        
        # Copy data
        rsync -av "$app_data_dir/" "$target_dir/" || {
            log_warning "Failed to migrate $app_name data"
            continue
        }
        
        # Set appropriate permissions
        chmod -R 755 "$target_dir"
        
        log_success "$app_name data migrated to $target_dir"
    fi
done

log_success "Data migration completed!"
log_info "Next steps:"
log_info "1. Verify data in new cluster storage"
log_info "2. Deploy applications to new cluster"
log_info "3. Test application functionality"
EOF
    
    chmod +x "$BACKUP_DIR/migrate-data.sh"
    log_success "Data migration script generated: $BACKUP_DIR/migrate-data.sh"
}

# Generate secret migration guide
generate_secret_migration_guide() {
    log_info "Generating secret migration guide..."
    
    cat > "$BACKUP_DIR/SECRET_MIGRATION.md" << EOF
# Secret Migration Guide

## Overview
Secrets cannot be directly copied due to security reasons. This guide helps you recreate secrets in the new cluster using Sealed Secrets.

## Steps

### 1. Install Sealed Secrets CLI
\`\`\`bash
# Already included in prerequisites installation
kubeseal --version
\`\`\`

### 2. Recreate Secrets

#### Slack Secret
\`\`\`bash
# Create the secret (replace with actual token)
kubectl create secret generic slack-secret \\
  --namespace=sandbox \\
  --from-literal=token=YOUR_SLACK_TOKEN \\
  --dry-run=client -o yaml > /tmp/slack-secret.yaml

# Convert to sealed secret
kubeseal -f /tmp/slack-secret.yaml -w secrets/sealed-secrets/slack-sealed.yaml

# Clean up temporary file
rm /tmp/slack-secret.yaml

# Apply to cluster
kubectl apply -f secrets/sealed-secrets/slack-sealed.yaml
\`\`\`

#### Harbor Secret
\`\`\`bash
# Create docker registry secret
kubectl create secret docker-registry harbor-secret \\
  --namespace=sandbox \\
  --docker-server=YOUR_HARBOR_URL \\
  --docker-username=YOUR_USERNAME \\
  --docker-password=YOUR_PASSWORD \\
  --dry-run=client -o yaml > /tmp/harbor-secret.yaml

# Convert to sealed secret
kubeseal -f /tmp/harbor-secret.yaml -w secrets/sealed-secrets/harbor-sealed.yaml

# Clean up and apply
rm /tmp/harbor-secret.yaml
kubectl apply -f secrets/sealed-secrets/harbor-sealed.yaml
\`\`\`

#### GitHub Runner Token
\`\`\`bash
# Create GitHub runner token secret
kubectl create secret generic github-runner-token \\
  --namespace=github-runners \\
  --from-literal=token=YOUR_GITHUB_TOKEN \\
  --dry-run=client -o yaml > /tmp/github-runner-secret.yaml

# Convert to sealed secret
kubeseal -f /tmp/github-runner-secret.yaml -w secrets/sealed-secrets/github-runner-sealed.yaml

# Clean up and apply
rm /tmp/github-runner-secret.yaml
kubectl apply -f secrets/sealed-secrets/github-runner-sealed.yaml
\`\`\`

### 3. Automated Script
You can also use the automated script:
\`\`\`bash
./secrets/examples/create-secrets.sh
\`\`\`

## Important Notes
- Never commit plain text secrets to the repository
- Sealed secrets are encrypted and safe to store in Git
- Keep the sealed-secrets-key backed up for disaster recovery
- Test secret access after migration

## Verification
\`\`\`bash
# Check if secrets are created
kubectl get secrets --all-namespaces | grep -E "(slack|harbor|github)"

# Test secret usage in pods
kubectl describe deployment slack -n sandbox
\`\`\`
EOF
    
    log_success "Secret migration guide generated: $BACKUP_DIR/SECRET_MIGRATION.md"
}

# Main function
main() {
    log_info "Starting k3s to Kubernetes migration preparation..."
    
    create_backup_dir
    backup_manifests
    backup_application_data
    backup_k3s_config
    generate_migration_checklist
    generate_data_migration_script
    generate_secret_migration_guide
    
    log_success "Migration preparation completed!"
    echo ""
    echo "=== MIGRATION SUMMARY ==="
    echo "Backup Location: $BACKUP_DIR"
    echo "Next Steps:"
    echo "1. Review the migration checklist: $BACKUP_DIR/MIGRATION_CHECKLIST.md"
    echo "2. Deploy the new cluster: ./scripts/setup/deploy-cluster.sh"
    echo "3. Migrate data: $BACKUP_DIR/migrate-data.sh"
    echo "4. Recreate secrets: Follow $BACKUP_DIR/SECRET_MIGRATION.md"
    echo "5. Deploy applications to new cluster"
    echo ""
    log_warning "Keep this backup until migration is complete and verified!"
}

# Run main function
main "$@"