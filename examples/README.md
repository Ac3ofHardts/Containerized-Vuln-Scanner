# Example Custom Rules

This directory contains example custom Semgrep rules you can use as templates for your organization.

## Using Custom Rules

### Option 1: Add to Container
```bash
# Copy rules into the template container
incus exec security-scanner -- mkdir -p /opt/custom-rules
incus file push custom-rules.yaml security-scanner/opt/custom-rules/

# Update scan script to use custom rules
incus exec security-scanner -- bash
# Edit /opt/scanners/run-scans.sh
# Add: semgrep --config=/opt/custom-rules/custom-rules.yaml ...
```

### Option 2: Scan-time Mount
```bash
# Mount rules directory during scan
incus config device add scan-instance custom-rules disk \
  source=/path/to/custom-rules \
  path=/custom-rules \
  readonly=true

# Run semgrep with custom config
semgrep --config=/custom-rules/custom-rules.yaml /target
```

## Rule Examples

### custom-hardcoded-api-key

Detects hardcoded API keys in source code.

**Triggers on**:
```javascript
const api_key = "sk_live_abc123";
api_key = "secret-key-here"
```

### custom-weak-crypto

Detects use of weak cryptographic algorithms.

**Triggers on**:
```javascript
crypto.createHash('md5')
crypto.createHash('sha1')
```

### custom-sql-concat

Detects SQL injection via string concatenation.

**Triggers on**:
```python
query = "SELECT * FROM " + table + " WHERE " + condition
```

## Writing Your Own Rules

See the [Semgrep Rule Syntax documentation](https://semgrep.dev/docs/writing-rules/rule-syntax/) for details.

### Basic Rule Template
```yaml
rules:
  - id: your-rule-id
    pattern: |
      # Your pattern here
    message: Description of the issue
    severity: ERROR|WARNING|INFO
    languages: [javascript, python, ...]
    metadata:
      cwe: CWE-XXX
      category: security|best-practice|...
```

### Testing Rules
```bash
# Test your rule against a sample file
semgrep --config=custom-rules.yaml path/to/test/file.js
```

## Contributing Rules

If you create useful rules, consider:
1. Contributing them upstream to [semgrep-rules](https://github.com/returntocorp/semgrep-rules)
2. Sharing in this project via PR
3. Publishing in your own rule registry