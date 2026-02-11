#!/usr/bin/env python3
"""
Generate comprehensive security report from scan results.
ALL FINDINGS INCLUDED - NO TRUNCATION
"""

import json
import sys
from pathlib import Path
from datetime import datetime
from collections import defaultdict

def load_json_file(file_path):
    """Safely load JSON file."""
    try:
        with open(file_path) as f:
            return json.load(f)
    except:
        return None

def analyze_codeql(results_dir):
    """Analyze CodeQL results."""
    codeql_file = results_dir / "codeql.sarif"
    
    if not codeql_file.exists():
        return None
    
    data = load_json_file(codeql_file)
    if not data:
        return None
    
    runs = data.get('runs', [])
    if not runs:
        return None
    
    results = runs[0].get('results', [])
    if not results:
        return {'total': 0, 'severity_counts': {}, 'findings': {}}
    
    findings = defaultdict(list)
    severity_counts = defaultdict(int)
    
    for result in results:
        level = result.get('level', 'note')
        severity_counts[level] += 1
        
        message_obj = result.get('message', {})
        if isinstance(message_obj, dict):
            message = message_obj.get('text', 'No message')
        else:
            message = str(message_obj)
        
        file_path = 'unknown'
        line = 0
        
        locations = result.get('locations', [])
        if locations:
            phys_loc = locations[0].get('physicalLocation', {})
            artifact = phys_loc.get('artifactLocation', {})
            file_path = artifact.get('uri', 'unknown')
            
            region = phys_loc.get('region', {})
            line = region.get('startLine', 0)
        
        rule_id = result.get('ruleId', 'unknown')
        
        finding = {
            'level': level,
            'rule_id': rule_id,
            'message': message,
            'file': file_path,
            'line': line,
        }
        findings[level].append(finding)
    
    return {
        'total': len(results),
        'severity_counts': dict(severity_counts),
        'findings': dict(findings)
    }

def analyze_semgrep(results_dir):
    """Analyze Semgrep results."""
    semgrep_file = results_dir / "semgrep.json"
    if not semgrep_file.exists():
        return None
    
    data = load_json_file(semgrep_file)
    if not data:
        return None
    
    results = data.get('results', [])
    findings = defaultdict(list)
    severity_counts = defaultdict(int)
    
    for result in results:
        severity = result.get('extra', {}).get('severity', 'INFO')
        severity_counts[severity] += 1
        
        finding = {
            'severity': severity,
            'rule_id': result.get('check_id', 'unknown'),
            'message': result.get('extra', {}).get('message', 'No message'),
            'file': result.get('path', 'unknown'),
            'line': result.get('start', {}).get('line', 0),
            'cwe': result.get('extra', {}).get('metadata', {}).get('cwe', []),
            'owasp': result.get('extra', {}).get('metadata', {}).get('owasp', []),
        }
        findings[severity].append(finding)
    
    return {
        'total': len(results),
        'severity_counts': dict(severity_counts),
        'findings': dict(findings)
    }

def analyze_gitleaks(results_dir):
    """Analyze Gitleaks results."""
    gitleaks_file = results_dir / "gitleaks.json"
    if not gitleaks_file.exists():
        return None
    
    data = load_json_file(gitleaks_file)
    if not data:
        return {'total': 0, 'findings': []}
    
    findings = []
    for secret in data:
        finding = {
            'description': secret.get('Description', 'Unknown'),
            'file': secret.get('File', 'unknown'),
            'line': secret.get('StartLine', 0),
            'match': secret.get('Match', ''),
        }
        findings.append(finding)
    
    return {
        'total': len(data),
        'findings': findings
    }

