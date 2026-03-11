#!/bin/bash
# Script for setup Apache Mosquitto in Bridge mode
# Supports both password and certificate-based authentication
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
CERT_DIR_NAME="${CERT_DIR_NAME:-mosquitto/certs}"
MQTT_LOCAL_PORT="${MQTT_LOCAL_PORT:-1883}"
MQTT_KEEPALIVE="${MQTT_KEEPALIVE:-60}"
MQTT_RESTART_TIMEOUT="${MQTT_RESTART_TIMEOUT:-10}"
MQTT_MAX_PACKET_SIZE="${MQTT_MAX_PACKET_SIZE:-268435455}"
MQTT_TOPIC_TELE_SENSOR="${MQTT_TOPIC_TELE_SENSOR:-tele/+/+/+/SENSOR}"
MQTT_TOPIC_TELE_STATE="${MQTT_TOPIC_TELE_STATE:-tele/+/+/+/STATE}"
MQTT_TOPIC_STAT_RESULT="${MQTT_TOPIC_STAT_RESULT:-stat/+/+/+/RESULT}"
MQTT_TOPIC_STAT_POWER="${MQTT_TOPIC_STAT_POWER:-stat/+/+/+/POWER}"
MQTT_TOPIC_CMD_PATTERN="${MQTT_TOPIC_CMD_PATTERN:-cmd/#}"
MQTT_TOPIC_CMND_PREFIX="${MQTT_TOPIC_CMND_PREFIX:-cmnd/}"
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

# Detect authentication mode (AWS IoT certificates or password)
USE_AWS_IOT=false
PST_CERTS_DIR="/var/lib/kvmd/pst/$CERT_DIR_NAME"

if [ -f "$PST_CERTS_DIR/cert-metadata.json" ]; then
    echo "=== AWS IoT certificates detected ==="
    USE_AWS_IOT=true
    echo "Using certificate-based authentication for bridge"
    echo ""
fi

echo "=== Installing Apache Mosquitto ==="
pacman -S mosquitto --noconfirm

echo "=== Creating helper script for password creation ==="
# Create a helper script that will run inside PST session
cat > /tmp/create_mosquitto_passwd.sh << 'HELPER_EOF'
#!/bin/bash
# This script runs inside kvmd-pstrun to create password file in PST

# Create mosquitto directory in PST if it doesn't exist
mkdir -p $KVMD_PST_DATA/mosquitto

# Prompt for username if not provided
if [ -z "$1" ]; then
    read -p "Enter MQTT username: " mqtt_user
else
    mqtt_user="$1"
fi

# Create password file in PST
mosquitto_passwd -c $KVMD_PST_DATA/mosquitto/passwd "$mqtt_user"

# Set proper permissions (read-only)
chmod 400 $KVMD_PST_DATA/mosquitto/passwd

echo "Password file created at: $KVMD_PST_DATA/mosquitto/passwd"
echo "Full path: $(readlink -f $KVMD_PST_DATA/mosquitto/passwd)"
ls -la $KVMD_PST_DATA/mosquitto/passwd
HELPER_EOF

chmod +x /tmp/create_mosquitto_passwd.sh

echo "=== Creating password file in PST ==="
# Prompt for username
read -p "Enter MQTT username: " mqtt_user

# Run the helper script inside PST session
kvmd-pstrun -- /tmp/create_mosquitto_passwd.sh "$mqtt_user"

# Clean up helper script
rm /tmp/create_mosquitto_passwd.sh

echo "=== Ensuring PST mosquitto directory exists and fixing permissions ==="
# The actual PST path is /var/lib/kvmd/pst (not /var/lib/kvmd/pst/data)
PST_MOSQUITTO_DIR="/var/lib/kvmd/pst/mosquitto"

# Create helper script to ensure mosquitto directory exists in PST
cat > /tmp/ensure_pst_mosquitto_dir.sh << 'ENSURE_DIR_EOF'
#!/bin/bash
# Ensure mosquitto directory exists in PST

mkdir -p $KVMD_PST_DATA/mosquitto
chmod 755 $KVMD_PST_DATA/mosquitto

echo "PST mosquitto directory ensured at: $KVMD_PST_DATA/mosquitto"
ls -la $KVMD_PST_DATA/mosquitto/
ENSURE_DIR_EOF

chmod +x /tmp/ensure_pst_mosquitto_dir.sh

# Ensure directory exists via PST
kvmd-pstrun -- /tmp/ensure_pst_mosquitto_dir.sh

# Clean up helper script
rm /tmp/ensure_pst_mosquitto_dir.sh

# Verify password file was created and fix permissions (outside PST context)
if [ -f "$PST_MOSQUITTO_DIR/passwd" ]; then
    echo "Password file found at: $PST_MOSQUITTO_DIR/passwd"
    chown mosquitto:mosquitto "$PST_MOSQUITTO_DIR/passwd"
    chmod 0700 "$PST_MOSQUITTO_DIR/passwd"
    ls -la "$PST_MOSQUITTO_DIR/passwd"
    echo "Password file permissions fixed (read-only for mosquitto user)"
