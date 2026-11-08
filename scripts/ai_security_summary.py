#!/usr/bin/env python3
import json
import os
import sys
import requests

def parse_trivy(file_path):
    findings = []
    if not os.path.exists(file_path):
        return findings
    try:
        with open(file_path, "r") as f:
            data = json.load(f)
        for target in data.get("Results", []):
            for vuln in target.get("Vulnerabilities", []):
                # Filter for High/Critical to keep context window clean
                if vuln.get("Severity") in ["HIGH", "CRITICAL"]:
                    findings.append({
                        "stage": "SCA / Dependencies",
                        "tool": "Trivy",
                        "id": vuln.get("VulnerabilityID"),
                        "severity": vuln.get("Severity"),
                        "package": vuln.get("PkgName"),
                        "installed_version": vuln.get("InstalledVersion"),
                        "fixed_version": vuln.get("FixedVersion", "N/A"),
                        "title": vuln.get("Title") or vuln.get("Description", "")[:120]
                    })
    except Exception as e:
        print(f"[!] Warning reading Trivy report: {e}")
    return findings

def parse_checkov(file_path):
    findings = []
    if not os.path.exists(file_path):
        return findings
    try:
        with open(file_path, "r") as f:
            data = json.load(f)
        results = data if isinstance(data, list) else [data]
        for item in results:
            failed_checks = item.get("results", {}).get("failed_checks", [])
            for check in failed_checks:
                if check.get("severity") in ["HIGH", "CRITICAL", None]:
                    findings.append({
                        "stage": "IaC / Kubernetes",
                        "tool": "Checkov",
                        "id": check.get("check_id"),
                        "severity": check.get("severity", "HIGH"),
                        "target": check.get("file_path"),
                        "resource": check.get("resource"),
                        "title": check.get("check_name"),
                        "guideline": check.get("guideline", "")
                    })
    except Exception as e:
        print(f"[!] Warning reading Checkov report: {e}")
    return findings

def parse_gitleaks(file_path):
    findings = []
    if not os.path.exists(file_path):
        return findings
    try:
        with open(file_path, "r") as f:
            data = json.load(f)
        for leak in data:
            findings.append({
                "stage": "Secret Detection",
                "tool": "Gitleaks",
                "id": leak.get("RuleID"),
                "severity": "CRITICAL",
                "target": f"{leak.get('File')}:{leak.get('StartLine')}",
                "title": leak.get("Description")
            })
    except Exception as e:
        print(f"[!] Warning reading Gitleaks report: {e}")
    return findings

def parse_grype(file_path):
    findings = []
    if not os.path.exists(file_path):
        return findings
    try:
        with open(file_path, "r") as f:
            data = json.load(f)
        for match in data.get("matches", []):
            vuln = match.get("vulnerability", {})
            sev = vuln.get("severity", "UNKNOWN")
            if sev.upper() in ["HIGH", "CRITICAL"]:
                findings.append({
                    "stage": "Container Hardening",
                    "tool": "Grype",
                    "id": vuln.get("id"),
                    "severity": sev,
                    "package": match.get("artifact", {}).get("name"),
                    "installed_version": match.get("artifact", {}).get("version"),
                    "title": vuln.get("description", "")[:120]
                })
    except Exception as e:
        print(f"[!] Warning reading Grype report: {e}")
    return findings

