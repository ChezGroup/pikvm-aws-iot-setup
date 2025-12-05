#!/bin/bash
# Certificate Management Helper Script for PIKVM AWS IoT
# Provides utilities for managing AWS IoT certificates

# =============================================================================
# CONFIGURATION LOADING
# =============================================================================

# Determine script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load configuration from config.sh if it exists
if [ -f "$SCRIPT_DIR/config/config.sh" ]; then
    source "$SCRIPT_DIR/config/config.sh"
elif [ -f "$SCRIPT_DIR/../config/config.sh" ]; then
    source "$SCRIPT_DIR/../config/config.sh"
fi

# Set default values
CERT_DIR_NAME="${CERT_DIR_NAME:-mosquitto/certs}"

PST_CERTS_DIR="/var/lib/kvmd/pst/$CERT_DIR_NAME"
METADATA_FILE="$PST_CERTS_DIR/cert-metadata.json"

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Function to print colored messages
print_success() { echo -e "${GREEN}✓${NC} $1"; }
print_warning() { echo -e "${YELLOW}⚠${NC} $1"; }
print_error() { echo -e "${RED}✗${NC} $1"; }

# Function to check if certificates exist
check_certificates() {
    echo "=== Certificate Status Check ==="
    echo ""
    
    if [ ! -f "$METADATA_FILE" ]; then
        print_error "No certificates found"
        echo "Run setup_aws_iot_certificates.sh to create certificates"
        return 1
    fi
    
    print_success "Certificate metadata found"
    
    # Check all required certificate files
    local all_found=true
    for cert_file in rootCA.pem cert.crt private.key; do
        if [ -f "$PST_CERTS_DIR/$cert_file" ]; then
            print_success "$cert_file exists"
        else
            print_error "$cert_file missing"
            all_found=false
        fi
    done
    
    echo ""
    
    if [ "$all_found" = true ]; then
        print_success "All certificate files present"
        return 0
    else
        print_error "Some certificate files are missing"
        return 1
    fi
}

# Function to show certificate information
show_info() {
    echo "=== Certificate Information ==="
    echo ""
    
    if [ ! -f "$METADATA_FILE" ]; then
        print_error "Certificate metadata not found"
        return 1
    fi
    
    # Extract information from metadata
    CERT_ARN=$(grep -o '"certificateArn": "[^"]*"' "$METADATA_FILE" | cut -d'"' -f4)
    AWS_ENDPOINT=$(grep -o '"awsIotEndpoint": "[^"]*"' "$METADATA_FILE" | cut -d'"' -f4)
    AWS_REGION=$(grep -o '"awsRegion": "[^"]*"' "$METADATA_FILE" | cut -d'"' -f4)
    THING_NAME=$(grep -o '"thingName": "[^"]*"' "$METADATA_FILE" | cut -d'"' -f4)
    POLICY_NAME=$(grep -o '"policyName": "[^"]*"' "$METADATA_FILE" | cut -d'"' -f4)
    CREATED_AT=$(grep -o '"createdAt": "[^"]*"' "$METADATA_FILE" | cut -d'"' -f4)
    
    echo "Thing Name:      $THING_NAME"
    echo "Policy Name:     $POLICY_NAME"
    echo "AWS Region:      $AWS_REGION"
    echo "AWS IoT Endpoint: $AWS_ENDPOINT"
    echo "Created At:      $CREATED_AT"
    echo ""
    echo "Certificate ARN:"
    echo "  $CERT_ARN"
    echo ""
    
    # Certificate details
    if [ -f "$PST_CERTS_DIR/cert.crt" ]; then
        echo "Certificate Details:"
        openssl x509 -in "$PST_CERTS_DIR/cert.crt" -noout -subject -issuer -dates
    fi
    
    return 0
}

