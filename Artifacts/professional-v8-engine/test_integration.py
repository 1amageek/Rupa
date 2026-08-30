#!/usr/bin/env python3
"""Independent cumulative checks for the professional V8 artifact set."""

from __future__ import annotations

import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest


ROOT = Path(__file__).parent
VERIFIER = ROOT / "verify_integration.py"
REPOSITORY = ROOT.parents[1]
CLI = REPOSITORY / "RupaKit/.build/out/Products/Debug/rupa"


class IntegrationEvidenceTests(unittest.TestCase):
    def run_verifier(self, root: Path, output: Path) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [sys.executable, str(VERIFIER), "--root", str(root), "--repository", str(REPOSITORY), "--cli", str(CLI), "--output", str(output)],
            check=False,
            capture_output=True,
            text=True,
            timeout=20,
        )

    def test_cumulative_report_preserves_p2_claim_and_production_rejection(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "report.json"
            result = self.run_verifier(ROOT, output)
            self.assertEqual(result.returncode, 0, result.stderr)
            report = json.loads(output.read_text())
            self.assertEqual(report["claimLevel"], "P2-engineering-reference")
            self.assertIn("production-release-rejected", report["status"])
            self.assertEqual(report["thermalEvidence"]["heatClosureErrorWatts"], 0)
            self.assertEqual(report["cadEvidence"]["semanticParts"], 168)
            self.assertEqual(report["cadEvidence"]["sourceBodies"], 202)
            self.assertGreaterEqual(len(report["openProductionReleaseGates"]), 10)

    def test_cumulative_report_is_deterministic(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            first = Path(directory) / "first.json"
            second = Path(directory) / "second.json"
            first_result = self.run_verifier(ROOT, first)
            second_result = self.run_verifier(ROOT, second)
            self.assertEqual(first_result.returncode, 0, first_result.stderr)
            self.assertEqual(second_result.returncode, 0, second_result.stderr)
            self.assertEqual(first.read_bytes(), second.read_bytes())

    def test_modified_native_artifact_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            copy_root = Path(directory) / "artifact"
            shutil.copytree(ROOT, copy_root)
            with (copy_root / "professional-v8.swcad").open("ab") as artifact:
                artifact.write(b"stale")
            output = Path(directory) / "report.json"
            result = self.run_verifier(copy_root, output)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("native CAD artifact is stale", result.stderr)
            self.assertFalse(output.exists())


if __name__ == "__main__":
    unittest.main()
