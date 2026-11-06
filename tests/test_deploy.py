import gzip
import json
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


class DeployTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.site = Path(self.temp.name)
        shutil.copy2(ROOT / "Makefile", self.site / "Makefile")
        shutil.copytree(ROOT / "_template", self.site / "_template")
        (self.site / "versions.json").write_text('{"latest":"","versions":[]}')
        self.output = self.site / "output"
        self.output.mkdir()
        (self.output / "docs.json").write_text('{"index":{}}')
        for name in ("fe-web.js", "fe-highlight.css", "styles.css"):
            (self.output / name).write_text(name)

    def make(self, target, variable):
        return subprocess.run(
            ["make", target, variable, f"OUTDIR={self.output}"],
            cwd=self.site,
            capture_output=True,
            text=True,
            check=False,
        )

    def test_deploys_stable_and_prerelease_versions(self):
        for version in ("26.3.0", "26.3.1-alpha.2"):
            with self.subTest(version=version):
                result = self.make("deploy", f"VERSION={version}")
                self.assertEqual(result.returncode, 0, result.stderr)
                with gzip.open(self.site / version / "docs.json.gz", "rt") as docs:
                    self.assertEqual(json.load(docs), {"index": {}})
                self.assertIn(version, (self.site / version / "index.html").read_text())
        versions = json.loads((self.site / "versions.json").read_text())
        self.assertEqual(versions["latest"], "26.3.0")
        self.assertEqual(versions["versions"], ["26.3.0", "26.3.1-alpha.2"])

    def test_rejects_make_and_shell_substitution(self):
        marker = self.site / "executed"
        for payload in (
            f"26.3.0$(shell touch {marker})",
            f"26.3.0$(touch {marker})",
            "../escape",
        ):
            with self.subTest(payload=payload):
                result = self.make("deploy", f"VERSION={payload}")
                self.assertNotEqual(result.returncode, 0)
                self.assertFalse(marker.exists())

    def test_rejects_unsafe_tag_before_building(self):
        marker = self.site / "executed"
        tag = f"v26.3.0$(shell touch {marker})"
        for target, variable in (("build", f"TAG={tag}"), ("_build-tag", f"T={tag}")):
            with self.subTest(target=target):
                result = subprocess.run(
                    ["make", target, variable, f"FE_SRC={self.site}"],
                    cwd=self.site,
                    capture_output=True,
                    text=True,
                    check=False,
                )
                self.assertNotEqual(result.returncode, 0)
                self.assertFalse(marker.exists())


if __name__ == "__main__":
    unittest.main()
