"""重要な許可／拒否経路を、全ポリシーの和集合で回帰検証する。"""
import ipaddress
from pathlib import Path
import unittest

import yaml

ROOT = Path(__file__).resolve().parents[3]
POLICIES = list(yaml.safe_load_all((ROOT / 'manifests/core/workload-networkpolicies.yaml').read_text()))


def matches(selector, labels):
    return all(labels.get(k) == v for k, v in selector.get('matchLabels', {}).items()) and all(
        labels.get(expr['key']) in expr['values'] for expr in selector.get('matchExpressions', []))


def allowed(namespace, labels, direction, remote_ns, remote_labels, ip, port, protocol='TCP'):
    selected = [p['spec'] for p in POLICIES if p['metadata']['namespace'] == namespace
                and matches(p['spec']['podSelector'], labels) and direction in p['spec']['policyTypes']]
    if not selected:
        return True
    for spec in selected:
        for rule in spec.get(direction.lower(), []):
            if not any(p.get('protocol', 'TCP') == protocol and p['port'] <= port <= p.get('endPort', p['port'])
                       for p in rule['ports']):
                continue
            for peer in rule['to' if direction == 'Egress' else 'from']:
                if 'ipBlock' in peer:
                    block = peer['ipBlock']
                    address = ipaddress.ip_address(ip)
                    if address in ipaddress.ip_network(block['cidr']) and not any(
                            address in ipaddress.ip_network(cidr) for cidr in block.get('except', [])):
                        return True
                elif matches(peer.get('namespaceSelector', {'matchLabels': {'kubernetes.io/metadata.name': namespace}}),
                             {'kubernetes.io/metadata.name': remote_ns}) and matches(peer.get('podSelector', {}), remote_labels):
                    return True
    return False


class NetworkPolicyTests(unittest.TestCase):
    def test_unlabelled_apps_cannot_reach_lan_or_internet(self):
        for ns in ['sandbox', 'tools', 'arc-runners']:
            for ip in ['192.168.122.10', '192.168.10.4', '1.1.1.1']:
                self.assertFalse(allowed(ns, {}, 'Egress', '', {}, ip, 443))

    def test_web_permission_does_not_open_private_network_or_other_ports(self):
        self.assertTrue(allowed('sandbox', {'app': 'api-hub'}, 'Egress', '', {}, '1.1.1.1', 443))
        for ip, port in [('192.168.122.10', 443), ('169.254.169.254', 80), ('1.1.1.1', 22)]:
            self.assertFalse(allowed('sandbox', {'app': 'api-hub'}, 'Egress', '', {}, ip, port))

    def test_only_arc_control_components_can_reach_api(self):
        for ip, port in [('10.96.0.1', 443), ('192.168.122.10', 6443)]:
            self.assertFalse(allowed('arc-systems', {'app.kubernetes.io/component': 'runner'}, 'Egress', '', {}, ip, port))
            for labels in [{'app.kubernetes.io/name': 'gha-rs-controller'},
                           {'app.kubernetes.io/component': 'runner-scale-set-listener'}]:
                self.assertTrue(allowed('arc-systems', labels, 'Egress', '', {}, ip, port))

    def test_webdriver_and_cache_require_correct_client(self):
        for src, dstns, dst, port in [('hitomi-monitor', 'tools', 'selenium-standalone-chrome', 4444),
                                    ('rsshub', 'sandbox', 'rsshub-redis', 6379)]:
            self.assertTrue(allowed('sandbox', {'app': src}, 'Egress', dstns, {'app': dst}, '10.244.1.2', port))
            self.assertTrue(allowed(dstns, {'app': dst}, 'Ingress', 'sandbox', {'app': src}, '10.244.1.3', port))
            self.assertFalse(allowed(dstns, {'app': dst}, 'Ingress', 'sandbox', {'app': 'unrelated'}, '10.244.1.3', port))

    def test_harbor_gateway_reaches_route_backends_only(self):
        gateway = {'app.kubernetes.io/name': 'nginx-gateway-nginx',
                   'gateway.networking.k8s.io/gateway-name': 'nginx-gateway'}
        for component in ['core', 'portal']:
            self.assertTrue(allowed('harbor', {'app': 'harbor', 'component': component},
                                    'Ingress', 'nginx-gateway', gateway, '10.244.1.2', 8080))
        for component in ['redis', 'registry', 'jobservice']:
            self.assertFalse(allowed('harbor', {'app': 'harbor', 'component': component},
                                     'Ingress', 'nginx-gateway', gateway, '10.244.1.2', 8080))

    def test_gateway_requires_both_namespace_and_labels(self):
        labels = {'app.kubernetes.io/name': 'nginx-gateway-nginx',
                  'gateway.networking.k8s.io/gateway-name': 'nginx-gateway'}
        self.assertTrue(allowed('sandbox', {'app': 'api-hub'}, 'Ingress', 'nginx-gateway', labels, '10.244.1.2', 3000))
        self.assertFalse(allowed('sandbox', {'app': 'api-hub'}, 'Ingress', 'sandbox', labels, '10.244.1.2', 3000))


if __name__ == '__main__':
    unittest.main()
