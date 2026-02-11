#!/bin/bash
# Debug CodeQL installation

echo "========================================="
echo "CodeQL Installation Debug"
echo "========================================="

echo ""
echo "1. CodeQL binary location:"
which codeql
ls -la /usr/local/bin/codeql

echo ""
echo "2. CodeQL version:"
codeql --version

echo ""
echo "3. CodeQL directory structure:"
ls -la /opt/codeql/

echo ""
echo "4. CodeQL queries repository:"
if [ -d "/opt/codeql/codeql-repo" ]; then
    echo "Queries repo exists"
    ls -la /opt/codeql/codeql-repo/
    echo ""
    echo "JavaScript queries:"
    ls -la /opt/codeql/codeql-repo/javascript/ql/src/codeql-suites/ 2>&1 || echo "Not found"
    echo ""
    echo "Python queries:"
    ls -la /opt/codeql/codeql-repo/python/ql/src/codeql-suites/ 2>&1 || echo "Not found"
else
    echo "ERROR: Queries repo NOT found at /opt/codeql/codeql-repo"
fi

echo ""
echo "5. Test CodeQL database creation (small test):"
cd /tmp
mkdir -p test-js
cat > test-js/test.js << 'EOF'
function test() {
    var x = 1;
    return x;
}
EOF

echo "Creating test database..."
codeql database create /tmp/test-db \
    --language=javascript \
    --source-root=/tmp/test-js \
    --no-build \
    --overwrite 2>&1

if [ -d "/tmp/test-db" ]; then
    echo "✓ Database created successfully"
    
    echo ""
    echo "6. Test query execution:"
    if [ -f "/opt/codeql/codeql-repo/javascript/ql/src/codeql-suites/javascript-security-and-quality.qls" ]; then
        echo "Running analysis..."
        codeql database analyze /tmp/test-db \
            /opt/codeql/codeql-repo/javascript/ql/src/codeql-suites/javascript-security-and-quality.qls \
            --format=sarif-latest \
            --output=/tmp/test-results.sarif 2>&1
        
        if [ -f "/tmp/test-results.sarif" ]; then
            echo "✓ Analysis completed"
            echo "Results:"
            cat /tmp/test-results.sarif | jq '.runs[0].results | length' 2>/dev/null || echo "No results"
        else
            echo "✗ Analysis failed - no output file"
        fi
    else
        echo "✗ Query suite not found"
    fi
else
    echo "✗ Database creation failed"
fi

echo ""
echo "========================================="
echo "Debug complete"
echo "========================================="
