# Troubleshooting Guide

## Installation Issues

### Incus Not Found

**Symptom**:
```
bash: incus: command not found
```

**Solution**:
Install Incus following the [official guide](https://linuxcontainers.org/incus/docs/main/installing/)

For Ubuntu 22.04:
```bash
sudo apt update
curl -fsSL https://pkgs.zabbly.com/key.asc | sudo gpg --dearmor -o /etc/apt/keyrings/zabbly.gpg
echo "Types: deb
URIs: https://pkgs.zabbly.com/incus/stable
Suites: jammy
Components: main
Architectures: amd64
Signed-By: /etc/apt/keyrings/zabbly.gpg" | sudo tee /etc/apt/sources.list.d/zabbly-incus-stable.sources
sudo apt update
sudo apt install incus
```

### Permission Denied

**Symptom**:
```
Error: Get "http://unix.socket/...": dial unix /var/lib/incus/unix.socket: connect: permission denied
```

**Solution**:
Add yourself to the `incus-admin` group:
```bash
sudo usermod -a -G incus-admin $USER
```

**Important**: Log out and back in for group changes to take effect.

Verify:
```bash
groups | grep incus-admin
```

### Setup Script Fails

**Symptom**:
```
ERROR: Failed to create container
```

**Solution**:
1. Check Incus is initialized:
```bash
   incus admin init
```
   
2. Verify storage pool exists:
```bash
   incus storage list
```

3. Check available disk space:
```bash
   df -h
```

## Scanning Issues

### Container Won't Start

**Symptom**:
```
Error: Failed to start container
```

**Solutions**:

1. **Check if security-scanner template exists**:
```bash
   incus list security-scanner
```
   If not found, run setup:
```bash
   ./scripts/setup.sh
```

2. **View container logs**:
```bash
   incus info security-scanner --show-log
```

3. **Restart Incus service**:
```bash
   sudo systemctl restart incus
```

### Git Clone Fails

**Symptom**:
```
fatal: unable to access 'https://github.com/...': Could not resolve host
```

**Solutions**:

1. **Check internet connection**:
```bash
   ping -c 3 github.com
```

2. **Try with SSH instead of HTTPS**:
```bash
   scan-repo git@github.com:org/repo.git
```

3. **Check for proxy settings**:
```bash
   echo $http_proxy
   echo $https_proxy
```

### Out of Disk Space

**Symptom**:
```
Error: not enough space in storage pool
```

**Solutions**:

1. **Check disk usage**:
```bash
   df -h
   incus storage info default
```

2. **Clean old results**:
```bash
   rm -rf ~/assessments/results/old-*
```

3. **Clean Incus images**:
```bash
   incus image list
   incus image delete <old-image>
```

4. **Increase storage pool** (if using file-backed):
```bash
   incus storage set default size 100GB
```

## Tool-Specific Issues

### CodeQL Fails

**Symptom**:
```
ERROR: CodeQL database creation failed
A fatal error occurred: Exit status 1
```

**Solutions**:

1. **Increase memory** (CodeQL needs 4GB+):
```bash
   # Edit scan-repo script to set memory limit
   incus config set scan-instance limits.memory 8GB
```

2. **Skip CodeQL for large repos**:
   Manually edit container scan script to comment out CodeQL section

3. **Use Semgrep only** for quick scans:
```bash
   # Modify /opt/scanners/run-scans.sh in container
   # Comment out CodeQL section
```

### Semgrep Rate Limited

**Symptom**:
```
Rate limit exceeded for registry.semgrep.dev
```

**Solution**:
Use offline rulesets:
```bash
incus exec security-scanner -- semgrep --config=p/security-audit --config=p/owasp-top-ten
```

Or cache rules locally:
```bash
incus exec security-scanner -- bash
semgrep --config=auto --download-only
```

### Gitleaks Not Finding Secrets

**Symptom**:
No secrets reported but you know they exist

**Solutions**:

1. **Check file was actually scanned**:
```bash
   cat ~/assessments/results/*/gitleaks.json
```

2. **Verify Gitleaks configuration**:
```bash
   incus exec security-scanner -- gitleaks --version
```

3. **Test directly**:
```bash
   incus exec security-scanner -- bash
   cd /target
   gitleaks detect --no-git --verbose
```

## Report Generation Issues

### Python Errors

**Symptom**:
```
ModuleNotFoundError: No module named 'json'
```

**Solution**:
```bash
# Reinstall Python3
sudo apt install --reinstall python3

# Verify
python3 -c "import json; print('OK')"
```

### Invalid JSON

**Symptom**:
```
json.decoder.JSONDecodeError: Expecting value: line 1 column 1
```

**Solution**:
One of the scan outputs is corrupt or empty.

1. **Check which files exist**:
```bash
   ls -lh ~/assessments/results/*/
```

2. **Validate JSON files**:
```bash
   jq . ~/assessments/results/*/semgrep.json
   jq . ~/assessments/results/*/gitleaks.json
```

3. **Re-run scan** if files are corrupt

### Report Has No Findings

**Symptom**:
Report shows 0 findings but scans ran

**Solution**:

1. **Check raw scan outputs**:
```bash
   cat ~/assessments/results/*/summary.txt
   jq '.results | length' ~/assessments/results/*/semgrep.json
```

2. **Verify scans actually ran**:
   Look for non-empty JSON files

3. **Test report generator directly**:
```bash
   generate-report --help
   python3 -m json.tool ~/assessments/results/*/semgrep.json
```

## Performance Issues

### Scans Taking Too Long

**Symptom**:
Scans take 30+ minutes for small repos

**Solutions**:

1. **Check if CodeQL is the bottleneck**:
   Monitor during scan - CodeQL is typically slowest

2. **Skip CodeQL**:
   Edit `/opt/scanners/run-scans.sh` in template container

3. **Check system resources**:
```bash
   top
   free -h
   iostat -x 1
```

4. **Reduce concurrent scans**:
   Don't run multiple scans simultaneously

### Container Startup Slow

**Symptom**:
Container takes 30+ seconds to start

**Solutions**:

1. **Use ZFS/Btrfs storage** (if available):
   Faster than directory-based storage

2. **Pre-start template**:
```bash
   incus start security-scanner
   # Keep it running, copy from running container
```

3. **Check disk I/O**:
```bash
   iostat -x 1
```

## File Access Issues

### Can't Read Results

**Symptom**:
```
Permission denied: ~/assessments/results/*/semgrep.json
```

**Solution**:

1. **Check file ownership**:
```bash
   ls -l ~/assessments/results/*/
```

2. **Fix UID mapping** (should be automatic):
```bash
   # Files should be owned by your user, not root
   # If not, UID mapping is broken
   sudo chown -R $USER:$USER ~/assessments/results/
```

### Results Directory Not Created

**Symptom**:
```
Error: No such file or directory: ~/assessments/results
```

**Solution**:
```bash
mkdir -p ~/assessments/results
```

Should be created automatically by scan-repo, but create manually if needed.

## Network Issues

### Can't Download Tools During Setup

**Symptom**:
```
Failed to fetch https://...
```

**Solutions**:

1. **Check internet connection**:
```bash
   ping -c 3 8.8.8.8
```

2. **Check DNS**:
```bash
   nslookup github.com
```

3. **Try with proxy** (if behind corporate firewall):
```bash
   export http_proxy=http://proxy:port
   export https_proxy=http://proxy:port
   ./scripts/setup.sh
```

### Container Has No Network

**Symptom**:
Tools can't reach internet from inside container

**Solution**:

By design, containers have no network access during scans (security feature).

If needed for testing:
```bash
incus config device add security-scanner eth0 nic \
  name=eth0 nictype=bridged parent=incusbr0
```

## Getting Help

### Collect Debugging Information

When reporting issues, include:
```bash
# System info
uname -a
cat /etc/os-release

# Incus version
incus version

# Container status
incus list

# Storage info
incus storage list
incus storage info default

# Recent logs
incus info security-scanner --show-log | tail -50

# Scan output
cat ~/assessments/results/latest/summary.txt
```

### Where to Get Help

1. **GitHub Issues**: https://github.com/Ac3ofHardts/Containerized-Vuln-Scanner/issues
2. **Incus Docs**: https://linuxcontainers.org/incus/docs/
3. **Semgrep Community**: https://semgrep.dev/docs/
4. **Email**: evan@texashardts.com (for commercial license holders)

### Before Opening an Issue

- [ ] Run `./prepare-for-release.sh` to check for common problems
- [ ] Check this troubleshooting guide
- [ ] Search existing GitHub issues
- [ ] Try on a fresh Ubuntu 24.04 VM if possible
- [ ] Collect debugging information (see above)

## Known Limitations

- **No Windows support** (Linux/WSL2 only)
- **No incremental scans** (always full scan)
- **CodeQL memory intensive** (4GB+ recommended)
- **No concurrent scanning** of same repo
- **Requires Incus** (Docker alternative not yet available)

See [Architecture docs](architecture.md) for more technical details.