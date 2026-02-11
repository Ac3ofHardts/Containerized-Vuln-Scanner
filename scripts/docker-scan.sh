#!/bin/bash
set -euo pipefail

REPO_URL="${1:-}"
OUTPUT_NAME="${2:-scan-$(date +%Y%m%d-%H%M%S)}"
REPO_DIR="/scan/repo"
RESULTS_DIR="/scan/results/${OUTPUT_NAME}"

if [[ -z "$REPO_URL" ]]; then
    echo "Usage: scan <repo-url> [output-name]"
    exit 1
fi

# Create results directory
mkdir -p "$RESULTS_DIR"

echo "[*] Cloning repository (shallow)..."
rm -rf "$REPO_DIR"
git clone --depth 1 "$REPO_URL" "$REPO_DIR"

cd "$REPO_DIR"

# Detect primary language for CodeQL
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

# Get query pack for language (using built-in packs from bundle)
get_query_pack() {
    local lang=$1
    case $lang in
        python)
            echo "codeql/python-queries:codeql-suites/python-security-and-quality.qls"
            ;;
        javascript)
            echo "codeql/javascript-queries:codeql-suites/javascript-security-and-quality.qls"
            ;;
        java)
            echo "codeql/java-queries:codeql-suites/java-security-and-quality.qls"
            ;;
        go)
            echo "codeql/go-queries:codeql-suites/go-security-and-quality.qls"
            ;;
        cpp)
            echo "codeql/cpp-queries:codeql-suites/cpp-security-and-quality.qls"
            ;;
        csharp)
            echo "codeql/csharp-queries:codeql-suites/csharp-security-and-quality.qls"
            ;;
        ruby)
            echo "codeql/ruby-queries:codeql-suites/ruby-security-and-quality.qls"
            ;;
        *)
            echo ""
            ;;
    esac
}

echo "[*] Running Semgrep..."
semgrep --config=auto \
    --config=p/security-audit \
    --config=p/owasp-top-ten \
    --json \
    --output="${RESULTS_DIR}/semgrep.json" \
    . 2>&1 | tee "${RESULTS_DIR}/semgrep.log" || true

semgrep --config=auto \
    --config=p/security-audit \
    --config=p/owasp-top-ten \
    --output="${RESULTS_DIR}/semgrep.txt" \
    . 2>&1 || true

echo "[*] Running Gitleaks..."
gitleaks detect \
    --source=. \
    --report-format=json \
    --report-path="${RESULTS_DIR}/gitleaks.json" \
    --no-git 2>&1 | tee "${RESULTS_DIR}/gitleaks.log" || true

echo "[*] Running Bandit (Python)..."
if find . -name "*.py" -type f | head -1 | grep -q .; then
    bandit -r . \
        -f json \
        -o "${RESULTS_DIR}/bandit.json" 2>&1 | tee "${RESULTS_DIR}/bandit.log" || true
else
    echo "No Python files found, skipping Bandit"
fi

echo "[*] Running Safety (Python)..."
if [ -f "requirements.txt" ]; then
    safety check \
        --file=requirements.txt \
        --json \
        --output="${RESULTS_DIR}/safety.json" 2>&1 | tee "${RESULTS_DIR}/safety.log" || true
else
    echo "No requirements.txt found, skipping Safety"
fi

# CodeQL - ALWAYS RUNS
echo "[*] Detecting language for CodeQL..."
LANG=$(detect_language)

if [ "$LANG" != "unknown" ]; then
    QUERY_PACK=$(get_query_pack "$LANG")
    
    if [ -z "$QUERY_PACK" ]; then
        echo "[!] No query pack found for $LANG"
    else
        echo "[*] Running CodeQL for $LANG (this may take 10-30 minutes)..."
        echo "[*] Using query pack: $QUERY_PACK"
        
        # Create database
        if codeql database create /tmp/codeql-db \
            --language="$LANG" \
            --source-root=. \
            --overwrite 2>&1 | tee "${RESULTS_DIR}/codeql-db.log"; then
            
            echo "[*] CodeQL database created, analyzing..."
            
            # Analyze with query pack
            codeql database analyze /tmp/codeql-db \
                "$QUERY_PACK" \
                --format=sarif-latest \
                --output="${RESULTS_DIR}/codeql.sarif" \
                --sarif-add-baseline-file-info \
                2>&1 | tee "${RESULTS_DIR}/codeql-analyze.log" || true
            
            # Also generate CSV for readability
            codeql database analyze /tmp/codeql-db \
                "$QUERY_PACK" \
                --format=csv \
                --output="${RESULTS_DIR}/codeql.csv" \
                2>&1 || true
                
            rm -rf /tmp/codeql-db
            echo "[✓] CodeQL scan complete"
        else
            echo "[!] CodeQL database creation failed, check codeql-db.log"
        fi
    fi
else
    echo "[!] No supported language detected for CodeQL (Python, JavaScript, Java, Go, C/C++, C#, Ruby)"
    echo "Skipping CodeQL scan"
fi

# Generate summary
{
    echo "========================================="
    echo "Security Scan Summary"
    echo "========================================="
    echo "Scan completed: $(date)"
    echo "Repository: $REPO_URL"
    echo ""
    echo "Results location: $RESULTS_DIR"
    echo ""
    echo "========================================="
    echo "Semgrep Summary"
    echo "========================================="
    if [ -f "${RESULTS_DIR}/semgrep.json" ]; then
        jq -r '.results | group_by(.extra.severity) | .[] | "\(.[0].extra.severity): \(length)"' \
            "${RESULTS_DIR}/semgrep.json" 2>/dev/null || echo "No Semgrep results"
    else
        echo "Semgrep did not produce results"
    fi
    
    echo ""
    echo "========================================="
    echo "Gitleaks Summary"
    echo "========================================="
    if [ -f "${RESULTS_DIR}/gitleaks.json" ]; then
        SECRET_COUNT=$(jq -r 'length' "${RESULTS_DIR}/gitleaks.json" 2>/dev/null || echo "0")
        echo "Secrets found: $SECRET_COUNT"
    else
        echo "No secrets found"
    fi
    
    echo ""
    echo "========================================="
    echo "Bandit Summary"
    echo "========================================="
    if [ -f "${RESULTS_DIR}/bandit.json" ]; then
        jq -r '.metrics._totals | "High: \(.SEVERITY.HIGH // 0), Medium: \(.SEVERITY.MEDIUM // 0), Low: \(.SEVERITY.LOW // 0)"' \
            "${RESULTS_DIR}/bandit.json" 2>/dev/null || echo "No Python issues"
    else
        echo "No Python files scanned"
    fi
    
    echo ""
    echo "========================================="
    echo "CodeQL Summary"
    echo "========================================="
    if [ -f "${RESULTS_DIR}/codeql.sarif" ]; then
        CODEQL_COUNT=$(jq -r '.runs[0].results | length' "${RESULTS_DIR}/codeql.sarif" 2>/dev/null || echo "0")
        echo "CodeQL findings: $CODEQL_COUNT"
        if [ "$CODEQL_COUNT" -gt 0 ]; then
            echo ""
            echo "Severity breakdown:"
            jq -r '.runs[0].results[] | .level' "${RESULTS_DIR}/codeql.sarif" 2>/dev/null | sort | uniq -c || true
        fi
    else
        echo "CodeQL did not produce results"
    fi
    
} > "${RESULTS_DIR}/summary.txt"

cat "${RESULTS_DIR}/summary.txt"
echo ""
echo "[✓] Scan complete. Results in: $RESULTS_DIR"

# Cleanup
rm -rf "$REPO_DIR"