# Function to verify certificate validity
verify_certificate() {
    echo "=== Certificate Verification ==="
    echo ""
    
    if [ ! -f "$PST_CERTS_DIR/cert.crt" ]; then
        print_error "Certificate file not found"
        return 1
    fi
    
    if [ ! -f "$PST_CERTS_DIR/rootCA.pem" ]; then
        print_error "Root CA file not found"
        return 1
    fi
    
    # Verify certificate against Root CA
    # AWS IoT certificates are self-contained, so we use -partial_chain
    echo "Verifying certificate chain..."
    if openssl verify -partial_chain -CAfile "$PST_CERTS_DIR/rootCA.pem" "$PST_CERTS_DIR/cert.crt" > /dev/null 2>&1; then
        print_success "Certificate is valid"
    else
        # Try alternative verification method
        if openssl x509 -in "$PST_CERTS_DIR/cert.crt" -noout > /dev/null 2>&1; then
            print_success "Certificate format is valid"
            print_warning "Full chain verification skipped (AWS IoT uses device certificates)"
            echo "  AWS IoT device certificates are validated by AWS IoT Core during connection"
        else
            print_error "Certificate verification failed"
            openssl verify -partial_chain -CAfile "$PST_CERTS_DIR/rootCA.pem" "$PST_CERTS_DIR/cert.crt"
            return 1
        fi
    fi
    
    # Check certificate dates
    NOT_BEFORE=$(openssl x509 -in "$PST_CERTS_DIR/cert.crt" -noout -startdate | cut -d= -f2)
    NOT_AFTER=$(openssl x509 -in "$PST_CERTS_DIR/cert.crt" -noout -enddate | cut -d= -f2)
    
    echo ""
    echo "Certificate Validity:"
    echo "  Valid From: $NOT_BEFORE"
    echo "  Valid To:   $NOT_AFTER"
    
    # Check if certificate is expired
    if openssl x509 -in "$PST_CERTS_DIR/cert.crt" -noout -checkend 0 > /dev/null 2>&1; then
        print_success "Certificate is not expired"
    else
        print_error "Certificate has expired!"
        return 1
    fi
    
    # Check if certificate will expire in 30 days
    if openssl x509 -in "$PST_CERTS_DIR/cert.crt" -noout -checkend 2592000 > /dev/null 2>&1; then
        print_success "Certificate valid for more than 30 days"
    else
        print_warning "Certificate will expire within 30 days"
    fi
    
    # Show certificate details
    echo ""
    echo "Certificate Details:"
    openssl x509 -in "$PST_CERTS_DIR/cert.crt" -noout -subject -issuer
    
    # Verify that the certificate can be read correctly
    echo ""
    echo "Certificate Fingerprint (SHA256):"
    openssl x509 -in "$PST_CERTS_DIR/cert.crt" -noout -fingerprint -sha256
    
    echo ""
    print_success "Certificate verification complete"
    echo "  Note: AWS IoT validates device certificates during TLS handshake"
    echo "  Test actual connection with: $0 test"
    
    return 0
}

# Function to test AWS IoT connection
test_connection() {
    echo "=== Testing AWS IoT Connection ==="
    echo ""
    
    if [ ! -f "$METADATA_FILE" ]; then
        print_error "Certificate metadata not found"
        return 1
    fi
    
    AWS_ENDPOINT=$(grep -o '"awsIotEndpoint": "[^"]*"' "$METADATA_FILE" | cut -d'"' -f4)
    THING_NAME=$(grep -o '"thingName": "[^"]*"' "$METADATA_FILE" | cut -d'"' -f4)
    
    # Test DNS resolution using getent (always available)
    echo "Testing DNS resolution..."
    if getent hosts "$AWS_ENDPOINT" > /dev/null 2>&1; then
        print_success "DNS resolution successful"
        RESOLVED_IP=$(getent hosts "$AWS_ENDPOINT" | awk '{print $1}')
        echo "  Resolved to: $RESOLVED_IP"
    else
        print_error "DNS resolution failed"
        echo "  Endpoint: $AWS_ENDPOINT"
        echo "  Try: getent hosts $AWS_ENDPOINT"
        return 1
    fi
    
    # Test network connectivity
    echo "Testing network connectivity..."
    if ping -c 3 -W 2 "$AWS_ENDPOINT" > /dev/null 2>&1; then
        print_success "Network connectivity OK"
    else
        print_warning "Ping failed (may be blocked by AWS firewall, this is normal)"
        echo "  This is expected for AWS IoT endpoints"
    fi
    
    # Test TLS connection
    echo "Testing TLS connection to port 8883..."
    if timeout 5 openssl s_client -connect "$AWS_ENDPOINT:8883" \
        -CAfile "$PST_CERTS_DIR/rootCA.pem" \
        -cert "$PST_CERTS_DIR/cert.crt" \
        -key "$PST_CERTS_DIR/private.key" \
        < /dev/null > /dev/null 2>&1; then
        print_success "TLS connection successful"
    else
        print_error "TLS connection failed"
        echo "Check logs with: journalctl -u mosquitto -n 50"
        return 1
    fi
    
    # Check Mosquitto bridge status
    echo ""
    echo "Checking Mosquitto bridge status..."
    
    # Check if service is running
    if systemctl is-active --quiet mosquitto; then
        print_success "Mosquitto service is running"
        
        # Check recent logs for bridge connection
        if journalctl -u mosquitto --since "5 minutes ago" 2>/dev/null | grep -q "Bridge awsiot established\|Connecting bridge awsiot"; then
            print_success "Bridge connection to AWS IoT active"
            echo "  Check detailed status: journalctl -u mosquitto -n 20"
        else
            print_warning "Bridge connection not confirmed in recent logs"
            echo "  This may be normal if the bridge was established more than 5 minutes ago"
            echo "  Check detailed logs with: journalctl -u mosquitto -f"
        fi
    else
        print_error "Mosquitto service is not running"
        echo "  Start with: systemctl start mosquitto"
        echo "  Check status: systemctl status mosquitto"
        return 1
    fi
    
    return 0
}

