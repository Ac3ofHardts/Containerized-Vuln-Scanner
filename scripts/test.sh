#!/bin/bash
# Run integration tests
set -e

echo "Testing setup..."
./scripts/setup.sh

echo "Testing scan on known-vulnerable app..."
scan-repo https://github.com/OWASP/NodeGoat test-scan

echo "Testing report generation..."
generate-report ~/assessments/results/NodeGoat-*/

echo "All tests passed!"