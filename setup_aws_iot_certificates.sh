#!/bin/bash
# Script for AWS IoT Certificate Setup on PIKVM
# This script generates and configures AWS IoT certificates for Mosquitto bridge
# For PiKVM (Arch Linux)

# =============================================================================
# CONFIGURATION LOADING
# =============================================================================

# Determine script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load configuration from config.sh if it exists
if [ -f "$SCRIPT_DIR/config/config.sh" ]; then
    echo "Loading configuration from config/config.sh..."
    source "$SCRIPT_DIR/config/config.sh"
elif [ -f "$SCRIPT_DIR/../config/config.sh" ]; then
    echo "Loading configuration from ../config/config.sh..."
    source "$SCRIPT_DIR/../config/config.sh"
else
    echo "Warning: config.sh not found. Using default values."
    echo "Copy config/config.sh.example to config/config.sh and customize it."
fi

# Set default values for all configuration variables
PROJECT_PREFIX="${PROJECT_PREFIX:-default-project}"
DEVICE_ID_METHOD="${DEVICE_ID_METHOD:-cpu-serial}"
DEVICE_ID_LENGTH="${DEVICE_ID_LENGTH:-8}"
CERT_DIR_NAME="${CERT_DIR_NAME:-mosquitto/certs}"
DEBUG_MODE="${DEBUG_MODE:-false}"
VERBOSE_LOGGING="${VERBOSE_LOGGING:-false}"

# Enable debug mode if configured
if [ "$DEBUG_MODE" = "true" ]; then
    set -x
fi

# Enable Write mode
rw

# The script stops at the first error
set -e

echo "=== AWS IoT Certificate Setup for PIKVM Mosquitto Bridge ==="
echo "Project: $PROJECT_PREFIX"
echo ""

# Check if AWS CLI is installed
if ! command -v aws &> /dev/null; then
    echo "=== Installing AWS CLI ==="
    pacman -S aws-cli --noconfirm
    echo "AWS CLI installed successfully"
    echo ""
fi

# Check AWS credentials
echo "=== Checking AWS Credentials ==="
if ! aws sts get-caller-identity &> /dev/null; then
    echo "AWS credentials not configured. Running 'aws configure'..."
    echo "You will need:"
    echo "  - AWS Access Key ID"
    echo "  - AWS Secret Access Key"
    echo "  - Default region (e.g., us-east-1)"
    echo ""
    aws configure
    echo ""
fi

# Verify AWS credentials
echo "Verifying AWS credentials..."
aws sts get-caller-identity
echo ""

# Get AWS IoT endpoint
echo "=== Getting AWS IoT Endpoint ==="

# Use configured endpoint or auto-detect
if [ -n "$AWS_IOT_ENDPOINT" ]; then
    echo "Using configured AWS IoT endpoint: $AWS_IOT_ENDPOINT"
else
    AWS_IOT_ENDPOINT=$(aws iot describe-endpoint --endpoint-type iot:Data-ATS --query 'endpointAddress' --output text)
    
    if [ -z "$AWS_IOT_ENDPOINT" ]; then
        echo "Error: Could not retrieve AWS IoT endpoint"
        exit 1
    fi
    
    echo "Auto-detected AWS IoT Endpoint: $AWS_IOT_ENDPOINT"
fi
echo ""

# Get AWS region
if [ -n "$AWS_REGION" ]; then
    echo "Using configured AWS region: $AWS_REGION"
else
    AWS_REGION=$(aws configure get region)
    if [ -z "$AWS_REGION" ]; then
        echo "Error: AWS region not configured"
        exit 1
    fi
    echo "Auto-detected AWS Region: $AWS_REGION"
fi
echo ""

# Get unique PIKVM identifier using CPU serial number
echo "=== Generating Unique PIKVM Identifier ==="

# Use custom device ID if specified
if [ "$DEVICE_ID_METHOD" = "custom" ] && [ -n "$CUSTOM_DEVICE_ID" ]; then
    DEVICE_ID="$CUSTOM_DEVICE_ID"
    echo "Using custom Device ID: $DEVICE_ID"
elif [ "$DEVICE_ID_METHOD" = "mac-address" ]; then
    MAC_ADDRESS=$(cat /sys/class/net/eth0/address 2>/dev/null || cat /sys/class/net/wlan0/address 2>/dev/null)
    if [ -z "$MAC_ADDRESS" ]; then
        echo "Error: Could not retrieve MAC address"
        exit 1
    fi
    DEVICE_ID=$(echo $MAC_ADDRESS | tr -d ':')
    echo "Using MAC-based Device ID: $DEVICE_ID"
