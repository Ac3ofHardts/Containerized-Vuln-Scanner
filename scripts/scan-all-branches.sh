#!/bin/bash
set -euo pipefail

REPO_URL="${1:-}"
BASE_OUTPUT_NAME="${2:-scan-$(date +%Y%m%d-%H%M%S)}"

if [[ -z "$REPO_URL" ]]; then
    echo "Usage: scan-all-branches <repo-url> [base-output-name]"
    exit 1
fi

TEMP_CLONE_DIR="/tmp/clone-$$"
RESULTS_BASE="/scan/results/${BASE_OUTPUT_NAME}"

echo "========================================="
echo "Multi-Branch Security Scanner"
echo "Repository: $REPO_URL"
echo "Output: $BASE_OUTPUT_NAME"
echo "========================================="

# Clone repo to get branch list
echo "[*] Cloning repository to discover branches..."
git clone "$REPO_URL" "$TEMP_CLONE_DIR"
cd "$TEMP_CLONE_DIR"

# Get all remote branches
echo "[*] Discovering branches..."
BRANCHES=$(git branch -r | grep -v '\->' | sed 's/origin\///' | sed 's/^[ \t]*//')
BRANCH_COUNT=$(echo "$BRANCHES" | wc -l)

echo "[*] Found $BRANCH_COUNT branches to scan"
echo ""

# Clean up temp clone and return to safe directory
cd /scan
rm -rf "$TEMP_CLONE_DIR"

# Detect language function
detect_language() {
    if find . -name "*.py" -type f | head -1 | grep -q .; then
        echo "python"
    elif find . -name "*.js" -o -name "*.ts" -type f | head -1 | grep -q .; then
        echo "javascript"
    elif find . -name "*.java" -type f | head -1 | grep -q .; then
        echo "java"
    elif find . -name "*.go" -type f | head -1 | grep -q .; then
        echo "go"
    elif find . -name "*.c" -o -name "*.cpp" -o -name "*.h" -type f | head -1 | grep -q .; then
        echo "cpp"
    elif find . -name "*.cs" -type f | head -1 | grep -q .; then
        echo "csharp"
    elif find . -name "*.rb" -type f | head -1 | grep -q .; then
        echo "ruby"
    else
        echo "unknown"
    fi
}

# Get query suite
get_query_suite() {
    local lang=$1
    case $lang in
        python)
            echo "/opt/codeql/codeql-repo/python/ql/src/codeql-suites/python-security-and-quality.qls"
            ;;
        javascript)
            echo "/opt/codeql/codeql-repo/javascript/ql/src/codeql-suites/javascript-security-and-quality.qls"
            ;;
        java)
            echo "/opt/codeql/codeql-repo/java/ql/src/codeql-suites/java-security-and-quality.qls"
            ;;
        go)
            echo "/opt/codeql/codeql-repo/go/ql/src/codeql-suites/go-security-and-quality.qls"
            ;;
        cpp)
            echo "/opt/codeql/codeql-repo/cpp/ql/src/codeql-suites/cpp-security-and-quality.qls"
            ;;
        csharp)
            echo "/opt/codeql/codeql-repo/csharp/ql/src/codeql-suites/csharp-security-and-quality.qls"
            ;;
        ruby)
            echo "/opt/codeql/codeql-repo/ruby/ql/src/codeql-suites/ruby-security-and-quality.qls"
            ;;
        *)
            echo ""
            ;;
    esac
}

