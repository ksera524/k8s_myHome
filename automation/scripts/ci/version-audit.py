#!/usr/bin/env python3

from __future__ import annotations

import json
import os
import re
import subprocess
from pathlib import Path
from typing import Any

import yaml
from packaging.version import InvalidVersion, Version


ROOT = Path(__file__).resolve().parents[3]
SUMMARY_PATH = ROOT / "weekly-version-audit-summary.md"
ISSUE_PATH = ROOT / "weekly-version-audit-issue.md"


def run(cmd: list[str]) -> str:
    proc = subprocess.run(cmd, capture_output=True, text=True, check=False)
    if proc.returncode != 0:
        raise RuntimeError(f"command failed: {' '.join(cmd)}\n{proc.stderr}")
    return proc.stdout.strip()


def maybe_run(cmd: list[str]) -> tuple[bool, str, str]:
    proc = subprocess.run(cmd, capture_output=True, text=True, check=False)
    return proc.returncode == 0, proc.stdout.strip() if proc.stdout else "", proc.stderr.strip() if proc.stderr else ""


def norm(version: str) -> str:
    return version.strip().strip('"').strip("'")


def semver_key(version: str) -> Version:
    value = norm(version)
    if value.startswith("v"):
        value = value[1:]
    return Version(value)


def is_semver(version: str) -> bool:
    return bool(re.match(r"^v?\d+\.\d+\.\d+$", norm(version)))


def compare(current: str, latest: str) -> str:
    if not latest:
        return "unknown"
    try:
        current_version = semver_key(current)
        latest_version = semver_key(latest)
    except InvalidVersion:
        return "unknown"
    if current_version < latest_version:
        return "update-available"
    if current_version == latest_version:
        return "up-to-date"
    return "ahead"


def helm_latest(repo_chart: str) -> str:
    data = json.loads(run(["helm", "search", "repo", repo_chart, "--versions", "-o", "json"]))
    versions = [item["version"] for item in data if "version" in item]
    stable = [version for version in versions if is_semver(version) and "-" not in norm(version)]
    if stable:
        return str(max(stable, key=semver_key))
    if versions:
        return versions[0]
    return ""


def crane_latest(repo: str) -> str:
    tags = [tag for tag in run(["crane", "ls", repo]).splitlines() if tag]
    stable = [tag for tag in tags if is_semver(tag)]
    if stable:
        return str(max(stable, key=semver_key))
    return ""


def load_yaml(path: Path) -> Any:
    return yaml.safe_load(path.read_text(encoding="utf-8"))


def load_child_apps() -> dict[str, dict[str, Any]]:
    apps: dict[str, dict[str, Any]] = {}
    app_root = ROOT / "manifests/bootstrap/applications"
    for path in sorted(app_root.rglob("*.yaml")):
        if path.name == "kustomization.yaml":
            continue
        with path.open(encoding="utf-8") as f:
            docs = [doc for doc in yaml.safe_load_all(f) if isinstance(doc, dict)]
        for doc in docs:
            if doc.get("kind") != "Application":
                continue
            name = doc.get("metadata", {}).get("name")
            if name:
                apps[name] = {
                    "doc": doc,
                    "path": path.relative_to(ROOT).as_posix(),
                }
    return apps


def find_app(apps: dict[str, dict[str, Any]], name: str) -> tuple[dict[str, Any], str]:
    app = apps.get(name)
    if app is None:
        raise RuntimeError(f"Application not found: {name}")
    return app["doc"], app["path"]


def load_kustomization(path_str: str) -> dict[str, Any]:
    return load_yaml(ROOT / path_str / "kustomization.yaml")


def first_helm_chart(kustomization: dict[str, Any]) -> dict[str, Any]:
    charts = kustomization.get("helmCharts") or []
    if not charts:
        raise RuntimeError("helmCharts entry not found")
    return charts[0]


