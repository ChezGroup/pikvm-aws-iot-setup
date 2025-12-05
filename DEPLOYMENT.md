# Deployment Guide

This guide explains how to deploy the PiKVM AWS IoT Setup scripts to your PiKVM
devices.

## Prerequisites

- PiKVM device (v4 recommended, running Arch Linux)
- Network connectivity to PiKVM
- SSH access configured
- AWS account with IoT Core enabled
- AWS CLI credentials (will be configured during setup)

## Deployment Methods

### Method 1: Quick Install (Recommended)

The fastest way to get started:

```bash
# On the PiKVM (via SSH)
curl -sSL https://raw.githubusercontent.com/ChezGroup/pikvm-aws-iot-setup/main/install.sh | bash
```

This will:

- Download all scripts to `/root/pikvm-setup`
- Create configuration template
- Set up directory structure
- Make scripts executable

### Method 2: Manual Installation

For more control over the installation:

```bash
# Enable write mode
rw

# Create directory
mkdir -p /root/pikvm-setup
cd /root/pikvm-setup

# Download scripts
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

### Method 3: Git Clone

If you want to track updates:

```bash
# Enable write mode
rw

# Clone repository
cd /root
git clone https://github.com/ChezGroup/pikvm-aws-iot-setup.git pikvm-setup
cd pikvm-setup

# Copy configuration template
cp config/config.sh.example config/config.sh
```

## Configuration

### Step 1: Create Configuration File

```bash
cd /root/pikvm-setup
cp config/config.sh.example config/config.sh
nano config/config.sh
```

### Step 2: Set Required Variables

Minimum configuration:

```bash
# Required: Your project/company identifier
export PROJECT_PREFIX="my-company"
```

### Step 3: Optional Customization

Customize as needed:

```bash
# Device identification
export DEVICE_ID_METHOD="cpu-serial"  # or "mac-address" or "custom"
export DEVICE_ID_LENGTH="8"

# AWS Region (auto-detected if not set)
# export AWS_REGION="us-east-1"

# MQTT Topics (defaults work with Tasmota)
export MQTT_TOPIC_TELE_SENSOR="tele/+/+/+/SENSOR"
export MQTT_TOPIC_TELE_STATE="tele/+/+/+/STATE"
```

## AWS Credentials Setup

Configure AWS CLI with your credentials:

```bash
aws configure
```

You'll need:

- AWS Access Key ID
- AWS Secret Access Key
- Default region (e.g., `us-east-1`)
- Output format (json recommended)

## Setup Process

### 1. Generate AWS IoT Certificates

```bash
cd /root/pikvm-setup
./setup_aws_iot_certificates.sh
```

This will:

- Create AWS IoT Thing (named `pikvm-{PROJECT_PREFIX}-{DEVICE_ID}`)
- Generate device certificates
- Create and attach IoT Policy
- Store certificates in PiKVM PST

### 2. Configure MQTT Broker

```bash
./setup_mqtt_local_broker.sh
```

This will:

- Install Mosquitto
- Configure bridge to AWS IoT
- Set up local authentication
- Enable and start service

### 3. Verify Connection

```bash
./troubleshoot_aws_iot.sh
```

This will:

- Check certificate status
- Verify policy attachments
- Test TLS connection
- Validate bridge status

### 4. Monitor Operation

Watch logs in real-time:

```bash
journalctl -u mosquitto -f
```

Check recent activity:

```bash
journalctl -u mosquitto --since "10 minutes ago"
```

## Multi-Device Deployment

### Using a Deployment Script

Create a deployment script for multiple devices:

```bash
#!/bin/bash
# deploy_all.sh

DEVICES=(
    "pikvm-1.local"
    "pikvm-2.local"
    "pikvm-3.local"
)

for device in "${DEVICES[@]}"; do
    echo "Deploying to $device..."

    ssh root@$device bash <<'SCRIPT'
        curl -sSL https://raw.githubusercontent.com/ChezGroup/pikvm-aws-iot-setup/main/install.sh | bash
        cd /root/pikvm-setup
        cp config/config.sh.example config/config.sh
        sed -i 's/my-project/my-company/' config/config.sh
        # Additional configuration as needed
SCRIPT

    echo "Deployed to $device"
done
```

### Ansible Playbook

Example Ansible playbook:

```yaml
---
- name: Deploy PiKVM AWS IoT Setup
  hosts: pikvms
  become: yes

  tasks:
    - name: Enable write mode
      command: rw

    - name: Run installer
      shell:
        curl -sSL
        https://raw.githubusercontent.com/ChezGroup/pikvm-aws-iot-setup/main/install.sh
        | bash

    - name: Configure project prefix
      lineinfile:
        path: /root/pikvm-setup/config/config.sh
        line: 'export PROJECT_PREFIX="my-company"'
        create: yes

    - name: Return to read-only
      command: ro
```

## Troubleshooting Deployment

### Installation Failed

```bash
# Check disk space
df -h

# Check network connectivity
ping -c 3 raw.githubusercontent.com

# Verify write mode
mount | grep " / "
```

### Configuration Issues

```bash
# Validate configuration syntax
bash -n /root/pikvm-setup/config/config.sh

# Check variable values
source /root/pikvm-setup/config/config.sh
echo "Project: $PROJECT_PREFIX"
echo "Device ID Method: $DEVICE_ID_METHOD"
```

### Permission Errors

```bash
# Fix script permissions
cd /root/pikvm-setup
chmod +x *.sh

# Fix certificate permissions (if already generated)
cd /var/lib/kvmd/pst/mosquitto/certs
chown -R mosquitto:mosquitto .
chmod 644 *.pem *.crt
chmod 600 private.key
```

## Post-Deployment Checklist

- [ ] Scripts installed successfully
- [ ] Configuration file created and customized
- [ ] AWS credentials configured
- [ ] Certificates generated
- [ ] AWS IoT Thing visible in AWS Console
- [ ] Mosquitto service running
- [ ] Bridge connection established
- [ ] Test messages flowing
- [ ] Certificates backed up
- [ ] Device documented in inventory

## Updating Existing Installation

To update scripts on a deployed PiKVM:

```bash
# SSH into PiKVM
ssh root@pikvm-hostname.local

# Enable write mode
rw

# Backup current configuration
cp /root/pikvm-setup/config/config.sh /tmp/config.sh.backup

# Re-run installer (preserves config.sh)
curl -sSL https://raw.githubusercontent.com/ChezGroup/pikvm-aws-iot-setup/main/install.sh | bash

# Restart services if needed
systemctl restart mosquitto

# Return to read-only
ro
```

## Best Practices

1. **Always backup certificates** before major changes
2. **Test on one device** before mass deployment
3. **Document device IDs** in your inventory system
4. **Use consistent naming** for PROJECT_PREFIX across all devices
5. **Monitor logs** after deployment
6. **Keep AWS credentials secure** - never commit to git
7. **Rotate credentials** periodically
8. **Tag releases** when deploying to production

## Support

For deployment issues:

- Check [Troubleshooting Guide](README.md#troubleshooting)
- Review logs: `journalctl -u mosquitto -n 100`
- Open an issue:
  [GitHub Issues](https://github.com/ChezGroup/pikvm-aws-iot-setup/issues)

---

Last updated: 2025-12-05
