# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2026-01-29

### Added
- Initial release
- Incus-based containerized security scanning
- Multi-tool integration (Semgrep, CodeQL, Gitleaks, Bandit)
- Automated report generation in Markdown
- Support for JavaScript/TypeScript, Python, Java, Go, C/C++
- Command-line workflow: scan-repo and generate-report
- Comprehensive documentation

### Security
- All scans run in isolated containers
- Read-only mounting of source code
- No persistence of scan targets