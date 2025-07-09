#!/bin/bash

# Comprehensive Kubernetes cluster health check script
# This script performs various health checks and generates a detailed report

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
REPORT_FILE="$PROJECT_ROOT/cluster-health-report-$(date +%Y%m%d-%H%M%S).md"

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

# Initialize report
init_report() {
    cat > "$REPORT_FILE" << EOF
# Kubernetes Cluster Health Report

**Generated**: $(date)
**Cluster**: k8s-home

---

EOF
}

# Add section to report
add_section() {
    local title="$1"
    local content="$2"
    
    cat >> "$REPORT_FILE" << EOF
## $title

\`\`\`
$content
\`\`\`

EOF
}

# Check cluster connectivity
check_connectivity() {
    log_info "Checking cluster connectivity..."
    
    local status="✅ HEALTHY"
    local output=""
    
    if ! output=$(kubectl cluster-info 2>&1); then
        status="❌ UNHEALTHY"
        log_error "Failed to connect to cluster"
    else
        log_success "Cluster connectivity OK"
    fi
    
    add_section "Cluster Connectivity - $status" "$output"
}

# Check node status
check_nodes() {
    log_info "Checking node status..."
    
    local output
    output=$(kubectl get nodes -o wide)
    
    local ready_nodes
    ready_nodes=$(kubectl get nodes --no-headers | grep -c "Ready" || echo "0")
    
    local total_nodes
    total_nodes=$(kubectl get nodes --no-headers | wc -l)
    
    local status="✅ HEALTHY ($ready_nodes/$total_nodes ready)"
    
    if [[ $ready_nodes -ne $total_nodes ]]; then
        status="❌ UNHEALTHY ($ready_nodes/$total_nodes ready)"
        log_warning "Not all nodes are ready: $ready_nodes/$total_nodes"
    else
        log_success "All nodes are ready: $ready_nodes/$total_nodes"
    fi
    
    add_section "Node Status - $status" "$output"
}

# Check system pods
check_system_pods() {
    log_info "Checking system pods..."
    
    local output
    output=$(kubectl get pods -n kube-system -o wide)
    
    local running_pods
    running_pods=$(kubectl get pods -n kube-system --no-headers | grep -c "Running" || echo "0")
    
    local total_pods
    total_pods=$(kubectl get pods -n kube-system --no-headers | wc -l)
    
    local failed_pods
    failed_pods=$(kubectl get pods -n kube-system --no-headers | grep -E "(Error|CrashLoopBackOff|ImagePullBackOff)" | wc -l || echo "0")
    
    local status="✅ HEALTHY ($running_pods/$total_pods running)"
    
    if [[ $failed_pods -gt 0 ]]; then
        status="❌ UNHEALTHY ($failed_pods failed, $running_pods/$total_pods running)"
        log_warning "Found $failed_pods failed system pods"
    else
        log_success "All system pods are healthy: $running_pods/$total_pods running"
    fi
    
    add_section "System Pods - $status" "$output"
}

# Check application pods
check_application_pods() {
    log_info "Checking application pods..."
    
    local output
    output=$(kubectl get pods --all-namespaces -o wide | grep -v kube-system)
    
    local running_pods
    running_pods=$(kubectl get pods --all-namespaces --no-headers | grep -v kube-system | grep -c "Running" || echo "0")
    
    local total_pods
    total_pods=$(kubectl get pods --all-namespaces --no-headers | grep -v kube-system | wc -l)
    
    local failed_pods
    failed_pods=$(kubectl get pods --all-namespaces --no-headers | grep -v kube-system | grep -E "(Error|CrashLoopBackOff|ImagePullBackOff)" | wc -l || echo "0")
    
    local status="✅ HEALTHY ($running_pods/$total_pods running)"
    
    if [[ $failed_pods -gt 0 ]]; then
        status="❌ UNHEALTHY ($failed_pods failed, $running_pods/$total_pods running)"
        log_warning "Found $failed_pods failed application pods"
    else
        log_success "All application pods are healthy: $running_pods/$total_pods running"
    fi
    
    add_section "Application Pods - $status" "$output"
}

# Check services
check_services() {
    log_info "Checking services..."
    
    local output
    output=$(kubectl get services --all-namespaces -o wide)
    
    local total_services
    total_services=$(kubectl get services --all-namespaces --no-headers | wc -l)
    
    log_success "Found $total_services services"
    
    add_section "Services - ✅ HEALTHY ($total_services services)" "$output"
}

# Check storage
check_storage() {
    log_info "Checking storage..."
    
    local pv_output
    pv_output=$(kubectl get pv -o wide 2>/dev/null || echo "No persistent volumes found")
    
    local pvc_output
    pvc_output=$(kubectl get pvc --all-namespaces -o wide 2>/dev/null || echo "No persistent volume claims found")
    
    local sc_output
    sc_output=$(kubectl get storageclass -o wide)
    
    local bound_pvs
    bound_pvs=$(kubectl get pv --no-headers 2>/dev/null | grep -c "Bound" || echo "0")
    
    local total_pvs
    total_pvs=$(kubectl get pv --no-headers 2>/dev/null | wc -l || echo "0")
    
    local status="✅ HEALTHY ($bound_pvs/$total_pvs PVs bound)"
    
    if [[ $total_pvs -gt 0 && $bound_pvs -ne $total_pvs ]]; then
        status="⚠️ WARNING ($bound_pvs/$total_pvs PVs bound)"
        log_warning "Not all persistent volumes are bound: $bound_pvs/$total_pvs"
    else
        log_success "Storage is healthy"
    fi
    
    add_section "Storage Classes - $status" "$sc_output"
    add_section "Persistent Volumes" "$pv_output"
    add_section "Persistent Volume Claims" "$pvc_output"
}

# Check resource usage
check_resource_usage() {
    log_info "Checking resource usage..."
    
    local node_usage
    if node_usage=$(kubectl top nodes 2>/dev/null); then
        add_section "Node Resource Usage - ✅ AVAILABLE" "$node_usage"
        log_success "Node resource usage collected"
    else
        add_section "Node Resource Usage - ❌ UNAVAILABLE" "Metrics server not available or not responding"
        log_warning "Could not collect node resource usage (metrics server may not be installed)"
    fi
    
    local pod_usage
    if pod_usage=$(kubectl top pods --all-namespaces 2>/dev/null); then
        add_section "Pod Resource Usage - ✅ AVAILABLE" "$pod_usage"
        log_success "Pod resource usage collected"
    else
        add_section "Pod Resource Usage - ❌ UNAVAILABLE" "Metrics server not available or not responding"
        log_warning "Could not collect pod resource usage (metrics server may not be installed)"
    fi
}

# Check events
check_events() {
    log_info "Checking recent events..."
    
    local warning_events
    warning_events=$(kubectl get events --all-namespaces --field-selector type=Warning --sort-by='.lastTimestamp' 2>/dev/null || echo "No warning events found")
    
    local error_count
    error_count=$(kubectl get events --all-namespaces --field-selector type=Warning --no-headers 2>/dev/null | wc -l || echo "0")
    
    local status="✅ HEALTHY"
    if [[ $error_count -gt 0 ]]; then
        status="⚠️ WARNING ($error_count warning events)"
        log_warning "Found $error_count warning events"
    else
        log_success "No warning events found"
    fi
    
    add_section "Recent Warning Events - $status" "$warning_events"
}

# Check specific applications
check_applications() {
    log_info "Checking specific applications..."
    
    # Check Factorio
    if kubectl get deployment factorio -n sandbox >/dev/null 2>&1; then
        local factorio_status
        factorio_status=$(kubectl get deployment factorio -n sandbox -o wide)
        
        local factorio_replicas
        factorio_replicas=$(kubectl get deployment factorio -n sandbox -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
        
        if [[ "$factorio_replicas" == "1" ]]; then
            add_section "Factorio Application - ✅ HEALTHY" "$factorio_status"
            log_success "Factorio is healthy"
        else
            add_section "Factorio Application - ❌ UNHEALTHY" "$factorio_status"
            log_error "Factorio is not healthy"
        fi
    else
        add_section "Factorio Application - ⚠️ NOT DEPLOYED" "Factorio deployment not found"
        log_info "Factorio is not deployed"
    fi
    
    # Check Slack
    if kubectl get deployment slack -n sandbox >/dev/null 2>&1; then
        local slack_status
        slack_status=$(kubectl get deployment slack -n sandbox -o wide)
        
        local slack_replicas
        slack_replicas=$(kubectl get deployment slack -n sandbox -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
        
        if [[ "$slack_replicas" == "2" ]]; then
            add_section "Slack Application - ✅ HEALTHY" "$slack_status"
            log_success "Slack is healthy"
        else
            add_section "Slack Application - ❌ UNHEALTHY" "$slack_status"
            log_error "Slack is not healthy"
        fi
    else
        add_section "Slack Application - ⚠️ NOT DEPLOYED" "Slack deployment not found"
        log_info "Slack is not deployed"
    fi
}

# Generate recommendations
generate_recommendations() {
    log_info "Generating recommendations..."
    
    cat >> "$REPORT_FILE" << EOF
## Recommendations

EOF

    # Check if metrics server is installed
    if ! kubectl get deployment metrics-server -n kube-system >/dev/null 2>&1; then
        cat >> "$REPORT_FILE" << EOF
- **Install Metrics Server**: For resource monitoring capabilities
  \`\`\`bash
  kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
  \`\`\`

EOF
    fi
    
    # Check for failed pods
    local failed_pods
    failed_pods=$(kubectl get pods --all-namespaces --no-headers | grep -E "(Error|CrashLoopBackOff|ImagePullBackOff)" | wc -l || echo "0")
    
    if [[ $failed_pods -gt 0 ]]; then
        cat >> "$REPORT_FILE" << EOF
- **Fix Failed Pods**: $failed_pods pods are in failed state
  \`\`\`bash
  kubectl get pods --all-namespaces | grep -E "(Error|CrashLoopBackOff|ImagePullBackOff)"
  \`\`\`

EOF
    fi
    
    # Check for unbound PVCs
    local unbound_pvcs
    unbound_pvcs=$(kubectl get pvc --all-namespaces --no-headers 2>/dev/null | grep -c "Pending" || echo "0")
    
    if [[ $unbound_pvcs -gt 0 ]]; then
        cat >> "$REPORT_FILE" << EOF
- **Fix Storage Issues**: $unbound_pvcs PVCs are in pending state
  \`\`\`bash
  kubectl get pvc --all-namespaces | grep Pending
  \`\`\`

EOF
    fi
    
    cat >> "$REPORT_FILE" << EOF
- **Regular Maintenance**: 
  - Monitor cluster resources regularly
  - Keep nodes and applications updated
  - Backup etcd and important data
  - Review and rotate secrets periodically

EOF
}

# Main function
main() {
    log_info "Starting comprehensive cluster health check..."
    
    # Check kubectl access
    if ! kubectl cluster-info >/dev/null 2>&1; then
        log_error "Cannot connect to Kubernetes cluster. Check your kubectl configuration."
        exit 1
    fi
    
    init_report
    check_connectivity
    check_nodes
    check_system_pods
    check_application_pods
    check_services
    check_storage
    check_resource_usage
    check_events
    check_applications
    generate_recommendations
    
    log_success "Health check completed successfully!"
    log_info "Report saved to: $REPORT_FILE"
    
    # Display summary
    echo ""
    echo "=== HEALTH CHECK SUMMARY ==="
    local total_nodes=$(kubectl get nodes --no-headers | wc -l)
    local ready_nodes=$(kubectl get nodes --no-headers | grep -c "Ready" || echo "0")
    local total_pods=$(kubectl get pods --all-namespaces --no-headers | wc -l)
    local running_pods=$(kubectl get pods --all-namespaces --no-headers | grep -c "Running" || echo "0")
    local failed_pods=$(kubectl get pods --all-namespaces --no-headers | grep -E "(Error|CrashLoopBackOff|ImagePullBackOff)" | wc -l || echo "0")
    
    echo "Nodes: $ready_nodes/$total_nodes ready"
    echo "Pods: $running_pods/$total_pods running, $failed_pods failed"
    echo "Report: $REPORT_FILE"
}

# Run main function
main "$@"