else
    # Default: use CPU serial
    CPU_SERIAL=$(cat /proc/cpuinfo | grep Serial | cut -d ' ' -f 2)
    
    if [ -z "$CPU_SERIAL" ] || [ "$CPU_SERIAL" = "0000000000000000" ]; then
        echo "Warning: Could not retrieve valid CPU serial number"
        echo "Falling back to MAC address..."
        MAC_ADDRESS=$(cat /sys/class/net/eth0/address 2>/dev/null || cat /sys/class/net/wlan0/address 2>/dev/null)
        if [ -z "$MAC_ADDRESS" ]; then
            echo "Error: Could not retrieve MAC address either"
            echo "Please configure network interface first"
            exit 1
        fi
        DEVICE_ID=$(echo $MAC_ADDRESS | tr -d ':')
        echo "Using MAC-based Device ID: $DEVICE_ID"
    else
        # Use configured length of CPU serial for compact ID
        DEVICE_ID="${CPU_SERIAL: -$DEVICE_ID_LENGTH}"
        echo "CPU Serial: $CPU_SERIAL"
        echo "Using CPU serial-based Device ID: $DEVICE_ID"
    fi
fi

PIKVM_ID="${PROJECT_PREFIX}-${DEVICE_ID}"
THING_NAME="pikvm-${PIKVM_ID}"
POLICY_NAME="${THING_NAME}-policy"

echo "Project Prefix: $PROJECT_PREFIX"
echo "Full PIKVM ID: $PIKVM_ID"
echo "Thing Name: $THING_NAME"
echo "Policy Name: $POLICY_NAME"
echo ""

# Create helper script for PST operations
echo "=== Creating helper script for PST certificate setup ==="
cat > /tmp/setup_pst_certs.sh << PST_HELPER_EOF
#!/bin/bash
# This script runs inside kvmd-pstrun to create certificate directory in PST

# Create certificate directory in PST if it doesn't exist
mkdir -p \$KVMD_PST_DATA/$CERT_DIR_NAME
chmod 755 \$KVMD_PST_DATA/$CERT_DIR_NAME

echo "Certificate directory created at: \$KVMD_PST_DATA/$CERT_DIR_NAME"
echo "Full path: \$(readlink -f \$KVMD_PST_DATA/$CERT_DIR_NAME)"
ls -la \$KVMD_PST_DATA/mosquitto/
PST_HELPER_EOF

chmod +x /tmp/setup_pst_certs.sh

# Create certificates directory in PST (persistent storage)
echo "=== Creating certificates directory in PST ==="
kvmd-pstrun -- /tmp/setup_pst_certs.sh --some --script --args

# Clean up helper script
rm /tmp/setup_pst_certs.sh

# Set actual PST path (not inside PST context)
PST_CERTS_DIR="/var/lib/kvmd/pst/$CERT_DIR_NAME"
echo "Certificates will be stored at: $PST_CERTS_DIR"
echo ""

# Download Amazon Root CA to temp location first
echo "=== Downloading Amazon Root CA ==="
TEMP_ROOT_CA="/tmp/rootCA.pem"
wget -q https://www.amazontrust.com/repository/AmazonRootCA1.pem -O "$TEMP_ROOT_CA"
echo "Root CA downloaded to temporary location"
echo ""

# Create helper script to move Root CA to PST
cat > /tmp/copy_rootca_to_pst.sh << ROOTCA_EOF
#!/bin/bash
# Copy Root CA to PST

# Copy from temp to PST
cp /tmp/rootCA.pem \$KVMD_PST_DATA/$CERT_DIR_NAME/rootCA.pem
chmod 644 \$KVMD_PST_DATA/$CERT_DIR_NAME/rootCA.pem

echo "Root CA copied to PST"
ls -la \$KVMD_PST_DATA/$CERT_DIR_NAME/rootCA.pem
ROOTCA_EOF

chmod +x /tmp/copy_rootca_to_pst.sh

# Move Root CA to PST
kvmd-pstrun -- /tmp/copy_rootca_to_pst.sh --some --script --args

# Clean up
rm /tmp/copy_rootca_to_pst.sh /tmp/rootCA.pem

echo "Root CA installed successfully in PST"
echo ""

# Check if IoT policy already exists
echo "=== Creating/Verifying AWS IoT Policy ==="

# Use custom policy document if provided, otherwise use default
if [ -n "$AWS_IOT_POLICY_DOCUMENT" ]; then
    POLICY_DOC="$AWS_IOT_POLICY_DOCUMENT"
    echo "Using custom policy document from configuration"