# Scan each branch
SCAN_COUNT=0
for BRANCH in $BRANCHES; do
    SCAN_COUNT=$((SCAN_COUNT + 1))
    
    echo ""
    echo "========================================="
    echo "[$SCAN_COUNT/$BRANCH_COUNT] Scanning branch: $BRANCH"
    echo "========================================="
    
    BRANCH_NAME=$(echo "$BRANCH" | sed 's/\//-/g')
    BRANCH_DIR="${RESULTS_BASE}/${BRANCH_NAME}"
    REPO_DIR="/scan/repo-${SCAN_COUNT}"
    
    # Ensure we're in a safe directory before operations
    cd /scan
    
    # Clean up any existing repo directory
    rm -rf "$REPO_DIR"
    
    # Create branch results directory
    mkdir -p "$BRANCH_DIR"
    
    # Clone specific branch
    echo "[*] Cloning branch: $BRANCH..."
    if git clone --depth 1 --branch "$BRANCH" "$REPO_URL" "$REPO_DIR" 2>&1 | tee "$BRANCH_DIR/clone.log"; then
        # Change to repo directory
        cd "$REPO_DIR"
        
        LANG=$(detect_language)
        echo "[*] Detected language: $LANG"
        
        # Run Semgrep
        echo "[*] Running Semgrep..."
        semgrep --config=auto \
            --config=p/security-audit \
            --config=p/owasp-top-ten \
            --json \
            --output="$BRANCH_DIR/semgrep.json" \
            . 2>&1 | tee "$BRANCH_DIR/semgrep.log" || true
        
        semgrep --config=auto \
            --config=p/security-audit \
            --config=p/owasp-top-ten \
            --output="$BRANCH_DIR/semgrep.txt" \
            . 2>&1 || true
        
        # Run Gitleaks
        echo "[*] Running Gitleaks..."
        gitleaks detect \
            --source=. \
            --report-format=json \
            --report-path="$BRANCH_DIR/gitleaks.json" \
            --no-git 2>&1 | tee "$BRANCH_DIR/gitleaks.log" || true
        
        # Run Bandit (Python)
        if find . -name "*.py" -type f | head -1 | grep -q .; then
            echo "[*] Running Bandit..."
            bandit -r . -f json -o "$BRANCH_DIR/bandit.json" 2>&1 | tee "$BRANCH_DIR/bandit.log" || true
        fi
        
        # Run Safety (Python)
        if [ -f "requirements.txt" ]; then
            echo "[*] Running Safety..."
            safety check --file=requirements.txt --json --output="$BRANCH_DIR/safety.json" 2>&1 | tee "$BRANCH_DIR/safety.log" || true
        fi
        
        # Run CodeQL - ALWAYS (auto-detects build requirements)
        if [ "$LANG" != "unknown" ]; then
            QUERY_SUITE=$(get_query_suite "$LANG")
            
            if [ -n "$QUERY_SUITE" ]; then
                echo "[*] Running CodeQL for $LANG (may take 10-30 minutes)..."
                
                if codeql database create /tmp/codeql-db-${SCAN_COUNT} \
                    --language="$LANG" \
                    --source-root=. \
                    --overwrite 2>&1 | tee "$BRANCH_DIR/codeql-db.log"; then
                    
                    echo "[*] Analyzing CodeQL database..."
                    
                    codeql database analyze /tmp/codeql-db-${SCAN_COUNT} \
                        "$QUERY_SUITE" \
                        --format=sarif-latest \
                        --output="$BRANCH_DIR/codeql.sarif" \
                        2>&1 | tee "$BRANCH_DIR/codeql-analyze.log" || true
                    
                    codeql database analyze /tmp/codeql-db-${SCAN_COUNT} \
                        "$QUERY_SUITE" \
                        --format=csv \
                        --output="$BRANCH_DIR/codeql.csv" \
                        2>&1 || true
                    
                    rm -rf /tmp/codeql-db-${SCAN_COUNT}
                    echo "[✓] CodeQL complete"
                else
                    echo "[!] CodeQL failed"
                fi
            fi
        fi
        
        # Generate branch summary
        {
            echo "Branch: $BRANCH"
            echo "Scanned: $(date)"
            echo "Language: $LANG"
            echo ""
            echo "=== Semgrep ==="
            if [ -f "$BRANCH_DIR/semgrep.json" ]; then
                jq -r '.results | group_by(.extra.severity) | .[] | "\(.[0].extra.severity): \(length)"' \
                    "$BRANCH_DIR/semgrep.json" 2>/dev/null || echo "No results"
            else
                echo "No results"
            fi
            echo ""
            echo "=== Gitleaks ==="
            if [ -f "$BRANCH_DIR/gitleaks.json" ]; then
                echo "Secrets: $(jq -r 'length' "$BRANCH_DIR/gitleaks.json" 2>/dev/null || echo 0)"
            else
                echo "No secrets"
            fi
            echo ""
            echo "=== CodeQL ==="
            if [ -f "$BRANCH_DIR/codeql.sarif" ]; then
                echo "Findings: $(jq -r '.runs[0].results | length' "$BRANCH_DIR/codeql.sarif" 2>/dev/null || echo 0)"
            else
                echo "No results"
            fi
        } > "$BRANCH_DIR/summary.txt"
        
        cat "$BRANCH_DIR/summary.txt"
        
        # Return to safe directory before cleanup
        cd /scan
        rm -rf "$REPO_DIR"
        
        echo "[✓] Branch $BRANCH complete"
    else
        echo "[!] Failed to clone branch $BRANCH"
        # Ensure we're back in a safe directory
        cd /scan
    fi
done

# Generate master summary (ensure we're in safe directory)
cd /scan

{
    echo "========================================="
    echo "Multi-Branch Scan Report"
    echo "========================================="
    echo "Repository: $REPO_URL"
    echo "Scanned: $(date)"
    echo "Branches: $SCAN_COUNT"
    echo ""
    
    for BRANCH in $BRANCHES; do
        BRANCH_NAME=$(echo "$BRANCH" | sed 's/\//-/g')
        BRANCH_DIR="${RESULTS_BASE}/${BRANCH_NAME}"
        
        if [ -f "$BRANCH_DIR/summary.txt" ]; then
            echo "========================================="
            cat "$BRANCH_DIR/summary.txt"
            echo ""
        fi
    done
} > "${RESULTS_BASE}/MASTER_SUMMARY.txt"

echo ""
echo "========================================="
echo "All Branches Scanned!"
echo "========================================="
cat "${RESULTS_BASE}/MASTER_SUMMARY.txt"
echo ""
echo "Results: ${RESULTS_BASE}/"
