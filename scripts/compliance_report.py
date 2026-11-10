"""Pull NIST 800-53 Rev. 5 results from AWS Security Hub and write a report.

Run from the repo's main folder:  py scripts\\compliance_report.py
Writes compliance_report.md (for GitHub) and compliance_report.csv (for Excel).
"""
import csv
from collections import defaultdict
from datetime import datetime, timezone

import boto3

NIST_STANDARD = "standards/nist-800-53/v/5.0.0"
SEVERITY_ORDER = {"CRITICAL": 0, "HIGH": 1, "MEDIUM": 2, "LOW": 3, "INFORMATIONAL": 4}

# Your account number, so it can be hidden in the report
account_id = boto3.client("sts").get_caller_identity()["Account"]


def hide_account(text):
    return text.replace(account_id, "ACCOUNT_ID")


client = boto3.client("securityhub", region_name="us-east-1")
filters = {
    "ComplianceAssociatedStandardsId": [{"Value": NIST_STANDARD, "Comparison": "EQUALS"}],
    "RecordState": [{"Value": "ACTIVE", "Comparison": "EQUALS"}],
    "WorkflowStatus": [{"Value": "SUPPRESSED", "Comparison": "NOT_EQUALS"}],
}

findings = []
for page in client.get_paginator("get_findings").paginate(
    Filters=filters, PaginationConfig={"PageSize": 100}
):
    for f in page["Findings"]:
        comp = f.get("Compliance", {})
        nist = [
            r.replace("NIST.800-53.r5 ", "")
            for r in comp.get("RelatedRequirements", [])
            if r.startswith("NIST.800-53.r5")
        ]
        findings.append({
            "check": comp.get("SecurityControlId", "unknown"),
            "status": comp.get("Status", "NOT_AVAILABLE"),
            "severity": f.get("Severity", {}).get("Label", ""),
            "title": f.get("Title", ""),
            "resource": hide_account(f["Resources"][0]["Id"]),
            "nist": nist,
        })

# A check passes only if every resource it looked at passed.
checks = defaultdict(set)
for f in findings:
    checks[f["check"]].add(f["status"])
passed = [c for c, s in checks.items() if s == {"PASSED"}]
score = round(100 * len(passed) / len(checks)) if checks else 0

# Group by NIST control, for example AU-9 or SC-7
by_control = defaultdict(lambda: {"PASSED": 0, "FAILED": 0})
for f in findings:
    for ctrl in f["nist"]:
        if f["status"] in ("PASSED", "FAILED"):
            by_control[ctrl][f["status"]] += 1

failed = sorted(
    (f for f in findings if f["status"] == "FAILED"),
    key=lambda x: (SEVERITY_ORDER.get(x["severity"], 9), x["check"]),
)

now = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M UTC")
lines = [
    "# NIST 800-53 Rev. 5 Compliance Report",
    "",
    f"Generated {now} from AWS Security Hub. Account numbers are replaced with ACCOUNT_ID.",
    "",
    f"**Score: {score}%** ({len(passed)} of {len(checks)} automated checks passing)",
    "",
    "## Failed checks, most severe first",
    "",
    "| Severity | Check | NIST controls | Resource |",
    "| --- | --- | --- | --- |",
]
for f in failed:
    lines.append(f"| {f['severity']} | {f['check']}: {f['title']} | {', '.join(f['nist'])} | `{f['resource']}` |")

lines += ["", "## Results by NIST control", "", "| NIST control | Passed | Failed |", "| --- | --- | --- |"]
for ctrl in sorted(by_control):
    r = by_control[ctrl]
    lines.append(f"| {ctrl} | {r['PASSED']} | {r['FAILED']} |")

with open("compliance_report.md", "w", encoding="utf-8") as out:
    out.write("\n".join(lines) + "\n")

with open("compliance_report.csv", "w", newline="", encoding="utf-8") as out:
    writer = csv.writer(out)
    writer.writerow(["severity", "check", "status", "nist_controls", "resource", "title"])
    for f in sorted(findings, key=lambda x: (SEVERITY_ORDER.get(x["severity"], 9), x["check"])):
        writer.writerow([f["severity"], f["check"], f["status"], " ".join(f["nist"]), f["resource"], f["title"]])

print(f"Score: {score}% ({len(passed)}/{len(checks)} checks). Wrote compliance_report.md and compliance_report.csv")
print("")
print("Most severe failed checks:")
for f in failed[:10]:
    print(f"  {f['severity']:<9} {f['check']:<16} {f['title'][:70]}")
