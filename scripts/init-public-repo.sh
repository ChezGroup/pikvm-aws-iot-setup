#!/bin/bash
# Initialize Public Repository
# This script helps create and publish the pikvm-aws-iot-setup public repository

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

print_info() { echo -e "${BLUE}ℹ${NC} $1"; }
print_success() { echo -e "${GREEN}✓${NC} $1"; }
print_warning() { echo -e "${YELLOW}⚠${NC} $1"; }
print_error() { echo -e "${RED}✗${NC} $1"; }

PUBLIC_DIR="/Users/avadakedrava/Documents/Engineering/tandera/pikvm-public"
REPO_NAME="pikvm-aws-iot-setup"
REPO_OWNER="ChezGroup"

echo ""
echo "╔═══════════════════════════════════════════════════════════╗"
echo "║                                                           ║"
echo "║     PiKVM AWS IoT Setup - Public Repo Initializer         ║"
echo "║                                                           ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""

# Check if directory exists
if [ ! -d "$PUBLIC_DIR" ]; then
    print_error "Public directory not found: $PUBLIC_DIR"
    exit 1
fi

cd "$PUBLIC_DIR"

print_info "Current directory: $(pwd)"
echo ""

# Check if git is initialized
if [ ! -d ".git" ]; then
    print_info "Initializing git repository..."
    git init
    print_success "Git initialized"
else
    print_warning "Git already initialized"
fi
echo ""

# Validate scripts
print_info "Validating shell scripts..."
VALIDATION_FAILED=false

for script in *.sh; do
    if [ -f "$script" ]; then
        # Check if executable
        if [ ! -x "$script" ]; then
            print_error "$script is not executable"
            chmod +x "$script"
            print_success "Fixed: $script is now executable"
        fi

        # Check syntax
        if bash -n "$script"; then
            print_success "$script: syntax OK"
        else
            print_error "$script: syntax error"
            VALIDATION_FAILED=true
        fi
    fi
done

if [ "$VALIDATION_FAILED" = true ]; then
    print_error "Validation failed. Please fix errors before proceeding."
    exit 1
fi
echo ""

# Check required files
print_info "Checking required files..."
REQUIRED_FILES=(
    "setup_aws_iot_certificates.sh"
    "setup_mqtt_local_broker.sh"
    "troubleshoot_aws_iot.sh"
    "manage_certificates.sh"
    "install.sh"
    "config/config.sh.example"
    "README.md"
    "LICENSE"
    ".gitignore"
    ".github/workflows/shellcheck.yml"
    ".github/workflows/validate.yml"
)

MISSING_FILES=false
for file in "${REQUIRED_FILES[@]}"; do
    if [ ! -f "$file" ]; then
        print_error "Missing: $file"
        MISSING_FILES=true
    else
        print_success "Found: $file"
    fi
done

if [ "$MISSING_FILES" = true ]; then
    print_error "Some required files are missing"
    exit 1
fi
echo ""

# Show git status
print_info "Git status:"
git status --short
echo ""

# Ask to proceed
print_warning "Ready to create repository: ${REPO_OWNER}/${REPO_NAME}"
echo ""
echo "This will:"
echo "  1. Stage all files"
echo "  2. Create initial commit"
echo "  3. Set main branch"
echo "  4. Configure remote (you'll need to create the GitHub repo first)"
echo ""
read -p "Do you want to proceed? (y/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    print_info "Aborted by user"
    exit 0
fi
echo ""

# Stage files
print_info "Staging files..."
git add .
print_success "Files staged"
echo ""

# Create initial commit
print_info "Creating initial commit..."
git commit -m "Initial release: PiKVM AWS IoT Setup v1.0.0

This is the first public release of the PiKVM AWS IoT Setup scripts.

Features:
- Automated AWS IoT certificate generation
- Mosquitto MQTT bridge configuration
- Certificate management tools
- Comprehensive troubleshooting utilities
- Full documentation and examples
- CI/CD with GitHub Actions

Scripts are fully configurable via config/config.sh for multi-project use.

Tested on PiKVM v4 with Arch Linux and AWS IoT Core.
"
print_success "Initial commit created"
echo ""

# Set main branch
print_info "Setting main branch..."
git branch -M main
print_success "Main branch set"
echo ""

# Instructions for GitHub
echo ""
print_warning "Next steps (manual):"
echo ""
echo "1. Create the GitHub repository:"
echo "   - Go to: https://github.com/organizations/${REPO_OWNER}/repositories/new"
echo "   - Repository name: ${REPO_NAME}"
echo "   - Description: Production-ready scripts for PiKVM AWS IoT integration"
echo "   - Visibility: Public"
echo "   - DO NOT initialize with README, .gitignore, or license"
echo ""

echo "2. Add remote and push:"
echo "   ${BLUE}cd $PUBLIC_DIR${NC}"
echo "   ${BLUE}git remote add origin git@github.com:${REPO_OWNER}/${REPO_NAME}.git${NC}"
echo "   ${BLUE}git push -u origin main${NC}"
echo ""

echo "3. Create first release:"
echo "   ${BLUE}git tag -a v1.0.0 -m \"Release v1.0.0\"${NC}"
echo "   ${BLUE}git push origin v1.0.0${NC}"
echo ""

echo "4. Configure GitHub repository settings:"
echo "   - Topics: pikvm, aws-iot, mqtt, mosquitto, iot, automation"
echo "   - Enable Issues"
echo "   - Enable Discussions (optional)"
echo "   - Set up branch protection for main"
echo ""

print_success "Repository initialized and ready to push!"
echo ""
