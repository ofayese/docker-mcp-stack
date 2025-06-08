#!/bin/bash
# Security Audit Script for Docker MCP Stack
# Performs comprehensive security checks and generates a security report

# Enable strict mode
set -euo pipefail

# Constants
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
UTILS_DIR="$ROOT_DIR/scripts/utils"
REPORT_DIR="$ROOT_DIR/reports/security"

# Import utility scripts
# shellcheck disable=SC1091
source "$UTILS_DIR/validation.sh"

# Create report directory
mkdir -p "$REPORT_DIR"

# Function to check container security
check_container_security() {
    log_info "Checking container security configurations..."
    local issues=()
    
    # Check for containers running as root
    log_info "Checking for containers running as root..."
    local root_containers
    root_containers=$(docker ps --format "table {{.Names}}\t{{.Image}}" --filter "status=running" | tail -n +2)
    
    while IFS= read -r line; do
        if [[ -n "$line" ]]; then
            local container_name
            container_name=$(echo "$line" | awk '{print $1}')
            local user_info
            user_info=$(docker exec "$container_name" id -u 2>/dev/null || echo "unknown")
            
            if [[ "$user_info" == "0" ]]; then
                issues+=("Container $container_name is running as root user")
            fi
        fi
    done <<< "$root_containers"
    
    # Check for privileged containers
    log_info "Checking for privileged containers..."
    local privileged_containers
    privileged_containers=$(docker ps --format "{{.Names}}" --filter "status=running")
    
    while IFS= read -r container; do
        if [[ -n "$container" ]]; then
            local is_privileged
            is_privileged=$(docker inspect "$container" --format '{{.HostConfig.Privileged}}' 2>/dev/null || echo "false")
            
            if [[ "$is_privileged" == "true" ]]; then
                issues+=("Container $container is running in privileged mode")
            fi
        fi
    done <<< "$privileged_containers"
    
    # Check for containers with excessive capabilities
    log_info "Checking container capabilities..."
    while IFS= read -r container; do
        if [[ -n "$container" ]]; then
            local cap_add
            cap_add=$(docker inspect "$container" --format '{{.HostConfig.CapAdd}}' 2>/dev/null || echo "[]")
            
            if [[ "$cap_add" == "[SYS_ADMIN]" ]] || [[ "$cap_add" == "[ALL]" ]]; then
                issues+=("Container $container has excessive capabilities: $cap_add")
            fi
        fi
    done <<< "$privileged_containers"
    
    return_issues "${issues[@]}"
}

# Function to check network security
check_network_security() {
    log_info "Checking network security configurations..."
    local issues=()
    
    # Check for containers with host networking
    log_info "Checking for containers using host networking..."
    local containers
    containers=$(docker ps --format "{{.Names}}" --filter "status=running")
    
    while IFS= read -r container; do
        if [[ -n "$container" ]]; then
            local network_mode
            network_mode=$(docker inspect "$container" --format '{{.HostConfig.NetworkMode}}' 2>/dev/null || echo "default")
            
            if [[ "$network_mode" == "host" ]]; then
                issues+=("Container $container is using host networking")
            fi
        fi
    done <<< "$containers"
    
    # Check for exposed ports
    log_info "Checking for unnecessarily exposed ports..."
    local exposed_ports
    exposed_ports=$(docker ps --format "{{.Names}}\t{{.Ports}}" --filter "status=running")
    
    while IFS= read -r line; do
        if [[ -n "$line" ]] && [[ "$line" =~ 0\.0\.0\.0: ]]; then
            local container_name
            container_name=$(echo "$line" | cut -f1)
            issues+=("Container $container_name has ports exposed to all interfaces (0.0.0.0)")
        fi
    done <<< "$exposed_ports"
    
    return_issues "${issues[@]}"
}

# Function to check image security
check_image_security() {
    log_info "Checking image security..."
    local issues=()
    
    # Check for images using latest tag
    log_info "Checking for images using 'latest' tag..."
    local images
    images=$(docker images --format "{{.Repository}}:{{.Tag}}" | grep ":latest" || true)
    
    if [[ -n "$images" ]]; then
        while IFS= read -r image; do
            if [[ -n "$image" ]]; then
                issues+=("Image $image uses 'latest' tag (not recommended for production)")
            fi
        done <<< "$images"
    fi
    
    # Check for old/outdated images
    log_info "Checking for potentially outdated images..."
    local old_images
    old_images=$(docker images --format "{{.Repository}}:{{.Tag}}\t{{.CreatedAt}}" | awk -v date="$(date -d '90 days ago' '+%Y-%m-%d')" '$2 < date {print $1}' || true)
    
    if [[ -n "$old_images" ]]; then
        while IFS= read -r image; do
            if [[ -n "$image" ]]; then
                issues+=("Image $image appears to be older than 90 days")
            fi
        done <<< "$old_images"
    fi
    
    return_issues "${issues[@]}"
}