def add_helm_repos() -> None:
    repos = {
        "nfs-subdir": "https://kubernetes-sigs.github.io/nfs-subdir-external-provisioner",
        "metallb": "https://metallb.github.io/metallb",
        "jetstack": "https://charts.jetstack.io",
        "external-secrets": "https://charts.external-secrets.io",
        "tailscale": "https://pkgs.tailscale.com/helmcharts",
        "harbor": "https://helm.goharbor.io",
        "rustfs": "https://charts.rustfs.com",
    }
    for alias, url in repos.items():
        maybe_run(["helm", "repo", "add", alias, url])
    run(["helm", "repo", "update"])


def collect_checks() -> list[dict[str, str]]:
    child_apps = load_child_apps()
    add_helm_repos()
    checks: list[dict[str, str]] = []

    chart_targets = [
        ("nfs-subdir-external-provisioner", "NFS Subdir External Provisioner", "nfs-subdir/nfs-subdir-external-provisioner"),
        ("metallb", "MetalLB", "metallb/metallb"),
        ("cert-manager", "cert-manager", "jetstack/cert-manager"),
        ("external-secrets-operator", "external-secrets", "external-secrets/external-secrets"),
        ("tailscale-operator", "tailscale-operator", "tailscale/tailscale-operator"),
    ]
    for app_name, label, repo_chart in chart_targets:
        app, app_path = find_app(child_apps, app_name)
        current = str(app["spec"]["source"]["targetRevision"])
        latest = helm_latest(repo_chart)
        checks.append({
            "component": label,
            "kind": "helm-chart",
            "current": current,
            "latest": latest,
            "status": compare(current, latest),
            "ref": repo_chart,
            "path": app_path,
        })

    wrapper_targets = [
        ("harbor", "Harbor", "harbor/harbor"),
        ("rustfs", "RustFS", "rustfs/rustfs"),
    ]
    for app_name, label, repo_chart in wrapper_targets:
        app, _ = find_app(child_apps, app_name)
        source_path = app["spec"]["source"]["path"]
        chart = first_helm_chart(load_kustomization(source_path))
        current = str(chart["version"])
        latest = helm_latest(repo_chart)
        checks.append({
            "component": label,
            "kind": "helm-chart",
            "current": current,
            "latest": latest,
            "status": compare(current, latest),
            "ref": repo_chart,
            "path": f"{source_path}/kustomization.yaml",
        })

    arc_doc = load_yaml(ROOT / "manifests/platform/ci-cd/github-actions/arc-controller.yaml")
    arc_current = str(arc_doc["spec"]["source"]["targetRevision"])
    arc_latest = crane_latest("ghcr.io/actions/gha-runner-scale-set-controller")
    checks.append({
        "component": "ARC Controller",
        "kind": "oci-chart",
        "current": arc_current,
        "latest": arc_latest,
        "status": compare(arc_current, arc_latest),
        "ref": "ghcr.io/actions/gha-runner-scale-set-controller",
        "path": "manifests/platform/ci-cd/github-actions/arc-controller.yaml",
    })

    appset_doc = load_yaml(ROOT / "manifests/platform/ci-cd/github-actions/runners-appset.yaml")
    runner_current = str(appset_doc["spec"]["template"]["spec"]["source"]["targetRevision"])
    consistency_status = "up-to-date" if norm(runner_current) == norm(arc_current) else "mismatch"
    checks.append({
        "component": "ARC Controller/Runner consistency",
        "kind": "consistency",
        "current": f"controller={arc_current}, runner={runner_current}",
        "latest": "-",
        "status": consistency_status,
        "ref": "arc-controller.yaml / runners-appset.yaml",
        "path": "manifests/platform/ci-cd/github-actions/",
    })

    lpp_text = (ROOT / "manifests/infrastructure/storage/local-path/local-path-provisioner.yaml").read_text(encoding="utf-8")
    match = re.search(r"image:\s*rancher/local-path-provisioner:([^\s]+)", lpp_text)
    lpp_current = match.group(1) if match else ""
    lpp_latest = crane_latest("rancher/local-path-provisioner") if lpp_current else ""
    checks.append({
        "component": "local-path-provisioner image",
        "kind": "container-image",
        "current": lpp_current,
        "latest": lpp_latest,
        "status": compare(lpp_current, lpp_latest) if lpp_current else "unknown",
        "ref": "rancher/local-path-provisioner",
        "path": "manifests/infrastructure/storage/local-path/local-path-provisioner.yaml",
    })

    cloudflared_text = (ROOT / "manifests/access/cloudflared/manifest.yaml").read_text(encoding="utf-8")
    cloud_match = re.search(r"image:\s*cloudflare/cloudflared:([^\s]+)", cloudflared_text)
    cloud_tag = cloud_match.group(1) if cloud_match else ""
    cloud_digest = ""
    if cloud_tag:
        ok, out, _ = maybe_run(["crane", "digest", f"cloudflare/cloudflared:{cloud_tag}"])
        cloud_digest = out if ok else ""
    checks.append({
        "component": "cloudflared image",
        "kind": "container-image",
        "current": cloud_tag,
        "latest": cloud_tag,
        "status": "tracked-by-digest",
        "ref": "cloudflare/cloudflared",
        "path": "manifests/access/cloudflared/manifest.yaml",
        "note": f"digest={cloud_digest}" if cloud_digest else "digest unavailable",
    })

    return checks


