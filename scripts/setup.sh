#!/bin/bash
# Containerized Vulnerability Scanner
# Copyright (C) 2026 Evan Hardt
#
# This program is licensed under AGPL v3 for open-source use.
# Commercial licenses available - contact: evan@texashardts.com
#
# For the full license, see LICENSE file in the root directory.

echo "=================================="
echo "Containerized Vulnerability Scanner Setup"
echo "=================================="
echo ""

# Check if Incus is installed
INCUS_INSTALLED=false
if ! command -v incus &> /dev/null; then
    echo "Incus is not installed. Installing from Zabbly repository..."
    echo ""
    
    # Detect OS version
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS_CODENAME=$VERSION_CODENAME
        
        if [ -z "$OS_CODENAME" ]; then
            # Fallback for Pop!_OS and others
            OS_CODENAME=$(lsb_release -sc 2>/dev/null || echo "jammy")
        fi
    else
        OS_CODENAME="jammy"
    fi
    
    echo "Detected OS codename: $OS_CODENAME"
    echo ""
    
    # Install Zabbly repository
    echo "[Setup] Adding Zabbly Incus repository..."
    sudo mkdir -p /etc/apt/keyrings/
    curl -fsSL https://pkgs.zabbly.com/key.asc | sudo gpg --dearmor -o /etc/apt/keyrings/zabbly.gpg
    
    echo "Types: deb
URIs: https://pkgs.zabbly.com/incus/stable
Suites: $OS_CODENAME
Components: main
Architectures: amd64
Signed-By: /etc/apt/keyrings/zabbly.gpg" | sudo tee /etc/apt/sources.list.d/zabbly-incus-stable.sources
    
    # Install Incus and ZFS tools
    echo ""
    echo "[Setup] Installing Incus and dependencies..."
    sudo apt update
    sudo apt install -y incus incus-tools zfsutils-linux
    
    # Add user to incus-admin group
    echo ""
    echo "[Setup] Adding user to incus-admin group..."
    sudo usermod -a -G incus-admin $USER
    
    INCUS_INSTALLED=true
    
    echo ""
    echo "⚠️  IMPORTANT: You need to log out and back in for group membership to take effect!"
    echo "⚠️  After logging back in, re-run this script to complete setup."
    echo ""
    exit 0
    
else
    echo "✓ Incus is already installed"
fi

# Check if user is in incus-admin group
if ! groups | grep -q incus-admin; then
    echo ""
    echo "⚠️  ERROR: You are not in the incus-admin group!"
    echo "⚠️  Please log out and log back in, then re-run this script."
    echo ""
    exit 1
fi

# Check if Incus is initialized by looking for storage pools
echo ""
echo "[Setup] Checking Incus initialization..."
if ! sudo incus storage list 2>/dev/null | grep -q .; then
    echo "Incus needs to be initialized. Running setup..."
    echo ""
    
    # Simple automated init - just say yes to defaults
    echo "Running 'incus admin init --minimal' for quick setup..."
    sudo incus admin init --minimal
    
    if [ $? -ne 0 ]; then
        echo ""
        echo "ERROR: Incus initialization failed!"
        echo "Please run 'sudo incus admin init' manually and then re-run this script."
        exit 1
    fi
    
    echo "✓ Incus initialized successfully"
else
    echo "✓ Incus is already initialized"
fi

# Verify storage pool exists
echo ""
echo "Verifying storage pool..."
if ! sudo incus storage list | grep -q default; then
    echo "No default storage pool found. Creating one..."
    sudo incus storage create default dir
    if [ $? -ne 0 ]; then
        echo "ERROR: Failed to create storage pool!"
        exit 1
    fi
fi

# Configure UFW to allow Incus traffic
echo ""
echo "Configuring UFW firewall for Incus..."
if command -v ufw &> /dev/null && sudo ufw status | grep -q "Status: active"; then
    echo "UFW is active, adding rules for Incus..."
    
    # Allow traffic on incusbr0 interface
    sudo ufw allow in on incusbr0
    sudo ufw route allow in on incusbr0
    sudo ufw route allow out on incusbr0
    
    # Allow forwarding
    sudo ufw default allow routed
    
    echo "✓ UFW configured for Incus"
fi

# Enable IP forwarding on host
echo "Enabling IP forwarding on host..."
sudo sysctl -w net.ipv4.ip_forward=1 > /dev/null
if ! grep -q "net.ipv4.ip_forward=1" /etc/sysctl.conf 2>/dev/null; then
    echo "net.ipv4.ip_forward=1" | sudo tee -a /etc/sysctl.conf > /dev/null