else
    echo "ERROR: Password file was not created at $PST_MOSQUITTO_DIR/passwd"
    echo "Checking what exists in PST:"
    ls -laR /var/lib/kvmd/pst/
    exit 1
fi

echo "=== Reading bridge configuration from environment variables ==="

if [ "$USE_AWS_IOT" = true ]; then
    echo "Loading AWS IoT configuration from certificate metadata..."

    # Load configuration from metadata file
    AWS_IOT_ENDPOINT=$(grep -o '"awsIotEndpoint": "[^"]*"' "$PST_CERTS_DIR/cert-metadata.json" | cut -d'"' -f4)
    THING_NAME=$(grep -o '"thingName": "[^"]*"' "$PST_CERTS_DIR/cert-metadata.json" | cut -d'"' -f4)

    if [ -z "$AWS_IOT_ENDPOINT" ]; then
        echo "Error: Could not read AWS IoT endpoint from metadata"
        exit 1
    fi

    BRIDGE_ADDRESS="${AWS_IOT_ENDPOINT}:8883"
    echo "AWS IoT Endpoint: $AWS_IOT_ENDPOINT"
    echo "Thing Name: $THING_NAME"
    echo "Bridge will use TLS with client certificates"
    echo ""

    # Verify certificate files exist
    for cert_file in rootCA.pem cert.crt private.key; do
        if [ ! -f "$PST_CERTS_DIR/$cert_file" ]; then
            echo "Error: Certificate file not found: $PST_CERTS_DIR/$cert_file"
            echo "Please run setup_aws_iot_certificates.sh first"
            exit 1
        fi
    done

else
    echo "Using password-based authentication for bridge..."
    echo ""

    # Bridge configuration from environment variables - all required
    if [ -z "$BRIDGE_ADDRESS" ]; then
        echo "Error: BRIDGE_ADDRESS environment variable is not set"
        echo "Example: export BRIDGE_ADDRESS='mqtt.example.com:1883'"
        echo ""
        echo "Alternatively, run setup_aws_iot_certificates.sh to use AWS IoT"
        exit 1
    fi

    if [ -z "$BRIDGE_REMOTE_USER" ]; then
        echo "Error: BRIDGE_REMOTE_USER environment variable is not set"
        echo "Example: export BRIDGE_REMOTE_USER='username'"
        exit 1
    fi

    if [ -z "$BRIDGE_REMOTE_PASSWORD" ]; then
        echo "Error: BRIDGE_REMOTE_PASSWORD environment variable is not set"
        echo "Example: export BRIDGE_REMOTE_PASSWORD='password'"
        exit 1
    fi

    echo "Bridge Address: $BRIDGE_ADDRESS"
    echo "Remote Username: $BRIDGE_REMOTE_USER"
    echo ""
fi

echo "=== Creating Mosquitto configuration ==="
# Backup original config if it exists
if [ -f /etc/mosquitto/mosquitto.conf ]; then
    cp /etc/mosquitto/mosquitto.conf /etc/mosquitto/mosquitto.conf.backup
fi

# Create new configuration file
cat > /etc/mosquitto/mosquitto.conf << EOF
# Mosquitto Configuration for Bridge Mode
# Using PiKVM PST for persistent data

# General Settings
persistence false
autosave_interval 0

# Logging to journal (systemd)
log_dest syslog
log_type error
log_type warning
log_type notice
log_type information
log_type debug

# Connection logging
connection_messages true

# Local Listener
listener $MQTT_LOCAL_PORT
protocol mqtt

# Authentication - password file in PST
allow_anonymous false
password_file /var/lib/kvmd/pst/mosquitto/passwd

EOF

# Add bridge configuration based on authentication mode
if [ "$USE_AWS_IOT" = true ]; then
    cat >> /etc/mosquitto/mosquitto.conf << EOF
# ============================================================
# Bridge to AWS IoT Core
# ============================================================
connection awsiot
address $BRIDGE_ADDRESS

# Specifying which topics are bridged
# Forward only telemetry topics to AWS IoT (avoid retained messages)
# Syntax: topic pattern direction QoS local_prefix remote_prefix
topic $MQTT_TOPIC_TELE_SENSOR out 0 "" ${THING_NAME}/
topic $MQTT_TOPIC_TELE_STATE out 0 "" ${THING_NAME}/
topic $MQTT_TOPIC_STAT_RESULT out 0 "" ${THING_NAME}/
topic $MQTT_TOPIC_STAT_POWER out 0 "" ${THING_NAME}/

# Receive commands from AWS IoT directed to this device
topic ${THING_NAME}/$MQTT_TOPIC_CMD_PATTERN in 0 "" $MQTT_TOPIC_CMND_PREFIX

# Setting protocol version explicitly
bridge_protocol_version mqttv311
bridge_insecure false

