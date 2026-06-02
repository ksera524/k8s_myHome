#!/usr/bin/env python3

from __future__ import annotations

import sys
from pathlib import Path

import yaml


ROOT = Path(__file__).resolve().parents[3]
ACCESS_CONTRACT = ROOT / "manifests/contracts/home-lab/access-surfaces.yaml"
CLUSTER_CONTRACT = ROOT / "manifests/contracts/home-lab/cluster-contract.yaml"
ACCESS_DIR = ROOT / "manifests/access"


def load_yaml(path: Path):
    with path.open(encoding="utf-8") as f:
        return yaml.safe_load(f)


def load_docs(path: Path):
    with path.open(encoding="utf-8") as f:
        return [doc for doc in yaml.safe_load_all(f) if isinstance(doc, dict)]


def fail(issues: list[str], message: str) -> None:
    issues.append(message)


def hostnames_from_block_text(text: str) -> set[str]:
    hosts: set[str] = set()
    for line in text.splitlines():
        stripped = line.strip()
        if stripped.startswith("- hostname:"):
            hosts.add(stripped.split(":", 1)[1].strip())
        elif stripped and not stripped.startswith("#"):
            parts = stripped.split()
            if len(parts) >= 2 and parts[0].count(".") == 3:
                hosts.update(parts[1:])
    return hosts