fi

# Configure network with IPv4
echo "Configuring network with IPv4..."
if sudo incus network list | grep -q incusbr0; then
    echo "Network incusbr0 exists, updating configuration..."
    # Update existing network
    sudo incus network set incusbr0 ipv4.address=10.0.100.1/24
    sudo incus network set incusbr0 ipv4.nat=true
    sudo incus network set incusbr0 ipv4.dhcp=true
    sudo incus network set incusbr0 ipv4.dhcp.ranges=10.0.100.2-10.0.100.254
    sudo incus network set incusbr0 ipv6.address=none
    sudo incus network set incusbr0 dns.mode=managed
    
    # Restart the network to apply changes
    echo "Restarting network to apply changes..."
    sudo systemctl restart incus || true
    sleep 3
else
    echo "Creating network bridge with IPv4 DHCP..."
    sudo incus network create incusbr0 \
        ipv4.address=10.0.100.1/24 \
        ipv4.nat=true \
        ipv4.dhcp=true \
        ipv4.dhcp.ranges=10.0.100.2-10.0.100.254 \
        ipv6.address=none \
        dns.mode=managed

    if [ $? -ne 0 ]; then
        echo "ERROR: Failed to create network!"
        exit 1
    fi
fi

# Verify and fix default profile
echo "Verifying default profile..."
if ! sudo incus profile show default | grep -q "path: /"; then
    echo "Adding root disk to default profile..."
    sudo incus profile device add default root disk path=/ pool=default 2>/dev/null || true
fi

# Update network device in profile
echo "Configuring network device in profile..."
sudo incus profile device remove default eth0 2>/dev/null || true
sudo incus profile device add default eth0 nic network=incusbr0 name=eth0

echo ""
echo "Current Incus configuration:"
echo "Storage pools:"
sudo incus storage list
echo ""
echo "Networks:"
sudo incus network list
echo ""
echo "Network detail:"
sudo incus network show incusbr0
echo ""
echo "Default profile:"
sudo incus profile show default

echo ""
echo "[1/4] Installing required tools..."
sudo apt update
sudo apt install -y jq git curl wget

# Create results directory
echo ""
echo "Creating results directory..."
mkdir -p ~/assessments/results

echo ""
echo "[2/4] Creating security-scanner base container..."
incus launch images:ubuntu/24.04 security-scanner

echo "Waiting for container to start and acquire IPv4 address via DHCP..."
sleep 25

# Verify container is running
if ! incus list | grep -q "security-scanner.*RUNNING"; then
    echo "ERROR: Container failed to start!"
    echo ""
    echo "Debug information:"
    echo "Container list:"
    incus list
    echo ""
    exit 1
fi

echo "✓ Container started successfully"

# Show container network info
echo ""
echo "Container network configuration:"
incus exec security-scanner -- ip addr show eth0

# Check if container got an IPv4 address
if ! incus exec security-scanner -- ip addr show eth0 | grep -q "inet "; then
    echo ""
    echo "WARNING: Container has no IPv4 address! Attempting manual DHCP..."
    incus exec security-scanner -- dhclient eth0
    sleep 5
    
    echo "After DHCP attempt:"
    incus exec security-scanner -- ip addr show eth0
fi

# Test internet connectivity
echo ""
echo "Testing container internet connectivity..."
if incus exec security-scanner -- ping -c 2 8.8.8.8 > /dev/null 2>&1; then
    echo "✓ Container has internet connectivity"
elif incus exec security-scanner -- ping -c 2 10.0.100.1 > /dev/null 2>&1; then
    echo "Container can reach gateway but not internet - checking NAT..."
    echo "iptables NAT table:"
    sudo iptables -t nat -L POSTROUTING -n -v
    echo ""
    echo "Manually adding NAT rule..."
    sudo iptables -t nat -A POSTROUTING -s 10.0.100.0/24 ! -d 10.0.100.0/24 -j MASQUERADE
    
    sleep 2
    if incus exec security-scanner -- ping -c 2 8.8.8.8 > /dev/null 2>&1; then
        echo "✓ NAT rule fixed connectivity"
    else
        echo "ERROR: Still no internet after NAT rule"
        exit 1
    fi
else
    echo "ERROR: Container cannot reach internet or gateway."
    echo ""
    echo "Full debugging output:"
    echo "Container IP:"
    incus exec security-scanner -- ip addr
    echo ""
    echo "Container routes:"
    incus exec security-scanner -- ip route
    echo ""
    echo "Can ping gateway?"
    incus exec security-scanner -- ping -c 2 10.0.100.1 || true
    echo ""
    exit 1
