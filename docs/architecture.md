# Architecture

## System Overview

Incus Security Scanner uses a containerized approach to security scanning, providing isolation, reproducibility, and minimal system impact.

## High-Level Architecture
```
┌─────────────────────────────────────────────────────────────┐
│                         Host System                         │
│                                                             │
│   ┌────────────────────────────────────────────────────┐    │
│   │     security-scanner (Template Container)          │    │
│   │                                                    │    │
│   │  ┌─────────────┐  ┌─────────────┐  ┌───────────┐   │    │
│   │  │   Semgrep   │  │   CodeQL    │  │  Gitleaks │   │    │
│   │  └─────────────┘  └─────────────┘  └───────────┘   │    │
│   │  ┌─────────────┐  ┌─────────────┐                  │    │
│   │  │   Bandit    │  │   Safety    │                  │    │
│   │  └─────────────┘  └─────────────┘                  │    │
│   │                                                    │    │
│   │  /opt/scanners/run-scans.sh                        │    │
│   └────────────────────────────────────────────────────┘    │
│                            ▲                                │
│                            │ incus copy                     │
│                            │                                │
│   ┌────────────────────────┴──────────────────────────┐     │
│   │         Per-Scan Instance (ephemeral)             │     │
│   │                                                   │     │
│   │  /target  ◄── (read-only mount) ◄── repo clone    │     │
│   │  /output  ◄── (writable mount)  ◄── ~/assessments │     │
│   │                                                   │     │
│   │  Runs: run-scans.sh /target /output               │     │
│   └───────────────────────────────────────────────────┘     │
│                                                             │
│   User Commands:                                            │
│   • scan-repo <url> [name]                                  │
│   • generate-report <results-dir>                           │
└─────────────────────────────────────────────────────────────┘
```

## Component Details

### Template Container (`security-scanner`)

**Purpose**: Pre-built, reusable container with all security tools installed.

**Contents**:
- Ubuntu 24.04 base
- Security tools: Semgrep, CodeQL, Gitleaks, Bandit, Safety
- Scan orchestration script: `/opt/scanners/run-scans.sh`
- System utilities: jq, git, python3, nodejs

**Lifecycle**: 
- Created once during setup
- Remains stopped (acts as template)
- Never directly scanned
- Updated periodically for tool versions

**Storage**: ~5GB on disk

### Scan Instance (Ephemeral)

**Purpose**: Isolated environment for each individual scan.

**Creation**: `incus copy security-scanner scan-<name>`

**Mounts**:
```
Host → Container Mapping:
~/assessments/repos/<name> → /target (read-only)
~/assessments/results/<name> → /output (read/write)
```

**UID Mapping**: Container root (UID 0) → Host user (configured via `raw.idmap`)

**Lifecycle**:
1. Copy from template (COW - fast)
2. Configure mounts and UID mapping
3. Start container
4. Execute scan script
5. Stop container
6. Delete container
7. Delete source repository clone

**Duration**: 30 seconds - 10 minutes depending on repo size

### Host Commands

#### `scan-repo`

**Location**: `/usr/local/bin/scan-repo`

**Workflow**:
```bash
1. Parse arguments (repo URL, optional name)
2. Generate timestamp-based output directory
3. git clone --depth=1 <repo> to temp location
4. incus copy security-scanner → scan-<name>
5. Configure container (UID mapping, mounts)
6. incus start scan-<name>
7. incus exec scan-<name> -- /opt/scanners/run-scans.sh /target /output
8. Wait for completion
9. incus stop && incus delete scan-<name>
10. rm -rf cloned repository
11. Display results location
```

**Output Structure**:
```
~/assessments/results/<name>-<timestamp>/
├── summary.txt
├── semgrep.json
├── semgrep.txt
├── codeql.sarif
├── gitleaks.json
├── bandit.json
├── bandit.txt
└── safety.json
```

#### `generate-report`