# Function to check secrets and credentials
check_secrets_security() {
    log_info "Checking secrets and credentials security..."
    local issues=()
    
    # Check environment files for weak passwords
    if [[ -f "$ROOT_DIR/.env" ]]; then
        log_info "Checking .env file for security issues..."
        
        # Check for default passwords
        local weak_patterns=("password" "admin" "123456" "mcp_password" "your-.*-token")
        
        for pattern in "${weak_patterns[@]}"; do
            if grep -qi "$pattern" "$ROOT_DIR/.env"; then
                issues+=("Found potential weak/default credentials in .env file")
                break
            fi
        done
        
        # Check for tokens that look like defaults
        if grep -q "your-.*-token" "$ROOT_DIR/.env"; then
            issues+=("Found default token placeholders in .env file")
        fi
    fi
    
    # Check for secrets in environment variables of running containers
    log_info "Checking running containers for exposed secrets..."
    local containers
    containers=$(docker ps --format "{{.Names}}" --filter "status=running")
    
    while IFS= read -r container; do
        if [[ -n "$container" ]]; then
            local env_vars
            env_vars=$(docker exec "$container" env 2>/dev/null | grep -i "password\|token\|secret\|key" || true)
            
            if [[ -n "$env_vars" ]]; then
                local count
                count=$(echo "$env_vars" | wc -l)
                if [[ $count -gt 0 ]]; then
                    issues+=("Container $container has $count environment variables with sensitive names")
                fi
            fi
        fi
    done <<< "$containers"
    
    return_issues "${issues[@]}"
}

# Function to check filesystem security
check_filesystem_security() {
    log_info "Checking filesystem security..."
    local issues=()
    
    # Check for containers with writable root filesystem
    log_info "Checking for containers with writable root filesystem..."
    local containers
    containers=$(docker ps --format "{{.Names}}" --filter "status=running")
    
    while IFS= read -r container; do
        if [[ -n "$container" ]]; then
            local read_only
            read_only=$(docker inspect "$container" --format '{{.HostConfig.ReadonlyRootfs}}' 2>/dev/null || echo "false")
            
            if [[ "$read_only" == "false" ]]; then
                issues+=("Container $container has writable root filesystem")
            fi
        fi
    done <<< "$containers"
    
    # Check for sensitive file permissions
    log_info "Checking file permissions..."
    local sensitive_files=(".env" ".env.secure" "nginx/ssl" "backup.sh" "restore.sh")
    
    for file in "${sensitive_files[@]}"; do
        if [[ -f "$ROOT_DIR/$file" ]] || [[ -d "$ROOT_DIR/$file" ]]; then
            local perms
            perms=$(stat -c "%a" "$ROOT_DIR/$file" 2>/dev/null || echo "unknown")
            
            if [[ "$perms" =~ ^[0-9]{3}$ ]] && [[ ${perms:2:1} -gt 4 ]]; then
                issues+=("File/directory $file has world-readable permissions ($perms)")
            fi
        fi
    done
    
    return_issues "${issues[@]}"
}

# Function to check SSL/TLS configuration
check_ssl_security() {
    log_info "Checking SSL/TLS configuration..."
    local issues=()
    
    # Check if SSL is enabled
    if [[ -f "$ROOT_DIR/.env" ]]; then
        # shellcheck disable=SC1090
        source "$ROOT_DIR/.env"
        
        if [[ "${SSL_ENABLED:-false}" == "false" ]]; then
            issues+=("SSL/TLS is not enabled")
        fi
        
        # Check for self-signed certificates in production
        if [[ "${ENVIRONMENT:-development}" != "development" ]] && [[ -f "$ROOT_DIR/nginx/ssl/nginx.crt" ]]; then
            local cert_issuer
            cert_issuer=$(openssl x509 -in "$ROOT_DIR/nginx/ssl/nginx.crt" -noout -issuer 2>/dev/null | grep -o "CN=[^,]*" | cut -d= -f2 || echo "unknown")
            
            if [[ "$cert_issuer" == "localhost" ]] || [[ "$cert_issuer" == "unknown" ]]; then
                issues+=("Using self-signed certificate in non-development environment")
            fi
        fi
    fi
    
    # Check nginx SSL configuration
    if [[ -f "$ROOT_DIR/nginx/nginx.conf" ]]; then
        if ! grep -q "ssl_protocols TLSv1.2 TLSv1.3" "$ROOT_DIR/nginx/nginx.conf"; then
            issues+=("Nginx SSL configuration may not enforce modern TLS versions")
        fi
    fi
    
    return_issues "${issues[@]}"
}

