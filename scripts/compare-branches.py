#!/usr/bin/env python3
"""
Compare vulnerability scan results across branches.
Shows which branches have more/fewer vulnerabilities.
"""

import json
import sys
from pathlib import Path
from collections import defaultdict

def load_semgrep_results(file_path):
    """Load and count Semgrep findings by severity."""
    try:
        with open(file_path) as f:
            data = json.load(f)
            results = data.get('results', [])
            
            counts = defaultdict(int)
            for result in results:
                severity = result.get('extra', {}).get('severity', 'UNKNOWN')
                counts[severity] += 1
            
            return dict(counts)
    except:
        return {}

def load_gitleaks_results(file_path):
    """Load and count Gitleaks findings."""
    try:
        with open(file_path) as f:
            data = json.load(f)
            return len(data) if isinstance(data, list) else 0
    except:
        return 0

def load_codeql_results(file_path):
    """Load and count CodeQL findings by severity."""
    try:
        with open(file_path) as f:
            data = json.load(f)
            results = data.get('runs', [{}])[0].get('results', [])
            
            counts = defaultdict(int)
            for result in results:
                level = result.get('level', 'note')
                counts[level] += 1
            
            return dict(counts)
    except:
        return {}

def analyze_branch_results(results_dir):
    """Analyze all branch results."""
    base_path = Path(results_dir)
    
    if not base_path.exists():
        print(f"Error: {results_dir} does not exist")
        sys.exit(1)
    
    branch_data = {}
    
    # Find all branch directories
    for branch_dir in base_path.iterdir():
        if not branch_dir.is_dir():
            continue
        
        branch_name = branch_dir.name
        
        branch_data[branch_name] = {
            'semgrep': load_semgrep_results(branch_dir / 'semgrep.json'),
            'gitleaks': load_gitleaks_results(branch_dir / 'gitleaks.json'),
            'codeql': load_codeql_results(branch_dir / 'codeql.sarif'),
        }
    
    return branch_data

def print_comparison(branch_data):
    """Print formatted comparison table."""
    
    if not branch_data:
        print("No branch data found!")
        return
    
    print("=" * 80)
    print("BRANCH SECURITY COMPARISON")
    print("=" * 80)
    print()
    
    # Header
    print(f"{'Branch':<20} {'Semgrep':<15} {'Secrets':<10} {'CodeQL':<15} {'Total':<10}")
    print(f"{'':20} {'(E/W/I)':<15} {'(Count)':<10} {'(E/W/N)':<15} {'Issues':<10}")
    print("-" * 80)
    
    # Sort by total issues (descending)
    branch_totals = {}
    for branch, data in branch_data.items():
        semgrep = data['semgrep']
        codeql = data['codeql']
        gitleaks = data['gitleaks']
        
        total = (
            semgrep.get('ERROR', 0) + semgrep.get('WARNING', 0) + semgrep.get('INFO', 0) +
            codeql.get('error', 0) + codeql.get('warning', 0) + codeql.get('note', 0) +
            gitleaks
        )
        branch_totals[branch] = total
    
    sorted_branches = sorted(branch_totals.items(), key=lambda x: x[1], reverse=True)
    
    # Print each branch
    for branch, total in sorted_branches:
        data = branch_data[branch]
        
        semgrep = data['semgrep']
        semgrep_str = f"{semgrep.get('ERROR', 0)}/{semgrep.get('WARNING', 0)}/{semgrep.get('INFO', 0)}"
        
        codeql = data['codeql']
        codeql_str = f"{codeql.get('error', 0)}/{codeql.get('warning', 0)}/{codeql.get('note', 0)}"
        
        gitleaks = data['gitleaks']
        
        print(f"{branch:<20} {semgrep_str:<15} {gitleaks:<10} {codeql_str:<15} {total:<10}")
    
    print()
    print("=" * 80)
    print("LEGEND")
    print("=" * 80)
    print("Semgrep: E/W/I = Error/Warning/Info")
    print("CodeQL:  E/W/N = Error/Warning/Note")
    print("Secrets: Count of hardcoded secrets found")
    print()
    
    # Show most vulnerable branch
    if sorted_branches:
        worst_branch = sorted_branches[0][0]
        worst_count = sorted_branches[0][1]
        print(f"⚠️  Most vulnerable branch: {worst_branch} ({worst_count} total issues)")
        
        if len(sorted_branches) > 1:
            best_branch = sorted_branches[-1][0]
            best_count = sorted_branches[-1][1]
            print(f"✅ Cleanest branch: {best_branch} ({best_count} total issues)")

if __name__ == '__main__':
    if len(sys.argv) != 2:
        print("Usage: compare-branches <results-directory>")
        print()
        print("Example:")
        print("  compare-branches /scan/results/weekly-scan-20260206")
        sys.exit(1)
    
    results_dir = sys.argv[1]
    branch_data = analyze_branch_results(results_dir)
    print_comparison(branch_data)