def main() -> int:
    issues: list[str] = []

    if not ACCESS_CONTRACT.exists():
        fail(issues, f"missing access contract: {ACCESS_CONTRACT}")
    if not CLUSTER_CONTRACT.exists():
        fail(issues, f"missing cluster contract: {CLUSTER_CONTRACT}")
    if issues:
        for issue in issues:
            print(f"[NG] {issue}", file=sys.stderr)
        return 1

    access_contract = load_yaml(ACCESS_CONTRACT)
    cluster_contract = load_yaml(CLUSTER_CONTRACT)
    surfaces = access_contract["spec"]["surfaces"]
    gateway_ip = cluster_contract["spec"]["network"]["serviceIPs"]["gateway"]
    tailscale_split_dns_ip = cluster_contract["spec"]["network"]["serviceIPs"]["tailscaleSplitDNS"]
    tunnel_id = access_contract["spec"]["shared"]["cloudflared"]["tunnelId"]

    annotated_surfaces: set[str] = set()

    for path in sorted(ACCESS_DIR.rglob("*.yaml")):
        if path.name == "kustomization.yaml":
            continue
        for doc in load_docs(path):
            kind = doc.get("kind")
            meta = doc.get("metadata", {})
            annotations = meta.get("annotations", {}) or {}
            surface_id = annotations.get("contracts.k8s-myhome.local/access-surface")
            if kind != "HTTPRoute" or not surface_id:
                continue

            rel = path.relative_to(ROOT)
            annotated_surfaces.add(surface_id)
            surface = surfaces.get(surface_id)
            if not surface:
                fail(issues, f"{rel}: unknown access surface annotation: {surface_id}")
                continue

            expected_hostname = surface["hostname"]
            actual_hostnames = set(doc.get("spec", {}).get("hostnames") or [])
            if actual_hostnames != {expected_hostname}:
                fail(issues, f"{rel}: {meta.get('name')} hostnames {sorted(actual_hostnames)} != {expected_hostname}")

            parent_refs = doc.get("spec", {}).get("parentRefs") or []
            section_names = {ref.get("sectionName") for ref in parent_refs if ref.get("sectionName")}
            allowed_sections = {"http", surface["gatewayListener"]}
            if not section_names or not section_names <= allowed_sections:
                fail(issues, f"{rel}: {meta.get('name')} sectionName {sorted(section_names)} not in {sorted(allowed_sections)}")

            backend_refs = []
            for rule in doc.get("spec", {}).get("rules") or []:
                backend_refs.extend(rule.get("backendRefs") or [])
            if backend_refs:
                backend_names = {ref.get("name") for ref in backend_refs if ref.get("name")}
                expected_backend = surface["backend"]["service"]
                if expected_backend not in backend_names:
                    fail(issues, f"{rel}: {meta.get('name')} backendRefs {sorted(backend_names)} missing {expected_backend}")

    for surface_id in surfaces:
        if surface_id not in annotated_surfaces:
            fail(issues, f"access surface has no annotated HTTPRoute: {surface_id}")

    gateway_doc = load_docs(ACCESS_DIR / "gateway/gateway.yaml")[0]
    listeners = gateway_doc.get("spec", {}).get("listeners") or []
    listener_hosts = {listener.get("name"): listener.get("hostname") for listener in listeners}
    for surface_id, surface in surfaces.items():
        listener = surface["gatewayListener"]
        hostname = surface["hostname"]
        if listener == "https-internal":
            expected = "*.internal.qroksera.com"
        else:
            expected = hostname
        if listener_hosts.get(listener) != expected:
            fail(issues, f"gateway listener {listener} hostname {listener_hosts.get(listener)} != {expected} ({surface_id})")

    cloudflared_docs = load_docs(ACCESS_DIR / "cloudflared/cloudflared-config.yaml")
    cloudflared = cloudflared_docs[0]
    cloud_config = cloudflared.get("data", {}).get("config.yml", "")
    if f"tunnel: {tunnel_id}" not in cloud_config:
        fail(issues, "cloudflared tunnel ID does not match access contract")
    cloud_hosts = hostnames_from_block_text(cloud_config)
    expected_cloud_hosts = {s["hostname"] for s in surfaces.values() if s["publish"].get("cloudflared")}
    if cloud_hosts != expected_cloud_hosts:
        fail(issues, f"cloudflared hosts {sorted(cloud_hosts)} != {sorted(expected_cloud_hosts)}")

    coredns = load_docs(ACCESS_DIR / "dns/core/coredns-configmap.yaml")[0]
    corefile = coredns.get("data", {}).get("Corefile", "")
    expected_core_hosts = {s["hostname"] for s in surfaces.values() if s["publish"].get("coreDNS")}
    core_hosts = hostnames_from_block_text(corefile)
    if core_hosts != expected_core_hosts:
        fail(issues, f"CoreDNS hosts {sorted(core_hosts)} != {sorted(expected_core_hosts)}")
    for host in expected_core_hosts:
        if f"{gateway_ip} {host}" not in corefile:
            fail(issues, f"CoreDNS host {host} does not use gateway IP {gateway_ip}")

    tailscale_docs = load_docs(ACCESS_DIR / "dns/tailscale/manifest.yaml")
    tailscale_config = next(doc for doc in tailscale_docs if doc.get("kind") == "ConfigMap")
    tailscale_corefile = tailscale_config.get("data", {}).get("Corefile", "")
    expected_ts_hosts = {s["hostname"] for s in surfaces.values() if s["publish"].get("tailscaleSplitDNS")}
    ts_hosts = hostnames_from_block_text(tailscale_corefile)
    if ts_hosts != expected_ts_hosts:
        fail(issues, f"Tailscale Split DNS hosts {sorted(ts_hosts)} != {sorted(expected_ts_hosts)}")
    for host in expected_ts_hosts:
        if f"{gateway_ip} {host}" not in tailscale_corefile:
            fail(issues, f"Tailscale Split DNS host {host} does not use gateway IP {gateway_ip}")

    tailscale_service = next(doc for doc in tailscale_docs if doc.get("kind") == "Service")
    actual_lb_ip = tailscale_service.get("spec", {}).get("loadBalancerIP")
    if actual_lb_ip != tailscale_split_dns_ip:
        fail(issues, f"Tailscale Split DNS loadBalancerIP {actual_lb_ip} != {tailscale_split_dns_ip}")

    if issues:
        for issue in issues:
            print(f"[NG] {issue}", file=sys.stderr)
        return 1

    print("[OK] access manifests match home-lab contracts")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