def analyze_bandit(results_dir):
    """Analyze Bandit results."""
    bandit_file = results_dir / "bandit.json"
    if not bandit_file.exists():
        return None
    
    data = load_json_file(bandit_file)
    if not data:
        return None
    
    results = data.get('results', [])
    findings = defaultdict(list)
    severity_counts = defaultdict(int)
    
    for result in results:
        severity = result.get('issue_severity', 'LOW')
        severity_counts[severity] += 1
        
        finding = {
            'severity': severity,
            'confidence': result.get('issue_confidence', 'MEDIUM'),
            'issue': result.get('issue_text', 'Unknown'),
            'file': result.get('filename', 'unknown'),
            'line': result.get('line_number', 0),
            'cwe': result.get('issue_cwe', {}).get('id', 'N/A'),
        }
        findings[severity].append(finding)
    
    return {
        'total': len(results),
        'severity_counts': dict(severity_counts),
        'findings': dict(findings)
    }

def is_multi_branch_scan(results_dir):
    """Check if this is a multi-branch scan."""
    return (results_dir / "MASTER_SUMMARY.txt").exists()

def get_branch_directories(results_dir):
    """Get all branch directories in a multi-branch scan."""
    branches = []
    for item in results_dir.iterdir():
        if item.is_dir():
            if (item / "semgrep.json").exists() or (item / "codeql.sarif").exists():
                branches.append(item)
    return sorted(branches, key=lambda x: x.name)