**Location**: `/usr/local/bin/generate-report`

**Language**: Python 3

**Process**:
1. Load JSON/SARIF files from results directory
2. Parse each tool's output format
3. Normalize to common finding structure
4. Sort by severity (Critical → High → Medium → Low)
5. Generate Markdown with:
   - Executive summary
   - Tool statistics
   - Detailed findings per severity
   - Recommendations
6. Write to `SECURITY_REPORT.md`

## Data Flow

### Scan Execution Flow
```
User runs: scan-repo https://github.com/org/repo

1. Clone Repository
   └─→ git clone --depth=1 → /tmp/repos/repo-TIMESTAMP

2. Create Container
   └─→ incus copy security-scanner scan-repo-TIMESTAMP

3. Configure Container
   ├─→ Set UID mapping (container root → host user)
   ├─→ Mount /target (read-only) → cloned repo
   └─→ Mount /output (read/write) → results dir

4. Start & Execute
   └─→ incus exec ... /opt/scanners/run-scans.sh /target /output
        ├─→ Semgrep → semgrep.json
        ├─→ CodeQL → codeql.sarif
        ├─→ Gitleaks → gitleaks.json
        ├─→ Bandit → bandit.json
        ├─→ Safety → safety.json
        └─→ Generate summary.txt

5. Cleanup
   ├─→ Stop container
   ├─→ Delete container
   └─→ Delete cloned repo

6. Results Available
   └─→ ~/assessments/results/repo-TIMESTAMP/
```

### Report Generation Flow
```
User runs: generate-report ~/assessments/results/repo-TIMESTAMP/

1. Load Files
   ├─→ Parse semgrep.json (Semgrep findings)
   ├─→ Parse codeql.sarif (CodeQL findings)
   ├─→ Parse gitleaks.json (Secret findings)
   └─→ Parse bandit.json (Python findings)

2. Normalize
   └─→ Convert all to common structure:
        {
          tool: string,
          severity: Critical|High|Medium|Low,
          title: string,
          file: string,
          line: number,
          message: string,
          cwe: string[],
          owasp: string[]
        }

3. Sort & Group
   ├─→ Sort by severity
   └─→ Group by severity level

4. Generate Markdown
   ├─→ Executive summary
   ├─→ Statistics table
   ├─→ Findings by severity
   └─→ Recommendations

5. Write Output
   └─→ SECURITY_REPORT.md
```

## Storage Architecture

### Directory Backend

Currently uses `dir` storage backend (directory-based):

**Advantages**:
- Works on any filesystem
- No special kernel modules needed
- Simple, predictable

**Disadvantages**:
- Slower than ZFS/Btrfs
- No copy-on-write for fast clones
- Larger disk usage

**Future Enhancement**: Support for ZFS/Btrfs when available

### Storage Locations
```
Host Filesystem:
~/.local/share/incus/
├── storage-pools/
│   └── default/
│       ├── containers/
│       │   └── security-scanner/  (template)
│       └── containers-snapshots/

~/assessments/
├── repos/           (temporary - deleted after scan)
│   └── <name>-<timestamp>/
└── results/         (permanent - user manages)
    └── <name>-<timestamp>/
        ├── *.json
        ├── *.sarif
        └── *.txt
```

## Security Considerations

### Isolation

**Container Isolation**:
- Each scan runs in separate namespace
- No network access (unless explicitly enabled)
- Limited filesystem access (only mounted paths)
- Process isolation from host

**Code Mounting**:
- Source code mounted read-only
- Prevents accidental modification
- Prevents malicious code from affecting host

### UID Mapping
```
Container UID 0 (root) → Host UID <user>
```

This ensures:
- Files created in /output are owned by host user
- No privilege escalation
- Easy file access after scan

### Trust Boundaries

**Trusted**:
- Template container (built by user)
- Scan scripts (user-controlled)
- Security tools (from official sources)