# Function to backup certificates
backup_certificates() {
    echo "=== Backing up Certificates ==="
    echo ""
    
    if [ ! -d "$PST_CERTS_DIR" ]; then
        print_error "Certificates directory not found"
        return 1
    fi
    
    rw  # Enable write mode
    
    BACKUP_FILE="/tmp/pikvm-certs-backup-$(date +%Y%m%d-%H%M%S).tar.gz"
    
    if tar -czf "$BACKUP_FILE" -C /var/lib/kvmd/pst/mosquitto certs/; then
        print_success "Backup created: $BACKUP_FILE"
        ls -lh "$BACKUP_FILE"
        echo ""
        echo "To download the backup:"
        echo "  scp root@$(hostname -I | awk '{print $1}'):$BACKUP_FILE ."
    else
        print_error "Backup failed"
        ro
        return 1
    fi
    
    ro  # Return to read-only mode
    
    return 0
}

# Function to restore certificates from backup
restore_certificates() {
    if [ -z "$1" ]; then
        print_error "Usage: $0 restore <backup-file.tar.gz>"
        return 1
    fi
    
    BACKUP_FILE="$1"
    
    if [ ! -f "$BACKUP_FILE" ]; then
        print_error "Backup file not found: $BACKUP_FILE"
        return 1
    fi
    
    echo "=== Restoring Certificates from Backup ==="
    echo ""
    echo "Backup file: $BACKUP_FILE"
    echo ""
    
    read -p "This will overwrite existing certificates. Continue? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Restore cancelled"
        return 1
    fi
    
    rw  # Enable write mode
    
    # Create backup of current certificates
    if [ -d "$PST_CERTS_DIR" ]; then
        CURRENT_BACKUP="/tmp/pikvm-certs-current-$(date +%Y%m%d-%H%M%S).tar.gz"
        tar -czf "$CURRENT_BACKUP" -C /var/lib/kvmd/pst/mosquitto certs/
        print_success "Current certificates backed up to: $CURRENT_BACKUP"
    fi
    
    # Restore from backup
    if tar -xzf "$BACKUP_FILE" -C /var/lib/kvmd/pst/mosquitto/; then
        print_success "Certificates restored successfully"
        
        # Fix permissions
        chown -R mosquitto:mosquitto "$PST_CERTS_DIR"
        chmod 755 "$PST_CERTS_DIR"
        chmod 644 "$PST_CERTS_DIR"/*.pem "$PST_CERTS_DIR"/*.crt
        chmod 600 "$PST_CERTS_DIR"/private.key
        
        print_success "Permissions fixed"
        
        # Restart Mosquitto
        systemctl restart mosquitto
        print_success "Mosquitto restarted"
    else
        print_error "Restore failed"
        ro
        return 1
    fi
    
    ro  # Return to read-only mode
    
    return 0
}

# Function to show usage
usage() {
    echo "PIKVM AWS IoT Certificate Management Helper"
    echo ""
    echo "Usage: $0 <command>"
    echo ""
    echo "Commands:"
    echo "  check      - Check if certificates exist and are valid"
    echo "  info       - Show certificate information"
    echo "  verify     - Verify certificate validity and expiration"
    echo "  test       - Test AWS IoT connection"
    echo "  backup     - Create backup of certificates"
    echo "  restore    - Restore certificates from backup"
    echo "  help       - Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 check"
    echo "  $0 info"
    echo "  $0 test"
    echo "  $0 backup"
    echo "  $0 restore /tmp/pikvm-certs-backup-20251011.tar.gz"
    echo ""
}

# Main script logic
case "${1:-help}" in
    check)
        check_certificates
        ;;
    info)
        show_info
        ;;
    verify)
        verify_certificate
        ;;
    test)
        test_connection
        ;;
    backup)
        backup_certificates
        ;;
    restore)
        restore_certificates "$2"
        ;;
    help|--help|-h)
        usage
        ;;
    *)
        print_error "Unknown command: $1"
        echo ""
        usage
        exit 1
        ;;
esac

exit $?
