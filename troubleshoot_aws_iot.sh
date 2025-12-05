#!/bin/bash
# Troubleshoot AWS IoT Connection Issues
# For PiKVM (Arch Linux)

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

set -e

PST_CERTS_DIR="/var/lib/kvmd/pst/$CERT_DIR_NAME"

echo "=== AWS IoT Connection Troubleshooting ==="
echo ""

# Check if metadata exists
if [ ! -f "$PST_CERTS_DIR/cert-metadata.json" ]; then
    echo "Error: Certificate metadata not found"
    echo "Please run setup_aws_iot_certificates.sh first"
    exit 1
fi

# Load configuration
CERT_ARN=$(grep -o '"certificateArn": "[^"]*"' "$PST_CERTS_DIR/cert-metadata.json" | cut -d'"' -f4)
THING_NAME=$(grep -o '"thingName": "[^"]*"' "$PST_CERTS_DIR/cert-metadata.json" | cut -d'"' -f4)
POLICY_NAME=$(grep -o '"policyName": "[^"]*"' "$PST_CERTS_DIR/cert-metadata.json" | cut -d'"' -f4)
AWS_IOT_ENDPOINT=$(grep -o '"awsIotEndpoint": "[^"]*"' "$PST_CERTS_DIR/cert-metadata.json" | cut -d'"' -f4)

echo "Configuration:"
echo "  Thing Name: $THING_NAME"
echo "  Policy Name: $POLICY_NAME"
echo "  Certificate ARN: $CERT_ARN"
echo "  AWS IoT Endpoint: $AWS_IOT_ENDPOINT"
echo ""

# 1. Check Certificate Status
echo "=== 1. Checking Certificate Status ==="
CERT_STATUS=$(aws iot describe-certificate --certificate-id "${CERT_ARN##*/}" --query 'certificateDescription.status' --output text)
echo "Certificate Status: $CERT_STATUS"

if [ "$CERT_STATUS" != "ACTIVE" ]; then
    echo "⚠️  Certificate is NOT active!"
    echo "Activating certificate..."
    aws iot update-certificate --certificate-id "${CERT_ARN##*/}" --new-status ACTIVE
    echo "Certificate activated"
fi
echo ""

# 2. Check Policy Details
echo "=== 2. Checking Policy Details ==="
echo "Policy Document:"
aws iot get-policy --policy-name "$POLICY_NAME" --query 'policyDocument' --output text | python3 -m json.tool
echo ""

# 3. Check Policy Attachment
echo "=== 3. Checking Policy Attachment ==="
ATTACHED_POLICIES=$(aws iot list-attached-policies --target "$CERT_ARN" --query 'policies[*].policyName' --output text)

if echo "$ATTACHED_POLICIES" | grep -q "$POLICY_NAME"; then
    echo "✅ Policy '$POLICY_NAME' is attached to certificate"
else
    echo "⚠️  Policy NOT attached! Attaching now..."
    aws iot attach-policy --policy-name "$POLICY_NAME" --target "$CERT_ARN"
    echo "Policy attached"
fi
echo ""

# 4. Check Thing Principal Attachment
echo "=== 4. Checking Thing Principal Attachment ==="
ATTACHED_PRINCIPALS=$(aws iot list-thing-principals --thing-name "$THING_NAME" --query 'principals[*]' --output text)

if echo "$ATTACHED_PRINCIPALS" | grep -q "$CERT_ARN"; then
    echo "✅ Certificate is attached to Thing '$THING_NAME'"
else
    echo "⚠️  Certificate NOT attached to Thing! Attaching now..."
    aws iot attach-thing-principal --thing-name "$THING_NAME" --principal "$CERT_ARN"
    echo "Certificate attached to Thing"
fi
echo ""

# 5. Check Certificate Files
echo "=== 5. Checking Certificate Files ==="
for cert_file in rootCA.pem cert.crt private.key; do
    if [ -f "$PST_CERTS_DIR/$cert_file" ]; then
        echo "✅ $cert_file exists"
        ls -lh "$PST_CERTS_DIR/$cert_file"
    else
        echo "❌ $cert_file NOT FOUND"
    fi
done
echo ""

# 6. Test TLS Connection with OpenSSL
echo "=== 6. Testing TLS Connection with OpenSSL ==="
echo "Attempting to connect to AWS IoT endpoint..."
timeout 5 openssl s_client -connect "$AWS_IOT_ENDPOINT:8883" \
    -CAfile "$PST_CERTS_DIR/rootCA.pem" \
    -cert "$PST_CERTS_DIR/cert.crt" \
    -key "$PST_CERTS_DIR/private.key" \
    -showcerts < /dev/null 2>&1 | grep -E "Verify return code|Protocol|Cipher" || echo "Connection attempt completed"
echo ""

# 7. Check Mosquitto Configuration
echo "=== 7. Checking Mosquitto Configuration ==="
echo "Bridge configuration in mosquitto.conf:"
grep -A 30 "connection awsiot" /etc/mosquitto/mosquitto.conf || echo "No bridge configuration found"
echo ""

# 8. Test MQTT Connection with mosquitto_pub
echo "=== 8. Testing MQTT Connection ==="
echo "Attempting to publish test message..."
timeout 10 mosquitto_pub \
    -h "$AWS_IOT_ENDPOINT" \
    -p 8883 \
    --cafile "$PST_CERTS_DIR/rootCA.pem" \
    --cert "$PST_CERTS_DIR/cert.crt" \
    --key "$PST_CERTS_DIR/private.key" \
    -t "${THING_NAME}/test" \
    -m "test message from PIKVM" \
    -d 2>&1 || echo "MQTT publish attempt completed"
echo ""

# 9. Check Recent Mosquitto Logs
echo "=== 9. Recent Mosquitto Logs ==="
journalctl -u mosquitto --since "5 minutes ago" --no-pager | tail -20
echo ""

echo "=== Troubleshooting Complete ==="
echo ""
echo "Common Issues and Solutions:"
echo ""
echo "1. If OpenSSL connection succeeds but Mosquitto fails:"
echo "   - Check file permissions: sudo ls -la $PST_CERTS_DIR"
echo "   - Ensure mosquitto user can read files"
echo ""
echo "2. If 'Verify return code' is not 0:"
echo "   - Certificate chain issue"
echo "   - May need to re-download Root CA"
echo ""
echo "3. If policy attachment failed:"
echo "   - Policy may be too restrictive"
echo "   - Check client ID in mosquitto.conf matches policy"
echo ""
echo "4. To re-test after fixes:"
echo "   - Restart Mosquitto: sudo systemctl restart mosquitto"
echo "   - Watch logs: sudo journalctl -u mosquitto -f"
echo ""