**Untrusted**:
- Target repositories (potentially malicious)
- All code being scanned

**Mitigation**:
- Read-only mounts prevent tampering
- Isolated execution prevents host compromise
- No build/execution of target code (static analysis only)

## Performance Characteristics

### Resource Usage

| Component | CPU | Memory | Disk I/O | Duration |
|-----------|-----|--------|----------|----------|
| Container startup | Low | 50MB | Minimal | 1-2s |
| Semgrep | Medium | 500MB | Low | 10-60s |
| CodeQL | High | 2-4GB | Medium | 30s-5min |
| Gitleaks | Low | 100MB | Medium | 5-30s |
| Bandit | Low | 200MB | Low | 5-20s |
| Container cleanup | Low | N/A | Low | 1-2s |

### Scalability

**Single Scan**: 1-10 minutes depending on repository size

**Parallel Scans**: Limited by:
- Available RAM (2-4GB per concurrent scan)
- CPU cores (CodeQL is CPU-intensive)
- Disk I/O (less critical)

**Recommended**: Max 2-3 concurrent scans on 16GB system

### Optimization Opportunities

1. **Skip CodeQL for quick scans** (10x faster)
2. **Pre-warm container** (keep one running)
3. **Cache dependencies** (for repeated scans)
4. **Parallel tool execution** (within container)
5. **ZFS/Btrfs backend** (faster container cloning)

## Extension Points

### Adding New Tools

1. Update `scripts/setup.sh`:
```bash
   incus exec security-scanner -- apt install new-tool
```

2. Update `/opt/scanners/run-scans.sh`:
```bash
   echo "[+] Running new-tool..."
   new-tool scan /target > /output/newtool.json
```

3. Update `scripts/generate-report`:
```python
   def parse_newtool(results_dir):
       # Parse newtool.json
       # Return normalized findings
```

### Custom Rulesets

Mount custom rules directory:
```bash
incus config device add scan-instance custom-rules disk \
  source=/path/to/rules \
  path=/opt/custom-rules
```

### CI/CD Integration

Example GitHub Actions:
```yaml
- name: Security Scan
  run: |
    scan-repo ${{ github.event.repository.clone_url }}
    generate-report ~/assessments/results/*/
```

## Comparison to Alternatives

### vs Docker-based Scanning

**Incus Advantages**:
- Lighter weight (system containers vs app containers)
- Better resource isolation
- Easier file mounting
- Persistent templates

**Docker Advantages**:
- More widespread adoption
- Better CI/CD integration
- Hub ecosystem

### vs Native Installation

**Incus Advantages**:
- No pollution of host system
- Reproducible environments
- Easy cleanup
- Version isolation

**Native Advantages**:
- Slightly faster
- Simpler setup
- Lower resource overhead

### vs VM-based Scanning

**Incus Advantages**:
- Much faster startup
- Lower memory overhead
- Shared kernel (efficient)

**VM Advantages**:
- Stronger isolation
- Can scan Windows code on Linux host

## Technical Debt & Future Improvements

### Current Limitations

1. **No incremental scanning** - Always full scan
2. **Single-threaded tools** - Could parallelize
3. **No result caching** - Rescans duplicate work
4. **Limited reporting formats** - Only Markdown
5. **No web UI** - CLI only

### Roadmap

- [ ] PDF report generation
- [ ] HTML dashboard
- [ ] Incremental scans (git diff-based)
- [ ] Result database (SQLite)
- [ ] Web API for remote scanning
- [ ] Docker alternative implementation
- [ ] Windows support (WSL2)
- [ ] Custom rule management UI

## References

- [Incus Documentation](https://linuxcontainers.org/incus/docs/)
- [Semgrep Architecture](https://semgrep.dev/docs/architecture/)
- [CodeQL Documentation](https://codeql.github.com/docs/)
- [SARIF Specification](https://sarifweb.azurewebsites.net/)