# Function to check monitoring and logging security
check_monitoring_security() {
    log_info "Checking monitoring and logging security..."
    local issues=()
    
    # Check if monitoring services have authentication
    local monitoring_containers=("mcp-grafana" "mcp-prometheus")
    
    for container in "${monitoring_containers[@]}"; do
        if docker ps --format "{{.Names}}" | grep -q "$container"; then
            log_info "Checking $container security..."
            
            # Check Grafana authentication
            if [[ "$container" == "mcp-grafana" ]]; then
                local grafana_auth
                grafana_auth=$(docker exec "$container" env 2>/dev/null | grep "GF_AUTH_ANONYMOUS_ENABLED" || echo "GF_AUTH_ANONYMOUS_ENABLED=true")
                
                if [[ "$grafana_auth" == "GF_AUTH_ANONYMOUS_ENABLED=true" ]]; then
                    issues+=("Grafana has anonymous authentication enabled")
                fi
            fi
        fi
    done
    
    # Check log file permissions
    local log_dirs=("logs" "backups/logs")
    
    for log_dir in "${log_dirs[@]}"; do
        if [[ -d "$ROOT_DIR/$log_dir" ]]; then
            local perms
            perms=$(stat -c "%a" "$ROOT_DIR/$log_dir" 2>/dev/null || echo "unknown")
            
            if [[ "$perms" =~ ^[0-9]{3}$ ]] && [[ ${perms:2:1} -gt 4 ]]; then
                issues+=("Log directory $log_dir has world-readable permissions ($perms)")
            fi
        fi
    done
    
    return_issues "${issues[@]}"
}

# Helper function to handle issues array
return_issues() {
    local issues=("$@")
    
    if [[ ${#issues[@]} -gt 0 ]]; then
        log_warn "Security issues found:"
        for issue in "${issues[@]}"; do
            log_warn "  - $issue"
        done
        return 1
    else
        log_info "✅ No security issues found in this category"
        return 0
    fi
}

# Function to generate security report
generate_security_report() {
    local report_file="$REPORT_DIR/security_audit_$(date +%Y%m%d_%H%M%S).md"
    
    log_info "Generating security report: $report_file"
    
    cat > "$report_file" << EOF
# Docker MCP Stack Security Audit Report

**Generated:** $(date)
**Version:** $(git rev-parse --short HEAD 2>/dev/null || echo "unknown")
**Environment:** ${ENVIRONMENT:-development}

## Executive Summary

This report contains the results of a comprehensive security audit of the Docker MCP Stack.

## Audit Categories

EOF
    
    # Run each security check and capture results
    local total_issues=0
    local categories=("Container Security" "Network Security" "Image Security" "Secrets Security" "Filesystem Security" "SSL/TLS Security" "Monitoring Security")
    local functions=("check_container_security" "check_network_security" "check_image_security" "check_secrets_security" "check_filesystem_security" "check_ssl_security" "check_monitoring_security")
    
    for i in "${!categories[@]}"; do
        local category="${categories[$i]}"
        local function="${functions[$i]}"
        
        echo "### $category" >> "$report_file"
        echo "" >> "$report_file"
        
        # Capture function output
        local output
        if output=$($function 2>&1); then
            echo "✅ **Status:** PASSED" >> "$report_file"
            echo "" >> "$report_file"
            echo "No security issues found in this category." >> "$report_file"
        else
            echo "⚠️ **Status:** ISSUES FOUND" >> "$report_file"
            echo "" >> "$report_file"
            echo "\`\`\`" >> "$report_file"
            echo "$output" >> "$report_file"
            echo "\`\`\`" >> "$report_file"
            ((total_issues++))
        fi
        
        echo "" >> "$report_file"
    done
    
    # Add recommendations section
    cat >> "$report_file" << EOF

## Recommendations

### High Priority
- Review and fix all identified security issues
- Implement non-root users for all containers
- Enable SSL/TLS for all external communications
- Use strong, unique passwords for all services

### Medium Priority
- Implement container image scanning
- Set up automated security monitoring
- Enable audit logging for all services
- Regular security updates and patches

### Low Priority
- Consider using secrets management system
- Implement network segmentation
- Add security headers validation
- Regular security training for team

## References

- [Docker Security Best Practices](https://docs.docker.com/engine/security/)
- [OWASP Container Security](https://owasp.org/www-project-container-security/)
- [CIS Docker Benchmark](https://www.cisecurity.org/benchmark/docker)

---

**Total Issues Found:** $total_issues categories with issues
**Report Location:** $report_file
EOF
    
    log_info "Security report generated: $report_file"
    
    if [[ $total_issues -gt 0 ]]; then
        log_warn "Security audit found issues in $total_issues categories"
        return 1
    else
        log_info "✅ Security audit passed - no issues found"
        return 0
    fi
}

# Main function
main() {
    log_info "Starting Docker MCP Stack security audit..."
    
    # Check if Docker is running
    if ! docker info > /dev/null 2>&1; then
        log_error "Docker is not running. Please start Docker and try again."
        exit 1
    fi
    
    # Generate security report
    if generate_security_report; then
        log_info "✅ Security audit completed successfully"
        exit 0
    else
        log_warn "⚠️ Security audit completed with issues"
        exit 1
    fi
}

# Check if script is being sourced or executed
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