def generate_report(results_dir, output_file):
    """Generate comprehensive markdown report - ALL FINDINGS."""
    results_dir = Path(results_dir)
    
    report = []
    report.append("# Security Vulnerability Assessment Report")
    report.append("")
    report.append(f"**Generated:** {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    report.append(f"**Scan Results:** {results_dir.name}")
    report.append("")
    
    if is_multi_branch_scan(results_dir):
        report.append("**Type:** Multi-Branch Scan")
        report.append("")
        report.append("---")
        report.append("")
        
        branches = get_branch_directories(results_dir)
        
        report.append(f"## Executive Summary - All Branches ({len(branches)} branches)")
        report.append("")
        report.append("| Branch | Total | Critical | Semgrep | CodeQL | Secrets | Bandit |")
        report.append("|--------|-------|----------|---------|--------|---------|--------|")
        
        grand_total = 0
        grand_critical = 0
        
        for branch_dir in branches:
            branch_name = branch_dir.name
            
            semgrep = analyze_semgrep(branch_dir)
            gitleaks = analyze_gitleaks(branch_dir)
            codeql = analyze_codeql(branch_dir)
            bandit = analyze_bandit(branch_dir)
            
            total = 0
            critical = 0
            
            semgrep_count = semgrep['total'] if semgrep else 0
            codeql_count = codeql['total'] if codeql else 0
            secrets_count = gitleaks['total'] if gitleaks else 0
            bandit_count = bandit['total'] if bandit else 0
            
            if semgrep:
                total += semgrep_count
                critical += semgrep['severity_counts'].get('ERROR', 0)
            if gitleaks:
                total += secrets_count
                critical += secrets_count
            if codeql:
                total += codeql_count
                critical += codeql['severity_counts'].get('error', 0)
            if bandit:
                total += bandit_count
                critical += bandit['severity_counts'].get('HIGH', 0)
            
            grand_total += total
            grand_critical += critical
            
            report.append(f"| `{branch_name}` | {total} | {critical} | {semgrep_count} | {codeql_count} | {secrets_count} | {bandit_count} |")
        
        report.append(f"| **TOTAL** | **{grand_total}** | **{grand_critical}** | - | - | - | - |")
        report.append("")
        report.append("---")
        report.append("")
        
        # COMPLETE DETAILED FINDINGS - ALL ISSUES
        report.append("## Complete Detailed Findings by Branch")
        report.append("")
        
        for branch_dir in branches:
            branch_name = branch_dir.name
            
            report.append(f"### Branch: `{branch_name}`")
            report.append("")
            
            semgrep = analyze_semgrep(branch_dir)
            gitleaks = analyze_gitleaks(branch_dir)
            codeql = analyze_codeql(branch_dir)
            bandit = analyze_bandit(branch_dir)
            
            # ALL SEMGREP FINDINGS
            if semgrep and semgrep['total'] > 0:
                report.append(f"#### Semgrep - {semgrep['total']} Total Issues")
                report.append("")
                
                for severity in ['ERROR', 'WARNING', 'INFO']:
                    if severity in semgrep['findings']:
                        findings = semgrep['findings'][severity]
                        report.append(f"##### {severity} ({len(findings)} issues)")
                        report.append("")
                        
                        for idx, finding in enumerate(findings, 1):
                            report.append(f"**{idx}. {finding['rule_id']}**")
                            report.append(f"- **File:** `{finding['file']}:{finding['line']}`")
                            report.append(f"- **Message:** {finding['message']}")
                            if finding['cwe']:
                                report.append(f"- **CWE:** {', '.join(map(str, finding['cwe']))}")
                            if finding['owasp']:
                                report.append(f"- **OWASP:** {', '.join(map(str, finding['owasp']))}")
                            report.append("")
                
                report.append("---")
                report.append("")
            
            # ALL GITLEAKS FINDINGS
            if gitleaks and gitleaks['total'] > 0:
                report.append(f"#### ⚠️ Gitleaks - {gitleaks['total']} Secrets Found")
                report.append("")
                
                for idx, finding in enumerate(gitleaks['findings'], 1):
                    report.append(f"**{idx}. {finding['description']}**")
                    report.append(f"- **File:** `{finding['file']}:{finding['line']}`")
                    report.append(f"- **Match:** `{finding['match'][:100]}...`")
                    report.append("")
                
                report.append("---")
                report.append("")
            
            # ALL CODEQL FINDINGS
            if codeql and codeql['total'] > 0:
                report.append(f"#### CodeQL - {codeql['total']} Total Issues")
                report.append("")
                
                for level in ['error', 'warning', 'note', 'recommendation']:
                    if level in codeql['findings']:
                        findings = codeql['findings'][level]
                        report.append(f"##### {level.upper()} ({len(findings)} issues)")
                        report.append("")
                        
                        for idx, finding in enumerate(findings, 1):
                            report.append(f"**{idx}. {finding['rule_id']}**")
                            report.append(f"- **File:** `{finding['file']}:{finding['line']}`")
                            report.append(f"- **Message:** {finding['message']}")
                            report.append("")
                
                report.append("---")
                report.append("")
            
            # ALL BANDIT FINDINGS
            if bandit and bandit['total'] > 0:
                report.append(f"#### Bandit - {bandit['total']} Total Issues")
                report.append("")
                
                for severity in ['HIGH', 'MEDIUM', 'LOW']:
                    if severity in bandit['findings']:
                        findings = bandit['findings'][severity]
                        report.append(f"##### {severity} ({len(findings)} issues)")
                        report.append("")
                        
                        for idx, finding in enumerate(findings, 1):
                            report.append(f"**{idx}. {finding['issue']}**")
                            report.append(f"- **File:** `{finding['file']}:{finding['line']}`")
                            report.append(f"- **Confidence:** {finding['confidence']}")
                            if finding['cwe'] != 'N/A':
                                report.append(f"- **CWE:** {finding['cwe']}")
                            report.append("")
                
                report.append("---")
                report.append("")
    
    else:
        # SINGLE BRANCH - COMPLETE REPORT
        report.append("**Type:** Single Branch Scan")
        report.append("")
        
        semgrep = analyze_semgrep(results_dir)
        gitleaks = analyze_gitleaks(results_dir)
        codeql = analyze_codeql(results_dir)
        bandit = analyze_bandit(results_dir)
        
        total = 0
        critical = 0
        
        if semgrep:
            total += semgrep['total']
            critical += semgrep['severity_counts'].get('ERROR', 0)
        if gitleaks:
            total += gitleaks['total']
            critical += gitleaks['total']
        if codeql:
            total += codeql['total']
            critical += codeql['severity_counts'].get('error', 0)
        if bandit:
            total += bandit['total']
            critical += bandit['severity_counts'].get('HIGH', 0)
        
        report.append(f"**Total Issues:** {total}")
        report.append(f"**Critical:** {critical}")
        report.append("")
        report.append("---")
        report.append("")
        
        report.append("## Complete Findings - All Issues")
        report.append("")
        
        # ALL SEMGREP
        if semgrep and semgrep['total'] > 0:
            report.append(f"### Semgrep - {semgrep['total']} Total Issues")
            report.append("")
            
            for severity in ['ERROR', 'WARNING', 'INFO']:
                if severity in semgrep['findings']:
                    findings = semgrep['findings'][severity]
                    report.append(f"#### {severity} ({len(findings)} issues)")
                    report.append("")
                    
                    for idx, f in enumerate(findings, 1):
                        report.append(f"**{idx}. {f['rule_id']}**")
                        report.append(f"- `{f['file']}:{f['line']}`")
                        report.append(f"- {f['message']}")
                        if f['cwe']:
                            report.append(f"- CWE: {', '.join(map(str, f['cwe']))}")
                        report.append("")
        
        # ALL GITLEAKS
        if gitleaks and gitleaks['total'] > 0:
            report.append(f"### ⚠️ Gitleaks - {gitleaks['total']} Secrets")
            report.append("")
            for idx, f in enumerate(gitleaks['findings'], 1):
                report.append(f"**{idx}. {f['description']}**")
                report.append(f"- `{f['file']}:{f['line']}`")
                report.append(f"- Match: `{f['match'][:100]}...`")
                report.append("")
        
        # ALL CODEQL
        if codeql and codeql['total'] > 0:
            report.append(f"### CodeQL - {codeql['total']} Total Issues")
            report.append("")
            
            for level in ['error', 'warning', 'note', 'recommendation']:
                if level in codeql['findings']:
                    findings = codeql['findings'][level]
                    report.append(f"#### {level.upper()} ({len(findings)} issues)")
                    report.append("")
                    
                    for idx, f in enumerate(findings, 1):
                        report.append(f"**{idx}. {f['rule_id']}**")
                        report.append(f"- `{f['file']}:{f['line']}`")
                        report.append(f"- {f['message']}")
                        report.append("")
        
        # ALL BANDIT
        if bandit and bandit['total'] > 0:
            report.append(f"### Bandit - {bandit['total']} Total Issues")
            report.append("")
            
            for severity in ['HIGH', 'MEDIUM', 'LOW']:
                if severity in bandit['findings']:
                    findings = bandit['findings'][severity]
                    report.append(f"#### {severity} ({len(findings)} issues)")
                    report.append("")
                    
                    for idx, f in enumerate(findings, 1):
                        report.append(f"**{idx}. {f['issue']}**")
                        report.append(f"- `{f['file']}:{f['line']}`")
                        report.append(f"- Confidence: {f['confidence']}")
                        report.append("")
    
    report.append("## Recommendations")
    report.append("")
    report.append("1. **Address all critical/high severity findings immediately**")
    report.append("2. **Rotate all exposed secrets and credentials**")
    report.append("3. **Implement automated security scanning in CI/CD pipeline**")
    report.append("4. **Conduct thorough security code review**")
    report.append("5. **Enable dependency scanning for known CVEs**")
    report.append("")
    
    with open(output_file, 'w') as f:
        f.write('\n'.join(report))
    
    print(f"[✓] Complete report generated: {output_file}")
    print(f"    Total lines: {len(report)}")

if __name__ == '__main__':
    if len(sys.argv) != 2:
        print("Usage: generate-report <results-directory>")
        sys.exit(1)
    
    results_dir = sys.argv[1]
    if not Path(results_dir).exists():
        print(f"Error: Directory not found: {results_dir}")
        sys.exit(1)
    
    output_file = Path(results_dir) / "SECURITY_REPORT.md"
    generate_report(results_dir, output_file)
