#!/bin/bash
# Quick Installation Script for PiKVM AWS IoT Setup
# This script downloads and sets up the PiKVM AWS IoT configuration scripts
#
# Usage:
#   curl -sSL https://raw.githubusercontent.com/ChezGroup/pikvm-aws-iot-setup/main/install.sh | bash
#   or
#   wget -qO- https://raw.githubusercontent.com/ChezGroup/pikvm-aws-iot-setup/main/install.sh | bash

set -e

# Configuration
REPO_OWNER="ChezGroup"
REPO_NAME="pikvm-aws-iot-setup"
BRANCH="main"
BASE_URL="https://raw.githubusercontent.com/${REPO_OWNER}/${REPO_NAME}/${BRANCH}"
INSTALL_DIR="/root/pikvm-setup"

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Functions for colored output
print_info() { echo -e "${BLUE}ℹ${NC} $1"; }
print_success() { echo -e "${GREEN}✓${NC} $1"; }
print_warning() { echo -e "${YELLOW}⚠${NC} $1"; }
print_error() { echo -e "${RED}✗${NC} $1"; }

# Welcome message
echo ""
echo "╔═══════════════════════════════════════════════════════════╗"
echo "║                                                           ║"
echo "║        PiKVM AWS IoT Setup - Quick Installer              ║"
echo "║                                                           ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""

# Check if running on PiKVM
if [ ! -f /usr/bin/kvmd ]; then
    print_warning "This script is designed for PiKVM systems"
    read -p "Continue anyway? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_info "Installation cancelled"
        exit 0
    fi
fi

# Enable write mode if on PiKVM
if command -v rw &> /dev/null; then
    print_info "Enabling write mode..."
    rw
fi

# Create installation directory
print_info "Creating installation directory: $INSTALL_DIR"
mkdir -p "$INSTALL_DIR"
cd "$INSTALL_DIR"

# Download scripts
print_info "Downloading setup scripts from GitHub..."

SCRIPTS=(
    "setup_aws_iot_certificates.sh"
    "setup_mqtt_local_broker.sh"
    "troubleshoot_aws_iot.sh"
    "manage_certificates.sh"
)

for script in "${SCRIPTS[@]}"; do
    print_info "  Downloading $script..."
    if curl -sSL "${BASE_URL}/${script}" -o "$script"; then
        chmod +x "$script"
        print_success "  $script downloaded"
    else
        print_error "  Failed to download $script"
        exit 1
    fi
done

# Download configuration template
print_info "Downloading configuration template..."
mkdir -p config
if curl -sSL "${BASE_URL}/config/config.sh.example" -o "config/config.sh.example"; then
    print_success "Configuration template downloaded"
else
    print_error "Failed to download configuration template"
    exit 1
fi

# Check if config.sh already exists
if [ -f "config/config.sh" ]; then
    print_warning "config/config.sh already exists. Keeping existing configuration."
else
    # Prompt user to create configuration
    echo ""
    print_info "Configuration Setup"
    echo ""
    read -p "Do you want to create a configuration file now? (Y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Nn]$ ]]; then
        cp config/config.sh.example config/config.sh

        # Prompt for project prefix
        read -p "Enter your project prefix [default-project]: " project_prefix
        project_prefix=${project_prefix:-default-project}

        # Update config file with project prefix
        sed -i "s/export PROJECT_PREFIX=\"my-project\"/export PROJECT_PREFIX=\"$project_prefix\"/" config/config.sh

        print_success "Configuration file created at config/config.sh"
        print_info "You can edit config/config.sh to customize settings"
    else
        print_info "You can create config/config.sh later by copying config/config.sh.example"
    fi
fi

# Return to read-only mode if on PiKVM
if command -v ro &> /dev/null; then
    print_info "Returning to read-only mode..."
    sync
    sleep 1
    ro 2>/dev/null || print_warning "Could not remount as read-only (may require reboot)"
fi

# Success message
echo ""
print_success "Installation complete!"
echo ""
echo "Scripts installed in: $INSTALL_DIR"
echo ""
echo "Next steps:"
echo ""
echo "  1. Configure your setup:"
echo -e "     ${BLUE}nano $INSTALL_DIR/config/config.sh${NC}"
echo ""
echo "  2. Set up AWS IoT certificates:"
echo -e "     ${BLUE}cd $INSTALL_DIR && ./setup_aws_iot_certificates.sh${NC}"
echo ""
echo "  3. Configure Mosquitto MQTT broker:"
echo -e "     ${BLUE}cd $INSTALL_DIR && ./setup_mqtt_local_broker.sh${NC}"
echo ""
echo "  4. Test your connection:"
echo -e "     ${BLUE}cd $INSTALL_DIR && ./troubleshoot_aws_iot.sh${NC}"
echo ""
echo "For detailed documentation, visit:"
echo -e "  ${BLUE}https://github.com/${REPO_OWNER}/${REPO_NAME}${NC}"
echo ""
