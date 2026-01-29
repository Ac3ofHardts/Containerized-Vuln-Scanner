# Containerized Vulnerability Scanner

[![License: AGPL v3](https://img.shields.io/badge/License-AGPL%20v3-blue.svg)](https://www.gnu.org/licenses/agpl-3.0)
[![Commercial License Available](https://img.shields.io/badge/Commercial%20License-Available-green.svg)](LICENSE-COMMERCIAL.template)
[![Version](https://img.shields.io/badge/version-1.0.0-blue.svg)](https://github.com/Ac3ofHardts/Containerized-Vuln-Scanner/releases)
[![Platform](https://img.shields.io/badge/platform-Linux-lightgrey.svg)](https://github.com/Ac3ofHardts/Containerized-Vuln-Scanner)

A lightweight, containerized security scanning solution for static code analysis and vulnerability assessment. Built with Incus for isolation, portability, and minimal storage overhead.

## Features

- 🔍 **Multi-language SAST** - Semgrep with security-audit and OWASP Top 10 rulesets
- 🔬 **Deep Analysis** - CodeQL for complex dataflow vulnerabilities
- 🔐 **Secret Detection** - Gitleaks for hardcoded credentials and API keys
- 🐍 **Python Security** - Bandit for Python-specific vulnerabilities
- 📊 **Automated Reports** - Professional Markdown reports from all scan results
- 🔒 **Isolated Execution** - Each scan runs in a fresh, isolated container
- 💾 **Minimal Storage** - Shallow clones and automatic cleanup
- 🎯 **Easy Workflow** - One command to scan any repository

## Supported Languages

JavaScript/TypeScript, Python, Java, Go, C/C++, Ruby, PHP, C#, and [many more via Semgrep](https://semgrep.dev/docs/supported-languages/)

## Prerequisites

- Ubuntu/Debian-based Linux (tested on Ubuntu 22.04, Pop!_OS 22.04)
- [Incus](https://linuxcontainers.org/incus/docs/main/installing/) installed and initialized
- 50GB available disk space
- 4GB+ RAM recommended

## Installation
```bash
# Clone the repository
git clone https://github.com/Ac3ofHardts/Containerized-Vuln-Scanner.git
cd Containerized-Vuln-Scanner

# Run setup (installs tools and creates template container)
./scripts/setup.sh
```

The setup script will:
1. Install required dependencies (jq, git, curl, wget)
2. Create the `security-scanner` base container
3. Install all security tools (Semgrep, CodeQL, Gitleaks, Bandit, Safety)
4. Install the `scan-repo` and `generate-report` commands

## Quick Start

### Basic Scan
```bash
scan-repo https://github.com/OWASP/NodeGoat
```

This will:
1. Clone the repository (shallow clone)
2. Spin up an isolated scan container
3. Run all security tools
4. Generate results in `~/assessments/results/NodeGoat-TIMESTAMP/`
5. Clean up everything except the results

### Named Output (for Client Work)
```bash
scan-repo https://github.com/client/project client-acme
```

Results saved to: `~/assessments/results/client-acme-TIMESTAMP/`

### Generate Professional Report
```bash
generate-report ~/assessments/results/NodeGoat-20260129-123456/
```

Creates `SECURITY_REPORT.md` with:
- Executive summary with severity breakdown
- Detailed findings from all tools
- Recommendations prioritized by severity
- CWE and OWASP mappings

## Usage Examples

### Scan Different Languages
```bash
# JavaScript/TypeScript project
scan-repo https://github.com/expressjs/express

# Python project  
scan-repo https://github.com/django/django

# Java project
scan-repo https://github.com/spring-projects/spring-boot

# Go project
scan-repo https://github.com/golang/go
```

### View Results
```bash
# Quick summary
cat ~/assessments/results/NodeGoat-*/summary.txt

# Detailed Semgrep findings
jq '.results[] | {severity, path, line: .start.line, message}' \
  ~/assessments/results/NodeGoat-*/semgrep.json | less

# Secrets found
jq '.[] | {Description, File, StartLine}' \
  ~/assessments/results/NodeGoat-*/gitleaks.json

# Generate full report
generate-report ~/assessments/results/NodeGoat-*/
```

## Output Files

Each scan produces:

| File | Description | Format |
|------|-------------|--------|
| `summary.txt` | High-level overview | Plain text |
| `semgrep.json` | Code vulnerabilities (machine-readable) | JSON |
| `semgrep.txt` | Code vulnerabilities (human-readable) | Plain text |
| `codeql.sarif` | Deep dataflow analysis | SARIF |
| `gitleaks.json` | Hardcoded secrets | JSON |
| `bandit.json` | Python-specific issues | JSON |
| `safety.json` | Python dependency vulnerabilities | JSON |
| `SECURITY_REPORT.md` | Comprehensive report (after running generate-report) | Markdown |

## Use Cases

### 🎓 Educational
- Teaching secure coding practices
- Creating vulnerable code examples
- Security workshop materials

### 💼 Security Assessments
- Client code reviews
- Pre-deployment security checks
- Continuous security validation

### 🔄 CI/CD Integration
- Automated security scanning in pipelines
- Pull request security checks
- Release validation

## How It Works
```
┌─────────────────────────────────────────────────────┐
│  Host System                                        │
│  ┌──────────────────────────────────────────────┐   │
│  │  security-scanner (template container)       │   │
│  │  • Semgrep                                   │   │
│  │  • CodeQL                                    │   │
│  │  • Gitleaks                                  │   │
│  │  • Bandit                                    │   │
│  │  • Safety                                    │   │
│  └──────────────────────────────────────────────┘   │
│                                                     │
│  scan-repo command:                                 │
│  1. Clone repo (shallow) ──────────────────┐        │
│  2. Copy template → scan-instance          │        │
│  3. Mount code (read-only) ────────────────┼──────┐ │
│  4. Mount output directory ────────────────┼──────┤ │
│  5. Run scans ─────────────────────────────┘      │ │
│  6. Cleanup container                             │ │
│  7. Delete cloned repo                            │ │
│                                                   │ │
│  Results: ~/assessments/results/ ◄────────────────┘ │
└─────────────────────────────────────────────────────┘
```

## Tools Included

| Tool | Purpose | Languages |
|------|---------|-----------|
| [Semgrep](https://semgrep.dev/) | Fast SAST with low false positives | 30+ languages |
| [CodeQL](https://codeql.github.com/) | Deep dataflow analysis | JavaScript, Python, Java, Go, C/C++, C#, Ruby |
| [Gitleaks](https://github.com/gitleaks/gitleaks) | Secret detection | All (text files) |
| [Bandit](https://bandit.readthedocs.io/) | Python security linting | Python |
| [Safety](https://pyup.io/safety/) | Python dependency scanning | Python |

## Advanced Usage

### Custom Semgrep Rules
```bash
# Add custom rules to the container
incus exec security-scanner -- bash
mkdir -p /opt/custom-rules
# Add your .yaml rules here
exit

# Update scan script to use custom rules
# (see docs/customization.md)
```

### Skip CodeQL for Faster Scans

CodeQL is thorough but slow. For quick assessments, you can modify the scan script to skip it or run Semgrep-only scans.

### Batch Scanning
```bash
# Scan multiple repos
for repo in repo1 repo2 repo3; do
  scan-repo https://github.com/org/$repo
done

# Generate combined report
# (custom script needed)
```

## Troubleshooting

### "Incus not installed"
Install Incus following the [official guide](https://linuxcontainers.org/incus/docs/main/installing/)

### "Permission denied" errors
Ensure you're in the `incus-admin` group:
```bash
sudo usermod -a -G incus-admin $USER
# Log out and back in
```

### CodeQL fails on large repos
CodeQL is memory-intensive. For repos >100k LOC:
- Increase container memory limits, or
- Skip CodeQL (use Semgrep only), or
- Run CodeQL separately with more resources

### "security-scanner template not found"
Run the setup script:
```bash
./scripts/setup.sh
```

See [docs/troubleshooting.md](docs/troubleshooting.md) for more common issues.

## Project Structure
```
Containerized-Vuln-Scanner/
├── README.md                    # This file
├── LICENSE                      # MIT License
├── CHANGELOG.md                 # Version history
├── CONTRIBUTING.md              # Contribution guidelines
├── version.txt                  # Current version
├── scripts/
│   ├── setup.sh                # Initial setup script
│   ├── scan-repo               # Main scanning command
│   └── generate-report         # Report generator
├── docs/
│   ├── architecture.md         # Technical details
│   ├── troubleshooting.md      # Common issues
│   └── sample-report.md        # Example output
└── examples/
    └── custom-rules.yaml       # Example custom Semgrep rules
```

## Commercial Licensing

This project is dual-licensed:

- **Open Source**: AGPL v3 for personal, educational, and open-source use
- **Commercial**: Proprietary license available for companies

### Why Dual Licensing?

The AGPL v3 license requires that if you modify this software and use it to provide a service over a network, you must open-source your modifications. Many companies prefer to keep their modifications proprietary.

### Commercial License Benefits

A commercial license provides:
- ✅ Freedom to keep modifications private
- ✅ Use in proprietary SaaS products
- ✅ No obligation to disclose source code
- ✅ Priority support and custom development
- ✅ Legal indemnification

### Get a Commercial License

For commercial licensing inquiries:
- **Email**: evan@texashardts.com
- **Response time**: 2-4 business days

Typical use cases requiring a commercial license:
- Security scanning as a service (SaaS)
- Integrating into proprietary commercial tools
- Reselling or bundling with commercial products
- Enterprise deployments with custom features

**Pricing**: Starting at $2,500 for startups, custom pricing for enterprise. See [COMMERCIAL-LICENSE-INFO.md](COMMERCIAL-LICENSE-INFO.md) for details.

Individual developers and open-source projects can use this freely under AGPL v3.

## Contributing

Contributions welcome! Please see [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

Ideas for contributions:
- Additional security tool integrations
- Support for more languages
- HTML/PDF report generation
- CI/CD integration examples
- Docker alternative implementation

## License

- **Open Source**: AGPL v3 - see [LICENSE](LICENSE) file
- **Commercial**: Contact for proprietary licensing - see [LICENSE-COMMERCIAL.template](LICENSE-COMMERCIAL.template)

## Author

**Evan Hardt**
- University of Alabama - Cybersecurity Researcher
- GitHub: [@Ac3ofHardts](https://github.com/Ac3ofHardts)
- Email: echardt@crimson.ua.edu | evan@texashardts.com

## Acknowledgments

- [Semgrep](https://semgrep.dev/) for SAST capabilities
- [CodeQL](https://codeql.github.com/) for deep dataflow analysis
- [Gitleaks](https://github.com/gitleaks/gitleaks) for secret detection
- [Incus](https://linuxcontainers.org/incus/) for container infrastructure
- Inspired by real-world security assessment workflows and Senior Design Project Consulting Work

## Related Projects

- [semgrep-rules](https://github.com/returntocorp/semgrep-rules) - Community Semgrep rules
- [CodeQL queries](https://github.com/github/codeql) - Official CodeQL queries
- [TruffleHog](https://github.com/trufflesecurity/trufflehog) - Alternative secret scanner

---

**⭐ If you find this useful, please star the repository!**

**💼 Need a commercial license?** Email evan@texashardts.com

For questions or issues, please [open an issue](https://github.com/Ac3ofHardts/Containerized-Vuln-Scanner/issues).