def call_gemini_api(findings, api_key):
    prompt = f"""
You are an expert DevSecOps engineer analyzing security findings from our CI/CD pipeline for the Spring PetClinic application.

Below is a normalized JSON list of detected HIGH/CRITICAL vulnerabilities across various pipeline stages:
{json.dumps(findings, indent=2)}

Please generate a concise, human-readable report in Markdown with the following sections:
1. ### 🛡️ Executive Vulnerability Summary (High-level overview of risk posture)
2. ### 🚨 High & Critical Alerts (List CVE/Rule ID, affected file/dependency, and stage)
3. ### 🛠️ Recommended Remediation & Code Solutions (Actionable steps: exact version bumps for pom.xml, Kubernetes manifest fixes, or secrets rotation instructions)
4. ### 📋 Next Steps for Developers

Keep it clear, actionable, and formatted with clean bullet points and code blocks.
"""
    url = f"https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent?key={api_key}"
    headers = {"Content-Type": "application/json"}
    body = {
        "contents": [{"parts": [{"text": prompt}]}]
    }
    
    response = requests.post(url, headers=headers, json=body)
    if response.status_code != 200:
        raise RuntimeError(f"Gemini API request failed ({response.status_code}): {response.text}")
    
    data = response.json()
    return data["candidates"][0]["content"]["parts"][0]["text"]

def main():
    reports_dir = os.environ.get("REPORTS_DIR", "reports")
    api_key = os.environ.get("GEMINI_API_KEY")
    output_file = os.environ.get("SUMMARY_FILE", "ai-security-summary.md")

    print(f"[+] Loading scanner artifacts from: {reports_dir}")
    all_findings = []
    all_findings.extend(parse_gitleaks(os.path.join(reports_dir, "gitleaks-report.json")))
    all_findings.extend(parse_trivy(os.path.join(reports_dir, "trivy-sca-results.json")))
    all_findings.extend(parse_checkov(os.path.join(reports_dir, "checkov-results.json")))
    all_findings.extend(parse_grype(os.path.join(reports_dir, "grype-results.json")))

    if not all_findings:
        msg = "### 🛡️ AI Security Advisory\n\nNo High or Critical vulnerabilities were detected across any stage. Pipeline security gates are passing cleanly."
        with open(output_file, "w") as f:
            f.write(msg)
        print("[✓] Clean run: No findings to triage.")
        return

    print(f"[+] Found {len(all_findings)} High/Critical vulnerabilities. Normalizing...")
    # Cap at 40 findings to preserve context window if there is an alert flood
    trimmed = all_findings[:40]

    if not api_key:
        print("[!] GEMINI_API_KEY is not set. Generating fallback basic markdown summary.")
        with open(output_file, "w") as f:
            f.write(f"### 🛡️ Security Vulnerabilities Detected ({len(trimmed)} items)\n\n")
            f.write("| Tool | Stage | ID | Severity | Target |\n| --- | --- | --- | --- | --- |\n")
            for item in trimmed:
                target = item.get("package") or item.get("target") or "N/A"
                f.write(f"| {item.get('tool', 'N/A')} | {item.get('stage', 'N/A')} | {item.get('id', 'N/A')} | {item.get('severity', 'N/A')} | {target} |\n")
            f.write("\n> ℹ️ *To enable AI-driven automated analysis and remediation playbooks, add `GEMINI_API_KEY` to your pipeline secrets.*\n")
        print(f"[✓] Fallback markdown summary written to {output_file}")
        return

    print(f"[+] Requesting AI Security Advisory from Gemini API...")
    try:
        summary_markdown = call_gemini_api(trimmed, api_key)
        with open(output_file, "w") as f:
            f.write(summary_markdown)
        print(f"[✓] AI Advisory successfully generated and written to {output_file}")
    except Exception as e:
        print(f"[!] Error calling Gemini API: {e}")
        # Write basic summary if API call fails
        with open(output_file, "w") as f:
            f.write(f"### 🛡️ Security Vulnerabilities Detected ({len(trimmed)} items)\n\n")
            f.write(f"*Note: Gemini AI advisory failed ({e}). Showing raw findings list:*\n\n")
            f.write("| Tool | Stage | ID | Severity | Target |\n| --- | --- | --- | --- | --- |\n")
            for item in trimmed:
                target = item.get("package") or item.get("target") or "N/A"
                f.write(f"| {item.get('tool', 'N/A')} | {item.get('stage', 'N/A')} | {item.get('id', 'N/A')} | {item.get('severity', 'N/A')} | {target} |\n")

if __name__ == "__main__":
    main()
