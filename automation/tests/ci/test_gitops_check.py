import importlib.util
from pathlib import Path
import tempfile
import unittest

import yaml

SCRIPT = Path(__file__).resolve().parents[2] / "scripts/ci/gitops-check.py"
spec = importlib.util.spec_from_file_location("gitops_check", SCRIPT)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class GitOpsTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.app = {
            "apiVersion": "argoproj.io/v1alpha1", "kind": "Application",
            "metadata": {"name": "demo", "namespace": "argocd"},
            "spec": {"source": {"repoURL": module.REPO_URL,
                                "targetRevision": "HEAD", "path": "manifests/apps/demo"}},
        }
        self.write("manifests/apps/demo/kustomization.yaml", {"resources": []})
        self.write("manifests/bootstrap/applications/kustomization.yaml", {"resources": ["demo.yaml"]})
        self.save_app()

    def write(self, name, data):
        path = self.root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(yaml.safe_dump(data))

    def save_app(self):
        self.write("manifests/bootstrap/applications/demo.yaml", self.app)

    def check_error(self, expected):
        self.save_app()
        self.assertTrue(any(expected in issue for issue in module.check(self.root)), expected)

    def test_valid(self):
        self.assertEqual(module.check(self.root), [])

    def test_missing_source(self):
        self.app["spec"]["source"]["path"] = "manifests/apps/typo"
        self.check_error("source path does not exist")

    def test_path_escape(self):
        self.app["spec"]["source"]["path"] = "../"
        self.check_error("source path does not exist inside repository")

    def test_revision_including_multisource(self):
        source = self.app["spec"].pop("source")
        source["targetRevision"] = "develop"
        self.app["spec"]["sources"] = [source]
        self.check_error("targetRevision must be HEAD")

    def test_missing_kustomization(self):
        (self.root / "manifests/apps/demo/kustomization.yaml").unlink()
        self.check_error("source has no Kustomization")

    def test_unregistered_application(self):
        self.write("manifests/bootstrap/applications/kustomization.yaml", {"resources": []})
        self.check_error("not included in bootstrap")

    def test_unowned_workload(self):
        self.write("manifests/apps/orphan/kustomization.yaml", {"resources": []})
        self.check_error("no bootstrap Application owns this app")

    def test_directory_include(self):
        self.app["spec"]["source"]["directory"] = {"include": "resource.yaml"}
        self.check_error("directory.include file is missing")
        self.write("manifests/apps/demo/resource.yaml", {"kind": "ConfigMap"})
        self.assertEqual(module.check(self.root), [])

    def test_unsupported_include_fails_closed(self):
        self.app["spec"]["source"]["directory"] = {"include": "*.yaml"}
        self.check_error("one explicit YAML file")

    def test_external_helm_source(self):
        self.app["spec"]["sources"] = [self.app["spec"].pop("source"),
                                        {"repoURL": "https://charts.example.com", "chart": "example", "targetRevision": "1.0"}]
        self.save_app()
        self.assertEqual(module.check(self.root), [])

    def test_failed_bootstrap_render(self):
        self.write("manifests/bootstrap/applications/kustomization.yaml", {"resources": ["missing.yaml"]})
        self.check_error("bootstrap render failed")


if __name__ == "__main__":
    unittest.main()
