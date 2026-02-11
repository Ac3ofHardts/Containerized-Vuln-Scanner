#!/bin/bash
# Simple wrapper to scan all branches with CodeQL
# Usage: ./scripts/docker-scan-wrapper.sh <repo-url>

REPO_URL="${1:-}"

if [[ -z "$REPO_URL" ]]; then
    echo "Usage: docker-scan-wrapper.sh <repo-url>"
    echo ""
    echo "Examples:"
    echo "  ./scripts/docker-scan-wrapper.sh https://github.com/OWASP/NodeGoat"
    echo "  ./scripts/docker-scan-wrapper.sh https://github.com/org/repo"
    echo ""
    echo "This will scan ALL branches with full CodeQL analysis."
    exit 1
fi

# Ensure we're in the repo root
cd "$(dirname "$0")/.."

# Create results directory if it doesn't exist
mkdir -p results

# Generate output name with timestamp
OUTPUT_NAME="scan-$(date +%Y%m%d-%H%M%S)"

echo "========================================="
echo "Containerized Vulnerability Scanner"
echo "========================================="
echo "Repository: $REPO_URL"
echo "Output: $OUTPUT_NAME"
echo ""
echo "Starting comprehensive scan..."
echo "This will scan ALL branches with:"
echo "  - Semgrep (SAST)"
echo "  - CodeQL (Deep Analysis)"
echo "  - Gitleaks (Secrets)"
echo "  - Bandit (Python)"
echo "  - Safety (Python Dependencies)"
echo ""
echo "========================================="
echo ""

# Run the all-branches scanner
docker-compose run --rm vuln-scanner scan-all-branches "$REPO_URL" "$OUTPUT_NAME"

echo ""
echo "========================================="
echo "Scan Complete!"
echo "========================================="
echo "Results location: ./results/$OUTPUT_NAME/"
echo ""
echo "Quick summary:"
cat "results/$OUTPUT_NAME/MASTER_SUMMARY.txt"
echo ""
echo "========================================="