fi

echo ""
echo "[3/4] Installing security tools in container..."
incus exec security-scanner -- bash << 'CONTAINER_SETUP'
set -e

# Update system
export DEBIAN_FRONTEND=noninteractive
apt update && apt upgrade -y

# Install base utilities
apt install -y git curl wget jq python3 python3-pip python3-venv nodejs npm unzip

# Install additional scanners that don't need venv
npm install -g eslint
apt install -y cppcheck shellcheck

# Create virtual environment for Python security tools
echo "Creating Python virtual environment..."
python3 -m venv /opt/scanner-venv

# Activate venv and install Python security tools
echo "Installing Python security scanners in venv..."
/opt/scanner-venv/bin/pip install --upgrade pip
/opt/scanner-venv/bin/pip install semgrep bandit safety detect-secrets

# Install gitleaks
echo "Installing gitleaks..."
GITLEAKS_VERSION=$(curl -s https://api.github.com/repos/gitleaks/gitleaks/releases/latest | grep tag_name | cut -d '"' -f 4)
wget -q https://github.com/gitleaks/gitleaks/releases/download/${GITLEAKS_VERSION}/gitleaks_${GITLEAKS_VERSION:1}_linux_x64.tar.gz
tar -xzf gitleaks_${GITLEAKS_VERSION:1}_linux_x64.tar.gz
mv gitleaks /usr/local/bin/
rm gitleaks_${GITLEAKS_VERSION:1}_linux_x64.tar.gz

# Install CodeQL
echo "Installing CodeQL..."
CODEQL_VERSION=$(curl -s https://api.github.com/repos/github/codeql-cli-binaries/releases/latest | grep tag_name | cut -d '"' -f 4)
wget -q https://github.com/github/codeql-cli-binaries/releases/download/${CODEQL_VERSION}/codeql-linux64.zip
unzip -q codeql-linux64.zip -d /opt/
rm codeql-linux64.zip

# Download CodeQL standard library bundles
echo "Downloading CodeQL standard libraries..."
cd /opt/codeql
git clone --depth 1 https://github.com/github/codeql.git codeql-repo

# Create scanner directory
mkdir -p /opt/scanners

echo "Tool installation complete!"
CONTAINER_SETUP

if [ $? -ne 0 ]; then
    echo "ERROR: Container setup failed!"
    incus stop security-scanner
    incus delete security-scanner
    exit 1
fi

echo ""
echo "[4/4] Creating scan script in container..."
incus exec security-scanner -- bash << 'EOF'
cat > /opt/scanners/run-scans.sh << 'SCANSCRIPT'
#!/bin/bash
TARGET=$1
OUTPUT=${2:-/output}

mkdir -p $OUTPUT

# Activate Python venv for scanners
source /opt/scanner-venv/bin/activate
export PATH="/opt/codeql:$PATH"

echo "=== Running Security Scans on $TARGET ==="
echo "=== Saving results to $OUTPUT ==="
echo ""

echo "[+] Running semgrep..."
semgrep --config=p/security-audit --config=p/owasp-top-ten --no-git-ignore --quiet --json $TARGET > $OUTPUT/semgrep.json 2>&1 || echo '{"results":[]}' > $OUTPUT/semgrep.json
semgrep --config=p/security-audit --config=p/owasp-top-ten --no-git-ignore --quiet $TARGET > $OUTPUT/semgrep.txt 2>&1 || echo "No findings" > $OUTPUT/semgrep.txt
SEMGREP_COUNT=$(jq '.results | length' $OUTPUT/semgrep.json 2>/dev/null || echo "0")
echo "    Found $SEMGREP_COUNT findings - saved to semgrep.json, semgrep.txt"

echo ""
echo "[+] Running CodeQL..."
# Detect primary language
CODEQL_LANG=""
if find $TARGET -name "*.js" -o -name "*.ts" -o -name "*.jsx" -o -name "*.tsx" | head -1 | grep -q .; then
    CODEQL_LANG="javascript"
elif find $TARGET -name "*.java" | head -1 | grep -q .; then
    CODEQL_LANG="java"
elif find $TARGET -name "*.py" | head -1 | grep -q .; then
    CODEQL_LANG="python"
elif find $TARGET -name "*.go" | head -1 | grep -q .; then
    CODEQL_LANG="go"
elif find $TARGET -name "*.cpp" -o -name "*.c" -o -name "*.h" | head -1 | grep -q .; then
    CODEQL_LANG="cpp"
fi

CODEQL_COUNT=0
if [ -n "$CODEQL_LANG" ]; then
    echo "    Detected language: $CODEQL_LANG"
    
    # Create database without build (works for interpreted languages)
    if codeql database create /tmp/codeql-db \
        --language=$CODEQL_LANG \
        --source-root=$TARGET \
        --overwrite \
        --no-run-unnecessary-builds \
        2>&1 | grep -E "Finalizing|Successfully"; then
        
        # Run analysis
        if codeql database analyze /tmp/codeql-db \
            --format=sarif-latest \
            --output=$OUTPUT/codeql.sarif \
            --sarif-category=security \
            2>&1 | grep -E "Running|Interpreting results"; then
            
            CODEQL_COUNT=$(jq '[.runs[].results[]] | length' $OUTPUT/codeql.sarif 2>/dev/null || echo "0")
            echo "    Found $CODEQL_COUNT findings - saved to codeql.sarif"
        fi
        
        # Cleanup
        rm -rf /tmp/codeql-db
    else
        echo "    CodeQL database creation failed, skipping analysis"
    fi
else
    echo "    No supported languages detected, skipping CodeQL"
fi

echo ""
echo "[+] Running bandit (Python)..."
bandit -r $TARGET -f json -o $OUTPUT/bandit.json 2>/dev/null || echo '{"results":[]}' > $OUTPUT/bandit.json
bandit -r $TARGET -ll -o $OUTPUT/bandit.txt 2>/dev/null || echo "No Python files found" > $OUTPUT/bandit.txt
BANDIT_COUNT=$(jq '.results | length' $OUTPUT/bandit.json 2>/dev/null || echo "0")
echo "    Found $BANDIT_COUNT findings - saved to bandit.json, bandit.txt"

echo ""
echo "[+] Running gitleaks (secrets)..."
gitleaks detect --source $TARGET --no-git --report-path $OUTPUT/gitleaks.json --exit-code 0 2>/dev/null || echo '[]' > $OUTPUT/gitleaks.json
GITLEAKS_COUNT=$(jq '. | length' $OUTPUT/gitleaks.json 2>/dev/null || echo "0")
echo "    Found $GITLEAKS_COUNT secrets - saved to gitleaks.json"

echo ""
echo "[+] Running safety (Python dependencies)..."
find $TARGET -name "requirements.txt" -exec safety check --json -r {} \; > $OUTPUT/safety.json 2>/dev/null || echo "[]" > $OUTPUT/safety.json
echo "    Saved to safety.json"

echo ""
echo "[+] Generating summary..."
cat > $OUTPUT/summary.txt << SUMMARY
Security Scan Summary
=====================
Target: $TARGET
Date: $(date)
Scanner: security-scanner template

Files scanned: $(find $TARGET -type f | wc -l)

Findings by tool:
- CodeQL (Deep SAST):    $CODEQL_COUNT issues
- Semgrep (Fast SAST):   $SEMGREP_COUNT issues
- Gitleaks (Secrets):    $GITLEAKS_COUNT secrets
- Bandit (Python):       $BANDIT_COUNT issues

See individual report files for details:
- codeql.sarif - Deep dataflow analysis (GitHub-compatible)
- semgrep.json/txt - Code vulnerabilities
- gitleaks.json - Hardcoded secrets
- bandit.json/txt - Python-specific issues
- safety.json - Dependency vulnerabilities
SUMMARY

cat $OUTPUT/summary.txt

# Deactivate venv
deactivate

echo ""
echo "[+] Scan complete - all results saved to $OUTPUT"
SCANSCRIPT

chmod +x /opt/scanners/run-scans.sh
EOF

echo ""
echo "Stopping and publishing template container..."
incus stop security-scanner


echo ""
echo "Installing scan-repo command..."
sudo cp ./scan-repo /usr/local/bin/
sudo chmod +x /usr/local/bin/scan-repo

echo ""
echo "Installing generate-report command..."
sudo cp ./generate-report /usr/local/bin/
sudo chmod +x /usr/local/bin/generate-report

echo ""
echo "=================================="
echo "Setup Complete!"
echo "=================================="
echo ""
echo "Usage:"
echo "  scan-repo <github-url> [output-name]"
echo "  generate-report <scan-results-directory> [output-path/output.md]"
echo ""
echo "Example:"
echo "  scan-repo https://github.com/OWASP/NodeGoat"
echo "  scan-repo https://github.com/client/repo client-name"
echo ""
echo "Results will be saved to: ~/assessments/results/"
echo ""