def build_summary(checks: list[dict[str, str]], updates: list[dict[str, str]], guard_issues: list[dict[str, str]]) -> list[str]:
    lines = [
        "## Weekly Version Audit",
        "",
        "| Component | Type | Current | Latest | Status | Reference |",
        "|---|---|---|---|---|---|",
    ]
    for check in checks:
        ref = check["ref"].replace("|", "\\|")
        lines.append(f"| {check['component']} | {check['kind']} | `{check['current']}` | `{check['latest']}` | `{check['status']}` | `{ref}` |")
    lines.append("")
    lines.append(f"- updates found: **{len(updates)}**")
    lines.append(f"- consistency issues found: **{len(guard_issues)}**")
    for check in checks:
        if check.get("note"):
            lines.append(f"- note `{check['component']}`: {check['note']}")
    return lines


def build_issue(updates: list[dict[str, str]], guard_issues: list[dict[str, str]]) -> list[str]:
    lines = ["## Weekly Version Audit: updates available", ""]
    if updates or guard_issues:
        lines.extend([
            "| Component | Current | Latest | Type | Path |",
            "|---|---|---|---|---|",
        ])
        for check in updates + guard_issues:
            lines.append(f"| {check['component']} | `{check['current']}` | `{check['latest']}` | {check['kind']} | `{check['path']}` |")
        lines.extend([
            "",
            "### Next actions",
            "- 1) バージョン更新PRを作成",
            "- 2) `make bootstrap` と `make phase5` で検証",
            "- 3) ArgoCDが `Synced/Healthy` であることを確認",
        ])
    else:
        lines.append("No updates found in this run.")
    return lines


def write_outputs(summary_lines: list[str], issue_lines: list[str], updates_found: str) -> None:
    SUMMARY_PATH.write_text("\n".join(summary_lines) + "\n", encoding="utf-8")
    ISSUE_PATH.write_text("\n".join(issue_lines) + "\n", encoding="utf-8")

    github_summary = os.environ.get("GITHUB_STEP_SUMMARY")
    if github_summary:
        with open(github_summary, "a", encoding="utf-8") as f:
            f.write("\n".join(summary_lines) + "\n")

    github_output = os.environ.get("GITHUB_OUTPUT")
    if github_output:
        with open(github_output, "a", encoding="utf-8") as f:
            f.write(f"updates_found={updates_found}\n")


def main() -> int:
    checks = collect_checks()
    updates = [check for check in checks if check["status"] == "update-available"]
    guard_issues = [check for check in checks if check["status"] == "mismatch"]
    updates_found = "true" if updates or guard_issues else "false"

    summary_lines = build_summary(checks, updates, guard_issues)
    issue_lines = build_issue(updates, guard_issues)
    write_outputs(summary_lines, issue_lines, updates_found)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
