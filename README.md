# PiKVM AWS IoT Setup

[![ShellCheck](https://github.com/ChezGroup/pikvm-aws-iot-setup/actions/workflows/shellcheck.yml/badge.svg)](https://github.com/ChezGroup/pikvm-aws-iot-setup/actions/workflows/shellcheck.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

Production-ready scripts for configuring PiKVM devices to connect to AWS IoT
Core via MQTT bridge using Mosquitto.

## 🚀 Quick Start

Install all scripts with a single command:

```bash
curl -sSL https://raw.githubusercontent.com/ChezGroup/pikvm-aws-iot-setup/main/install.sh | bash
```

Or using wget:

```bash
wget -qO- https://raw.githubusercontent.com/ChezGroup/pikvm-aws-iot-setup/main/install.sh | bash
```

## 📋 What's Included

- **`setup_aws_iot_certificates.sh`** - Generates and configures AWS IoT
  certificates
- **`setup_mqtt_local_broker.sh`** - Sets up Mosquitto MQTT broker in bridge
  mode
- **`troubleshoot_aws_iot.sh`** - Diagnoses and fixes AWS IoT connection issues
- **`manage_certificates.sh`** - Manages certificate lifecycle (backup, restore,
  verify)
- **`install.sh`** - Quick installer script
- **`config/config.sh.example`** - Configuration template

## 🛠️ Manual Installation

If you prefer manual installation:

```bash
# Enable write mode on PiKVM
rw

# Clone or download scripts
mkdir -p /root/pikvm-setup
cd /root/pikvm-setup

# Download individual scripts
curl -O https://raw.githubusercontent.com/ChezGroup/pikvm-aws-iot-setup/main/setup_aws_iot_certificates.sh
curl -O https://raw.githubusercontent.com/ChezGroup/pikvm-aws-iot-setup/main/setup_mqtt_local_broker.sh
curl -O https://raw.githubusercontent.com/ChezGroup/pikvm-aws-iot-setup/main/troubleshoot_aws_iot.sh
curl -O https://raw.githubusercontent.com/ChezGroup/pikvm-aws-iot-setup/main/manage_certificates.sh

# Make executable
chmod +x *.sh

# Download configuration template
mkdir -p config
curl -o config/config.sh.example https://raw.githubusercontent.com/ChezGroup/pikvm-aws-iot-setup/main/config/config.sh.example
```

## ⚙️ Configuration & Usage

**One-command installation:**

```bash
curl -sSL https://raw.githubusercontent.com/ChezGroup/pikvm-aws-iot-setup/main/install.sh | bash
```

**What the installer does:**

1. ✅ Enables write mode on PiKVM (`rw`)
2. ✅ Downloads all setup scripts
3. ✅ Creates configuration template
4. ✅ Returns to read-only mode (`ro`)

**Note:** AWS CLI and Mosquitto are automatically installed when you run the
setup scripts that need them (`setup_aws_iot_certificates.sh` and
`setup_mqtt_local_broker.sh` respectively).

### Step 1: Customize Settings

Create your configuration file:

```bash
cd /root/pikvm-setup
cp config/config.sh.example config/config.sh
nano config/config.sh
```

**Required Settings:**

```bash
# Project prefix for naming AWS IoT Things
export PROJECT_PREFIX="my-company"
```

### Step 2: Customize Settings

**Required Settings:**

```bash
# Project prefix for naming AWS IoT Things
export PROJECT_PREFIX="my-company"
```

**Optional Settings:**

```bash
# AWS Region (auto-detected if not set)
export AWS_REGION="us-east-1"

# MQTT Topics (defaults work with Tasmota)
export MQTT_TOPIC_TELE_SENSOR="tele/+/+/+/SENSOR"
export MQTT_TOPIC_TELE_STATE="tele/+/+/+/STATE"

# Device ID generation method
export DEVICE_ID_METHOD="cpu-serial"  # or "mac-address" or "custom"

# Custom Device ID (only if DEVICE_ID_METHOD="custom")
# export CUSTOM_DEVICE_ID="my-device-id"
```

See `config/config.sh.example` for all available options.

## 📖 Usage Guide

### Recommended Path: Certificate Mode (AWS IoT)

The certificate-based bridge is the recommended path. Run
`setup_aws_iot_certificates.sh` first (step 2 below): it stores the
certificates and `cert-metadata.json` in the PiKVM PST, and
`setup_mqtt_local_broker.sh` (step 3) auto-detects them and configures the
TLS bridge to AWS IoT Core on port `8883`, using the thing name
`pikvm-{PROJECT_PREFIX}-{DEVICE_ID}` as the prefix for all bridged topics.

### Bridge Mode: Password Authentication (External Brokers Only)

If no certificate metadata is found in the PST, the bridge falls back to
password authentication, which requires `BRIDGE_ADDRESS`,
`BRIDGE_REMOTE_USER`, and `BRIDGE_REMOTE_PASSWORD` in the environment. This
mode is meant for external MQTT brokers only and writes directional rules
only:

- `topic tele/# out 0 "" cloud/` and `topic stat/# out 0 "" cloud/` forward
  telemetry and status to the central broker under `cloud/`
- `topic cmnd/# in 0 "" cloud/` receives commands published under
  `cloud/cmnd/...`

**⚠️ Never use a bidirectional catch-all rule such as
`topic # both 0 "" cloud/`**: the bridge receives its own published messages
back and re-publishes them locally, creating an echo/self-loop. The
directional rules above replaced that pattern.

### 1. Configure AWS Credentials

Before running the scripts, configure AWS CLI:

```bash
aws configure
```

You'll need:

- AWS Access Key ID
- AWS Secret Access Key
- Default region (e.g., `us-east-1`)

### 2. Generate AWS IoT Certificates

```bash
cd /root/pikvm-setup
./setup_aws_iot_certificates.sh
```

This will:

- Create AWS IoT Thing (named `pikvm-{PROJECT_PREFIX}-{DEVICE_ID}`)
- Generate and download certificates
- Create IoT Policy with appropriate permissions
- Store certificates in PiKVM persistent storage (PST)

### 3. Setup Mosquitto MQTT Broker

```bash
./setup_mqtt_local_broker.sh
```

This will:

- Install Mosquitto
- Configure bridge mode to AWS IoT
- Set up local authentication
- Enable and start the service

### 4. Verify Connection

```bash
./troubleshoot_aws_iot.sh
```

This will:

- Check certificate status
- Verify policy attachments
- Test TLS connection
- Check Mosquitto bridge status

### 5. Monitor Logs

```bash
# Watch Mosquitto logs
journalctl -u mosquitto -f

# Check recent errors
journalctl -u mosquitto --since "10 minutes ago" --no-pager
```

## 🔧 Certificate Management

### Check Certificate Status

```bash
./manage_certificates.sh check
```

### View Certificate Information

```bash
./manage_certificates.sh info
```

### Verify Certificate Validity

```bash
./manage_certificates.sh verify
```

### Test AWS IoT Connection

```bash
./manage_certificates.sh test
```

### Backup Certificates

```bash
./manage_certificates.sh backup
```

### Restore from Backup

```bash
./manage_certificates.sh restore /tmp/pikvm-certs-backup-20241205.tar.gz
```

## 📁 File Structure

After installation:

```
/root/pikvm-setup/
├── config/
│   ├── config.sh.example    # Configuration template
│   └── config.sh            # Your configuration (not in git)
├── setup_aws_iot_certificates.sh
├── setup_mqtt_local_broker.sh
├── troubleshoot_aws_iot.sh
├── manage_certificates.sh
└── install.sh

/var/lib/kvmd/pst/mosquitto/  # Persistent storage
├── passwd                     # Local MQTT credentials
└── certs/                     # AWS IoT certificates
    ├── rootCA.pem
    ├── cert.crt
    ├── private.key
    ├── public.key
    └── cert-metadata.json
```

## 🔐 Security Considerations

### Configuration File

**⚠️ IMPORTANT:** Never commit `config/config.sh` to version control!

The `.gitignore` file excludes it automatically, but be careful when sharing:

```bash
# ✅ Safe - shares template
cat config/config.sh.example

# ❌ Dangerous - shares your configuration
cat config/config.sh
```

### AWS Credentials

- Use IAM users with minimal permissions
- Consider using temporary credentials (STS)
- Rotate access keys regularly
- Never hardcode credentials in scripts

### Certificates

- Certificates are stored in PiKVM PST (survives reboots)
- Private keys have `600` permissions
- Backup certificates to secure location
- Revoke certificates when decommissioning devices

## 🌍 Multi-Device Deployment

For deploying to multiple PiKVM devices:

### Option 1: Same Configuration

```bash
# On each device
curl -sSL https://raw.githubusercontent.com/ChezGroup/pikvm-aws-iot-setup/main/install.sh | bash
cd /root/pikvm-setup
cp config/config.sh.example config/config.sh
# Edit with same PROJECT_PREFIX
./setup_aws_iot_certificates.sh
./setup_mqtt_local_broker.sh
```

Each device will get a unique ID based on CPU serial or MAC address.

### Option 2: Custom Device IDs

```bash
# In config/config.sh on each device
export DEVICE_ID_METHOD="custom"
export CUSTOM_DEVICE_ID="warehouse-1"  # Unique per device
```

### Option 3: Scripted Deployment

```bash
# Create deployment script
for device in warehouse-1 warehouse-2 warehouse-3; do
    ssh root@pikvm-$device.local << 'EOF'
        curl -sSL https://raw.githubusercontent.com/ChezGroup/pikvm-aws-iot-setup/main/install.sh | bash
        cd /root/pikvm-setup
        cp config/config.sh.example config/config.sh
        sed -i 's/my-project/my-company/' config/config.sh
        ./setup_aws_iot_certificates.sh
        ./setup_mqtt_local_broker.sh
EOF
done
```

## 🐛 Troubleshooting

### Certificate Not Active

```bash
# Run troubleshoot script
./troubleshoot_aws_iot.sh

# It will automatically activate inactive certificates
```

### Bridge Not Connecting

```bash
# Check Mosquitto status
systemctl status mosquitto

# View detailed logs
journalctl -u mosquitto -n 100

# Restart service
systemctl restart mosquitto
```

### Permission Errors

```bash
# Fix certificate permissions
cd /var/lib/kvmd/pst/mosquitto/certs
chown -R mosquitto:mosquitto .
chmod 644 *.pem *.crt
chmod 600 private.key
```

### DNS Resolution Issues

```bash
# Test DNS
getent hosts $(grep awsIotEndpoint /var/lib/kvmd/pst/mosquitto/certs/cert-metadata.json | cut -d'"' -f4)

# Test TLS connection
./manage_certificates.sh test
```

## 📚 AWS IoT Policy

The default policy allows:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "iot:Connect",
      "Resource": "arn:aws:iot:*:*:client/*"
    },
    {
      "Effect": "Allow",
      "Action": ["iot:Publish", "iot:Receive"],
      "Resource": "arn:aws:iot:*:*:topic/*"
    },
    {
      "Effect": "Allow",
      "Action": "iot:Subscribe",
      "Resource": "arn:aws:iot:*:*:topicfilter/*"
    }
  ]
}
```

To use a custom policy, set `AWS_IOT_POLICY_DOCUMENT` in `config/config.sh`.

## 🔄 MQTT Topic Mapping

Default topic mapping (Tasmota compatible):

| Direction | Local Topic         | AWS IoT Topic                    |
| --------- | ------------------- | -------------------------------- |
| Out       | `tele/+/+/+/SENSOR` | `{THING_NAME}/tele/+/+/+/SENSOR` |
| Out       | `tele/+/+/+/STATE`  | `{THING_NAME}/tele/+/+/+/STATE`  |
| Out       | `stat/+/+/+/RESULT` | `{THING_NAME}/stat/+/+/+/RESULT` |
| Out       | `stat/+/+/+/POWER`  | `{THING_NAME}/stat/+/+/+/POWER`  |
| In        | `cmnd/#`            | `{THING_NAME}/cmd/#`             |

Customize topics in `config/config.sh`:

```bash
export MQTT_TOPIC_TELE_SENSOR="custom/sensor/#"
```

## 🤝 Contributing

Contributions are welcome! This project follows public repository best
practices:

1. Fork the repository
2. Create a feature branch
3. Test your changes on actual PiKVM hardware
4. Submit a pull request

## 📄 License

These scripts are provided as-is for use with PiKVM and AWS IoT Core.

## 🆘 Support

- **Issues**:
  [GitHub Issues](https://github.com/ChezGroup/pikvm-aws-iot-setup/issues)
- **Discussions**:
  [GitHub Discussions](https://github.com/ChezGroup/pikvm-aws-iot-setup/discussions)
- **PiKVM Docs**: https://docs.pikvm.org

## 🔗 Related Projects

- [PiKVM](https://pikvm.org) - Open-source KVM over IP
- [AWS IoT Core](https://aws.amazon.com/iot-core/) - Managed cloud service
- [Mosquitto](https://mosquitto.org/) - MQTT broker

---

**Note**: These scripts are designed for PiKVM running Arch Linux. Adaptations
may be needed for other platforms.
