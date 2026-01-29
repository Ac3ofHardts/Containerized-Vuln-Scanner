#!/bin/bash
# Containreized Vulnerability Scanner
# Copyright (C) 2026 Evan Hardt
#
# This program is licensed under AGPL v3 for open-source use.
# Commercial licenses available - contact: evan@texashardts.com
#
# For the full license, see LICENSE file in the root directory.

# Run integration tests
set -e

echo "Testing setup..."
./scripts/setup.sh

echo "Testing scan on known-vulnerable app..."
scan-repo https://github.com/OWASP/NodeGoat test-scan

echo "Testing report generation..."
generate-report ~/assessments/results/NodeGoat-*/

echo "All tests passed!"