# Bridge connection settings
cleansession true
remote_clientid ${THING_NAME}
local_cleansession true
start_type automatic
notifications false
try_private false
bridge_attempt_unsubscribe false
keepalive_interval $MQTT_KEEPALIVE
restart_timeout $MQTT_RESTART_TIMEOUT
bridge_max_packet_size $MQTT_MAX_PACKET_SIZE

# ============================================================
# Certificate based SSL/TLS support - AWS IoT
# ============================================================
# Path to the Amazon Root CA
bridge_cafile $PST_CERTS_DIR/rootCA.pem

# Path to the PEM encoded client certificate
bridge_certfile $PST_CERTS_DIR/cert.crt

# Path to the PEM encoded client private key
bridge_keyfile $PST_CERTS_DIR/private.key

# Enable TLS
bridge_tls_version tlsv1.2

EOF
else
    cat >> /etc/mosquitto/mosquitto.conf << EOF
# ============================================================
# Bridge to Central MQTT Broker (Password Authentication)
# ============================================================
connection central-broker
address $BRIDGE_ADDRESS

# Specifying which topics are bridged
topic # both 0 "" cloud/

# Bridge authentication
remote_username $BRIDGE_REMOTE_USER
remote_password $BRIDGE_REMOTE_PASSWORD

# Bridge connection settings
cleansession true
notifications true
start_type automatic
try_private false
bridge_attempt_unsubscribe true

EOF
fi

echo "Mosquitto configuration created successfully"
echo ""

echo "=== Configuring systemd service for auto-restart ==="
# Create systemd drop-in directory for service overrides
mkdir -p /etc/systemd/system/mosquitto.service.d

# Create override configuration for automatic restart
cat > /etc/systemd/system/mosquitto.service << 'SYSTEMD_EOF'
[Unit]
Description=Mosquitto MQTT Broker daemon
Requires=network.target
After=network-online.target
Wants=network-online.target

[Service]
Restart=always
RestartSec=5
Type=notify
NotifyAccess=main
User=mosquitto
ExecStart=/usr/bin/mosquitto -c /etc/mosquitto/mosquitto.conf
ExecReload=/bin/kill -HUP $MAINPID

# Watchdog to detect frozen processes
WatchdogSec=0

NoNewPrivileges=yes
ProtectSystem=full
ProtectHome=true
PrivateTmp=true
PrivateDevices=true

[Install]
WantedBy=multi-user.target

SYSTEMD_EOF

# Reload systemd to apply changes
systemctl daemon-reload

echo "=== Enabling and starting Mosquitto service ==="
systemctl enable mosquitto
systemctl start mosquitto

# Rollback to read-only mode
echo "=== Returning to read-only mode ==="
sync  # Ensure all pending writes are flushed
sleep 1  # Give the system a moment to finish operations

# Try to remount as read-only, but don't fail if it's busy
if ! ro 2>/dev/null; then
    echo "Warning: Could not immediately remount as read-only (mount point busy)"
    echo "The system will automatically remount as read-only on next reboot"
    echo "Or you can manually run 'ro' after closing all active processes"
fi


echo ""
echo "=== Setup complete! ==="
echo "Mosquitto is running on port 1883 (PiKVM PST Mode)"
echo "Local Username: $mqtt_user"
echo ""

if [ "$USE_AWS_IOT" = true ]; then
    echo "Bridge Mode: AWS IoT Core (Certificate Authentication)"
    echo "AWS IoT Endpoint: $AWS_IOT_ENDPOINT"
    echo "Thing Name: $THING_NAME"
    echo "Certificates Location: $PST_CERTS_DIR"
else
    echo "Bridge Mode: Custom MQTT Broker (Password Authentication)"
    echo "Bridge Address: $BRIDGE_ADDRESS"
    echo "Bridge Remote User: $BRIDGE_REMOTE_USER"
fi

echo ""
echo "Persistent data location: /var/lib/kvmd/pst/mosquitto/"
echo "  - Password file: /var/lib/kvmd/pst/mosquitto/passwd"

if [ "$USE_AWS_IOT" = true ]; then
    echo "  - Certificates: /var/lib/kvmd/pst/mosquitto/certs/"
fi

echo ""
echo "To add more local users, create this script:"
echo "  cat > /root/add_mqtt_user.sh << 'USEREOF'"
echo "  #!/bin/bash"
echo "  mosquitto_passwd /var/lib/kvmd/pst/mosquitto/passwd \\\$1"
echo "  USEREOF"
echo "  chmod +x /root/add_mqtt_user.sh"
echo ""
echo "Then run: kvmd-pstrun -- /root/add_mqtt_user.sh <username>"
echo ""
echo "To view logs: journalctl -u mosquitto -f"
echo "After changes, restart with: systemctl restart mosquitto"
echo ""

if [ "$USE_AWS_IOT" = true ]; then
    echo "AWS IoT Connection Test:"
    echo "  Watch logs: journalctl -u mosquitto -f"
    echo "  Look for: 'Bridge awsiot established'"
    echo ""
fi
