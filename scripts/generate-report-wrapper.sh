#!/bin/bash
# Wrapper for generating security reports

if [ "$#" -lt 1 ]; then
    echo "Usage: ./scripts/generate-report-wrapper.sh <results-directory>"
    echo ""
    echo "Examples:"
    echo "  ./scripts/generate-report-wrapper.sh ./results/scan-20260206-143022"
    echo "  ./scripts/generate-report-wrapper.sh ./results/scan-latest"
    echo ""
    echo "Or use 'latest' to automatically find most recent scan:"
    echo "  ./scripts/generate-report-wrapper.sh latest"
    exit 1
fi

RESULTS_DIR="$1"

# If "latest" is specified, find the most recent results directory
if [ "$RESULTS_DIR" = "latest" ]; then
    RESULTS_DIR=$(ls -dt results/scan-* 2>/dev/null | head -1)
    
    if [ -z "$RESULTS_DIR" ]; then
        echo "Error: No scan results found in ./results/"
        exit 1
    fi
    
    echo "[*] Using latest results: $RESULTS_DIR"
fi

# Verify directory exists
if [ ! -d "$RESULTS_DIR" ]; then
    echo "Error: Directory not found: $RESULTS_DIR"
    exit 1
fi

echo "========================================="
echo "Security Report Generator"
echo "========================================="
echo "Results: $RESULTS_DIR"
echo ""

# Run report generator in Docker
docker-compose run --rm vuln-scanner generate-report "/scan/results/$(basename "$RESULTS_DIR")"

# Check if report was generated
REPORT_FILE="$RESULTS_DIR/SECURITY_REPORT.md"
if [ -f "$REPORT_FILE" ]; then
    echo ""
    echo "========================================="
    echo "Report Generated Successfully!"
    echo "========================================="
    echo "Location: $REPORT_FILE"
    echo ""
    echo "View report:"
    echo "  cat $REPORT_FILE"
    echo "  less $REPORT_FILE"
    echo ""
    echo "Quick preview:"
    echo "----------------------------------------"
    head -30 "$REPORT_FILE"
    echo "----------------------------------------"
    echo ""
    echo "Full report: $REPORT_FILE"
else
    echo ""
    echo "[!] Report generation failed"
    exit 1
fi
