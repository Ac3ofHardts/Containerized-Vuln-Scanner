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
export PATH="/opt/codeql:$PATH"

echo "=== Running Security Scans on $TARGET ==="
echo "=== Saving results to $OUTPUT ==="
echo ""

echo "[+] Running semgrep..."
semgrep --config=p/security-audit --config=p/owasp-top-ten --no-git-ignore --quiet --json $TARGET > $OUTPUT/semgrep.json 2>&1
semgrep --config=p/security-audit --config=p/owasp-top-ten --no-git-ignore --quiet $TARGET > $OUTPUT/semgrep.txt 2>&1
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

if [ -n "$CODEQL_LANG" ]; then
    echo "    Detected language: $CODEQL_LANG"
    
    # Create database without build (works for interpreted languages)
    codeql database create /tmp/codeql-db \
        --language=$CODEQL_LANG \
        --source-root=$TARGET \
        --overwrite \
        --no-run-unnecessary-builds \
        2>&1 | grep -E "Finalizing|Successfully" || true
    
    if [ -d /tmp/codeql-db ]; then
        # Run analysis
        codeql database analyze /tmp/codeql-db \
            --format=sarif-latest \
            --output=$OUTPUT/codeql.sarif \
            --sarif-category=security \
            -- \
            2>&1 | grep -E "Running|Interpreting results" || true
        
        if [ -f $OUTPUT/codeql.sarif ]; then
            CODEQL_COUNT=$(jq '[.runs[].results[]] | length' $OUTPUT/codeql.sarif 2>/dev/null || echo "0")
            echo "    Found $CODEQL_COUNT findings - saved to codeql.sarif"
        else
            echo "    CodeQL analysis completed but no results generated"
            CODEQL_COUNT=0
        fi
        
        # Cleanup
        rm -rf /tmp/codeql-db
    else
        echo "    CodeQL database creation failed, skipping analysis"
        CODEQL_COUNT=0
    fi
else
    echo "    No supported languages detected, skipping CodeQL"
    CODEQL_COUNT=0
fi

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
echo "Installing generate-report command..."
sudo cp scripts/generate-report /usr/local/bin/
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