#!/bin/bash

echo "=================================="
echo "Containerized Vulnerability Scanner Setup"
echo "=================================="
echo ""

# Check if Incus is installed
if ! command -v incus &> /dev/null; then
    echo "ERROR: Incus is not installed"
    echo "Please install Incus first: https://linuxcontainers.org/incus/docs/main/installing/"
    exit 1
fi

echo "[1/4] Installing required tools..."
sudo apt update
sudo apt install -y jq git curl wget

echo ""
echo "[2/4] Creating security-scanner base container..."
incus launch images:ubuntu/24.04 security-scanner

echo "Waiting for container to start..."
sleep 5

echo ""
echo "[3/4] Installing security tools in container..."
incus exec security-scanner -- bash << 'CONTAINER_SETUP'
# Update system
apt update && apt upgrade -y

# Install base utilities
apt install -y git curl wget jq python3 python3-pip nodejs npm

# Install security scanning tools
pip3 install semgrep bandit safety detect-secrets appthreat-depscan

# Install additional scanners
npm install -g eslint
apt install -y cppcheck shellcheck

# Install gitleaks
GITLEAKS_VERSION=$(curl -s https://api.github.com/repos/gitleaks/gitleaks/releases/latest | grep tag_name | cut -d '"' -f 4)
wget -q https://github.com/gitleaks/gitleaks/releases/download/${GITLEAKS_VERSION}/gitleaks_${GITLEAKS_VERSION:1}_linux_x64.tar.gz
tar -xzf gitleaks_${GITLEAKS_VERSION:1}_linux_x64.tar.gz
mv gitleaks /usr/local/bin/
rm gitleaks_${GITLEAKS_VERSION:1}_linux_x64.tar.gz

# Create scanner directory
mkdir -p /opt/scanners
CONTAINER_SETUP

echo ""
echo "[4/4] Creating scan script in container..."
incus exec security-scanner -- bash << 'EOF'
cat > /opt/scanners/run-scans.sh << 'SCANSCRIPT'
#!/bin/bash
TARGET=$1
OUTPUT=${2:-/output}

mkdir -p $OUTPUT

echo "=== Running Security Scans on $TARGET ==="
echo "=== Saving results to $OUTPUT ==="
echo ""

echo "[+] Running semgrep..."
semgrep --config=p/security-audit --config=p/owasp-top-ten --no-git-ignore --quiet --json $TARGET > $OUTPUT/semgrep.json 2>&1
semgrep --config=p/security-audit --config=p/owasp-top-ten --no-git-ignore --quiet $TARGET > $OUTPUT/semgrep.txt 2>&1
SEMGREP_COUNT=$(jq '.results | length' $OUTPUT/semgrep.json 2>/dev/null || echo "0")
echo "    Found $SEMGREP_COUNT findings - saved to semgrep.json, semgrep.txt"

echo ""
echo "[+] Running bandit (Python)..."
bandit -r $TARGET -f json -o $OUTPUT/bandit.json 2>/dev/null || echo '{"results":[]}' > $OUTPUT/bandit.json
bandit -r $TARGET -ll -o $OUTPUT/bandit.txt 2>/dev/null || echo "No Python files found" > $OUTPUT/bandit.txt
BANDIT_COUNT=$(jq '.results | length' $OUTPUT/bandit.json 2>/dev/null || echo "0")
echo "    Found $BANDIT_COUNT findings - saved to bandit.json, bandit.txt"

echo ""
echo "[+] Running gitleaks (secrets)..."
gitleaks detect --source $TARGET --no-git --report-path $OUTPUT/gitleaks.json --exit-code 0 2>/dev/null
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
- Semgrep (SAST):        $SEMGREP_COUNT issues
- Gitleaks (Secrets):    $GITLEAKS_COUNT secrets
- Bandit (Python):       $BANDIT_COUNT issues

See individual report files for details:
- semgrep.json/txt - Code vulnerabilities
- gitleaks.json - Hardcoded secrets
- bandit.json/txt - Python-specific issues
- safety.json - Dependency vulnerabilities
SUMMARY

cat $OUTPUT/summary.txt
echo ""
echo "[+] Scan complete - all results saved to $OUTPUT"
SCANSCRIPT

chmod +x /opt/scanners/run-scans.sh
EOF

echo ""
echo "Stopping template container..."
incus stop security-scanner

echo ""
echo "Installing scan-repo command..."
sudo cp scripts/scan-repo /usr/local/bin/
sudo chmod +x /usr/local/bin/scan-repo

echo ""
echo "=================================="
echo "Setup Complete!"
echo "=================================="
echo ""
echo "Usage:"
echo "  scan-repo <github-url> [output-name]"
echo ""
echo "Example:"
echo "  scan-repo https://github.com/OWASP/NodeGoat"
echo "  scan-repo https://github.com/client/repo client-name"
echo ""
echo "Results will be saved to: ~/assessments/results/"
echo ""