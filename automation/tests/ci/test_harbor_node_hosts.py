"""ノードの既存 hosts を壊さずに Harbor の外部経路を除去する回帰テスト。"""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[3]
SCRIPT = ROOT / "manifests/access/harbor/scripts/reconcile-hosts.sh"
EXPECTED = "192.168.122.100 harbor.qroksera.com harbor.internal.qroksera.com # managed: harbor-node-hosts"


class HarborNodeHostsTests(unittest.TestCase):
    def test_conflicts_aliases_comments_and_idempotence(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "hosts"
            path.write_text(
                "127.0.0.1 localhost\n"
                "# harbor.qroksera.com is managed separately\n"
                "104.21.48.44 harbor.qroksera.com another-host # keep this alias\n"
                "::1 harbor.internal.qroksera.com\n"
                "192.168.122.99 harbor.qroksera.com\n"
                "192.168.122.20 unrelated-harbor.qroksera.com\n"
            )
            inode = path.stat().st_ino
            env = {**os.environ, "HOSTS_FILE": str(path), "RECONCILE_ONCE": "true"}
            subprocess.run(["sh", str(SCRIPT)], env=env, check=True, capture_output=True)
            actual = path.read_text()
            self.assertIn("127.0.0.1 localhost\n", actual)
            self.assertIn("104.21.48.44 another-host # keep this alias\n", actual)
            self.assertIn("192.168.122.20 unrelated-harbor.qroksera.com\n", actual)
            self.assertIn("# harbor.qroksera.com is managed separately\n", actual)
            self.assertNotIn("::1", actual)
            self.assertNotIn("192.168.122.99", actual)
            self.assertEqual(actual.splitlines()[-1], EXPECTED)
            self.assertEqual(path.stat().st_ino, inode)
            result = subprocess.run(["sh", str(SCRIPT)], env=env, check=True, capture_output=True)
            self.assertEqual(result.stdout, b"")
            self.assertEqual(path.read_text(), actual)


if __name__ == "__main__":
    unittest.main()