else
    POLICY_DOC='{
        "Version": "2012-10-17",
        "Statement": [
            {
                "Effect": "Allow",
                "Action": "iot:Connect",
                "Resource": "arn:aws:iot:*:*:client/*"
            },
            {
                "Effect": "Allow",
                "Action": [
                    "iot:Publish",
                    "iot:Receive"
                ],
                "Resource": "arn:aws:iot:*:*:topic/*"
            },
            {
                "Effect": "Allow",
                "Action": "iot:Subscribe",
                "Resource": "arn:aws:iot:*:*:topicfilter/*"
            }
        ]
    }'
    echo "Using default policy document"
fi

if aws iot get-policy --policy-name "$POLICY_NAME" &> /dev/null; then
    echo "Policy '$POLICY_NAME' already exists"
    echo "Updating policy to latest version..."
    aws iot create-policy-version --policy-name "$POLICY_NAME" --set-as-default \
        --policy-document "$POLICY_DOC"
    echo "Policy updated successfully"
else
    echo "Creating new IoT Policy: $POLICY_NAME"
    aws iot create-policy --policy-name "$POLICY_NAME" \
        --policy-document "$POLICY_DOC"
    echo "Policy created successfully"
fi
echo ""

# Check if Thing already exists
echo "=== Creating/Verifying AWS IoT Thing ==="
if aws iot describe-thing --thing-name "$THING_NAME" &> /dev/null; then
    echo "Thing '$THING_NAME' already exists"
else
    echo "Creating new IoT Thing: $THING_NAME"
    aws iot create-thing --thing-name "$THING_NAME"
    echo "Thing created successfully"
fi
echo ""

# Generate new certificate and keys
echo "=== Generating AWS IoT Certificate and Keys ==="

# Create temporary directory for certificate generation
TEMP_CERT_DIR="/tmp/aws-iot-certs-$$"
mkdir -p "$TEMP_CERT_DIR"

CERT_OUTPUT=$(aws iot create-keys-and-certificate \
    --set-as-active \
    --certificate-pem-outfile "$TEMP_CERT_DIR/cert.crt" \
    --private-key-outfile "$TEMP_CERT_DIR/private.key" \
    --public-key-outfile "$TEMP_CERT_DIR/public.key" \
    --region "$AWS_REGION")

# Extract certificate ARN
CERT_ARN=$(echo "$CERT_OUTPUT" | grep -o '"certificateArn": "[^"]*"' | cut -d'"' -f4)

if [ -z "$CERT_ARN" ]; then
    echo "Error: Could not extract certificate ARN"
    rm -rf "$TEMP_CERT_DIR"
    exit 1
fi

echo "Certificate ARN: $CERT_ARN"
echo ""

# Set proper permissions on temp files
chmod 644 "$TEMP_CERT_DIR/cert.crt"
chmod 600 "$TEMP_CERT_DIR/private.key"
chmod 644 "$TEMP_CERT_DIR/public.key"

echo "Certificate files created in temporary location"
ls -la "$TEMP_CERT_DIR"
echo ""

# Create helper script to copy certificates to PST
cat > /tmp/copy_certs_to_pst.sh << CERTS_EOF
#!/bin/bash
# Copy certificate files to PST

TEMP_DIR="\$1"
CERT_DIR="$CERT_DIR_NAME"

# Copy all certificate files
cp "\$TEMP_DIR/cert.crt" \$KVMD_PST_DATA/\$CERT_DIR/cert.crt
cp "\$TEMP_DIR/private.key" \$KVMD_PST_DATA/\$CERT_DIR/private.key
cp "\$TEMP_DIR/public.key" \$KVMD_PST_DATA/\$CERT_DIR/public.key

# Set proper permissions
chmod 644 \$KVMD_PST_DATA/\$CERT_DIR/cert.crt
chmod 600 \$KVMD_PST_DATA/\$CERT_DIR/private.key
chmod 644 \$KVMD_PST_DATA/\$CERT_DIR/public.key

echo "Certificates copied to PST"
ls -la \$KVMD_PST_DATA/\$CERT_DIR/
CERTS_EOF

chmod +x /tmp/copy_certs_to_pst.sh

# Copy certificates to PST
echo "=== Copying certificates to PST ==="
kvmd-pstrun -- /tmp/copy_certs_to_pst.sh "$TEMP_CERT_DIR" --some --script --args

