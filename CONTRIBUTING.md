# Contributing to Containerized Vulnerability Scanner

Thank you for considering contributing to Containerized Vulnerability Scanner! This document provides guidelines and instructions for contributing.

## Table of Contents

- [Code of Conduct](#code-of-conduct)
- [How Can I Contribute?](#how-can-i-contribute)
- [Development Setup](#development-setup)
- [Coding Standards](#coding-standards)
- [Commit Messages](#commit-messages)
- [Pull Request Process](#pull-request-process)
- [Adding New Security Tools](#adding-new-security-tools)
- [Testing](#testing)

## Code of Conduct

### Our Standards

**Positive behaviors:**
- Using welcoming and inclusive language
- Being respectful of differing viewpoints
- Gracefully accepting constructive criticism
- Focusing on what is best for the community
- Showing empathy towards others

**Unacceptable behaviors:**
- Trolling, insulting comments, or personal attacks
- Public or private harassment
- Publishing others' private information
- Other unprofessional conduct

## How Can I Contribute?

### Reporting Bugs

Before creating bug reports, please check existing issues. When creating a bug report, include:

- **Clear title** - Descriptive summary of the issue
- **Environment details** - OS, Incus version, scanner version
- **Steps to reproduce** - Detailed steps to recreate the bug
- **Expected behavior** - What you expected to happen
- **Actual behavior** - What actually happened
- **Error output** - Full error messages and logs
- **Screenshots** - If applicable

Use the bug report template in `.github/ISSUE_TEMPLATE/bug_report.md`

### Suggesting Enhancements

Enhancement suggestions are tracked as GitHub issues. Include:

- **Clear title** - Descriptive summary of the enhancement
- **Use case** - Why this would be useful
- **Proposed solution** - How you envision it working
- **Alternatives** - Other approaches you've considered
- **Additional context** - Screenshots, mockups, examples

Use the feature request template in `.github/ISSUE_TEMPLATE/feature_request.md`

### Your First Code Contribution

Unsure where to begin? Look for issues labeled:
- `good first issue` - Simple issues for newcomers
- `help wanted` - Issues where we need community help
- `documentation` - Documentation improvements

## Development Setup

### Prerequisites

- Ubuntu/Debian-based Linux (24.04 recommended)
- Incus installed and configured
- Python 3.8+
- Bash 4.0+
- Git

### Setting Up Development Environment
```bash
# Clone your fork
git clone https://github.com/YOUR_USERNAME/incus-security-scanner.git
cd incus-security-scanner

# Add upstream remote
git remote add upstream https://github.com/ORIGINAL_OWNER/incus-security-scanner.git

# Run setup
./scripts/setup.sh

# Verify installation
scan-repo --help
generate-report --help
```

### Running Tests
```bash
# Run validation script
./prepare-for-release.sh

# Test a scan
scan-repo https://github.com/OWASP/NodeGoat test-scan

# Test report generation
generate-report ~/assessments/results/NodeGoat-*/

# Verify output
cat ~/assessments/results/NodeGoat-*/SECURITY_REPORT.md
```

## Coding Standards

### Bash Scripts

- Use `#!/bin/bash` shebang
- Enable strict mode: `set -e` for critical scripts
- Use meaningful variable names (UPPER_CASE for constants)
- Comment complex logic
- Quote variables: `"$variable"` not `$variable`
- Check return codes for critical operations

**Example:**
```bash
#!/bin/bash
set -e

REPO_URL="$1"
OUTPUT_DIR="${2:-default}"

if [ -z "$REPO_URL" ]; then
    echo "Error: Repository URL required"
    exit 1
fi

# Clone repository
if ! git clone "$REPO_URL" "$OUTPUT_DIR"; then
    echo "Error: Failed to clone repository"
    exit 1
fi
```

### Python Scripts

- Follow PEP 8 style guide
- Use type hints where appropriate
- Include docstrings for functions
- Use meaningful variable names (snake_case)
- Handle exceptions gracefully

**Example:**
```python
def parse_semgrep(results_dir: Path) -> List[Dict]:
    """
    Parse Semgrep JSON results.
    
    Args:
        results_dir: Path to directory containing scan results
        
    Returns:
        List of normalized findings
    """
    semgrep_file = results_dir / 'semgrep.json'
    try:
        with open(semgrep_file, 'r') as f:
            data = json.load(f)
    except (FileNotFoundError, json.JSONDecodeError) as e:
        logger.warning(f"Failed to parse Semgrep results: {e}")
        return []
    
    return normalize_findings(data)
```

### Documentation

- Use Markdown for all documentation
- Include code examples where relevant
- Keep line length to 80-100 characters
- Use proper heading hierarchy
- Link to related documentation

## Commit Messages

### Format
```
<type>(<scope>): <subject>

<body>

<footer>
```

### Type

- `feat`: New feature
- `fix`: Bug fix
- `docs`: Documentation changes
- `style`: Formatting, missing semicolons, etc.
- `refactor`: Code restructuring
- `test`: Adding tests
- `chore`: Maintenance tasks

### Examples
```
feat(scanner): Add support for Rust language

- Integrate clippy for Rust static analysis
- Update report generator to parse clippy output
- Add Rust detection in scan-repo script

Closes #123
```
```
fix(codeql): Handle missing database gracefully

CodeQL database creation was failing silently for
some repositories. Now properly catches errors and
continues with other tools.

Fixes #456
```

## Pull Request Process

### Before Submitting

1. **Test your changes** - Run `./prepare-for-release.sh`
2. **Update documentation** - README, relevant docs
3. **Add tests** - If adding features
4. **Check for conflicts** - Rebase on latest main
5. **Run a full scan** - Ensure nothing is broken

### PR Description Template
```markdown
## Description
Brief description of changes

## Type of Change
- [ ] Bug fix
- [ ] New feature
- [ ] Documentation update
- [ ] Performance improvement
- [ ] Code refactoring

## Testing
Describe testing performed

## Checklist
- [ ] Code follows style guidelines
- [ ] Self-review completed
- [ ] Documentation updated
- [ ] Tests added/updated
- [ ] No new warnings
- [ ] Backward compatible
```

## Adding New Security Tools

### Integration Checklist

- [ ] Update `scripts/setup.sh` to install the tool
- [ ] Add tool execution to `/opt/scanners/run-scans.sh`
- [ ] Add parser to `scripts/generate-report`
- [ ] Update README.md with tool information
- [ ] Add example output to `docs/sample-report.md`
- [ ] Test on multiple languages/repos
- [ ] Update architecture documentation

### Example: Adding a New Tool

**1. Install in setup.sh:**
```bash
incus exec security-scanner -- bash << 'EOF'
pip3 install new-security-tool
EOF
```

**2. Add to scan script:**
```bash
echo "[+] Running new-security-tool..."
new-security-tool scan $TARGET --json > $OUTPUT/newtool.json
NEWTOOL_COUNT=$(jq '.findings | length' $OUTPUT/newtool.json)
echo "    Found $NEWTOOL_COUNT findings"
```

**3. Add parser to generate-report:**
```python
def parse_newtool(results_dir):
    """Parse new-security-tool JSON output"""
    newtool_file = results_dir / 'newtool.json'
    data = load_json(newtool_file)
    if not data:
        return []
    
    findings = []
    for item in data.get('findings', []):
        findings.append({
            'tool': 'NewTool',
            'severity': map_severity(item['severity']),
            'title': item['title'],
            'file': item['location']['file'],
            'line': item['location']['line'],
            'message': item['description'],
            'cwe': item.get('cwe', []),
            'owasp': item.get('owasp', [])
        })
    return findings
```

## Testing

### Manual Testing
```bash
# Test basic functionality
scan-repo https://github.com/OWASP/NodeGoat

# Test different languages
scan-repo https://github.com/django/django  # Python
scan-repo https://github.com/expressjs/express  # JavaScript

# Test error handling
scan-repo https://github.com/nonexistent/repo

# Test report generation
generate-report ~/assessments/results/NodeGoat-*/
```

### Test Checklist

- [ ] Setup script completes successfully
- [ ] Template container created correctly
- [ ] Scan completes without errors
- [ ] All tools produce output
- [ ] Report generates successfully
- [ ] Files have correct permissions
- [ ] Cleanup happens properly
- [ ] Error messages are helpful

## Getting Help

- **Questions**: Open a discussion on GitHub
- **Issues**: https://github.com/Ac3ofHardts/Containerized-Vuln-Scanner/issues
- **Email**: evan@texashardts.com (for commercial license holders)

## Recognition

Contributors will be:
- Credited in release notes
- Thanked in CHANGELOG.md
- Acknowledged in the community

## License

By contributing, you agree that your contributions will be licensed under the AGPL v3 license. If you're contributing on behalf of a company, ensure you have permission to license your work under AGPL v3.

For commercial licensing questions, see [LICENSE-COMMERCIAL.template](LICENSE-COMMERCIAL.template).

---

Thank you for contributing to Containerized Vulnerability Scanner! 🎉