# Clean up temporary directory
rm -rf "$TEMP_CERT_DIR"
rm /tmp/copy_certs_to_pst.sh

echo "Certificate files installed in PST"
echo ""

# Attach policy to certificate
echo "=== Attaching Policy to Certificate ==="
aws iot attach-policy --policy-name "$POLICY_NAME" --target "$CERT_ARN"
echo "Policy attached successfully"
echo ""

# Attach certificate to thing
echo "=== Attaching Certificate to Thing ==="
aws iot attach-thing-principal --thing-name "$THING_NAME" --principal "$CERT_ARN"
echo "Certificate attached to Thing successfully"
echo ""

# Save configuration metadata to PST
echo "=== Saving Certificate Metadata ==="

# Create metadata in temp location first
TEMP_METADATA="/tmp/cert-metadata.json"
cat > "$TEMP_METADATA" << EOF
{
  "certificateArn": "$CERT_ARN",
  "awsIotEndpoint": "$AWS_IOT_ENDPOINT",
  "awsRegion": "$AWS_REGION",
  "pikvmId": "$PIKVM_ID",
  "cpuSerial": "$CPU_SERIAL",
  "thingName": "$THING_NAME",
  "policyName": "$POLICY_NAME",
  "createdAt": "$(date -Iseconds)",
  "certFiles": {
    "rootCA": "$PST_CERTS_DIR/rootCA.pem",
    "certificate": "$PST_CERTS_DIR/cert.crt",
    "privateKey": "$PST_CERTS_DIR/private.key",
    "publicKey": "$PST_CERTS_DIR/public.key"
  }
}
EOF

# Create helper script to copy metadata to PST
cat > /tmp/copy_metadata_to_pst.sh << METADATA_EOF
#!/bin/bash
# Copy metadata to PST

CERT_DIR="$CERT_DIR_NAME"

cp /tmp/cert-metadata.json \$KVMD_PST_DATA/\$CERT_DIR/cert-metadata.json
chmod 644 \$KVMD_PST_DATA/\$CERT_DIR/cert-metadata.json

echo "Metadata saved to PST"
ls -la \$KVMD_PST_DATA/\$CERT_DIR/cert-metadata.json
METADATA_EOF

chmod +x /tmp/copy_metadata_to_pst.sh

# Copy metadata to PST
kvmd-pstrun -- /tmp/copy_metadata_to_pst.sh --some --script --args

# Clean up
rm /tmp/cert-metadata.json /tmp/copy_metadata_to_pst.sh

echo "Metadata saved to: $PST_CERTS_DIR/cert-metadata.json"
echo ""

# Ensure mosquitto user exists
echo "=== Ensuring mosquitto user exists ==="
if ! id mosquitto &>/dev/null; then
    echo "Creating mosquitto user and group..."
    groupadd --system mosquitto || true
    useradd  --system \
             --no-create-home \
             --gid mosquitto \
             --shell /usr/bin/nologin \
             mosquitto || true
fi

# Fix ownership of all files in PST (must be done outside PST context)
echo "=== Fixing file ownership ==="
chown -R mosquitto:mosquitto "$PST_CERTS_DIR"
echo "Ownership set to mosquitto:mosquitto"
echo ""

# Return to read-only mode
echo "=== Returning to read-only mode ==="
sync
sleep 1

if ! ro 2>/dev/null; then
    echo "Warning: Could not immediately remount as read-only (mount point busy)"
    echo "The system will automatically remount as read-only on next reboot"
fi

echo ""
echo "=== AWS IoT Certificate Setup Complete! ==="
echo ""
echo "Certificate Details:"
echo "  - ARN: $CERT_ARN"
echo "  - AWS IoT Endpoint: $AWS_IOT_ENDPOINT"
echo "  - Thing Name: $THING_NAME"
echo "  - Policy Name: $POLICY_NAME"
echo ""
echo "Certificate Files Location: $PST_CERTS_DIR"
echo "  - Root CA: rootCA.pem"
echo "  - Certificate: cert.crt"
echo "  - Private Key: private.key"
echo "  - Public Key: public.key"
echo "  - Metadata: cert-metadata.json"
echo ""
echo "Next Steps:"
echo "  1. Export AWS IoT endpoint for the main setup script:"
echo "     export AWS_IOT_ENDPOINT='$AWS_IOT_ENDPOINT'"
echo "  2. Run the main setup script: ./setup_mqtt_local_broker.sh"
echo ""
echo "To view certificate info later:"
echo "  cat $PST_CERTS_DIR/cert-metadata.json | grep -v privateKey"
echo ""
