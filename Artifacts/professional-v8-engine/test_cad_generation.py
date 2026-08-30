#!/usr/bin/env python3
"""Independent checks for the professional V8 semantic CAD generation plan."""

from __future__ import annotations

import json
import math
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


ROOT = Path(__file__).parent
GENERATOR = ROOT / "generate_cad_artifacts.py"


class CADGenerationTests(unittest.TestCase):
    def generate(self, output: Path) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [sys.executable, str(GENERATOR), "--output-directory", str(output)],
            check=False,
            capture_output=True,
            text=True,
            timeout=20,
        )

    def test_manifest_covers_every_semantic_part_without_fallbacks(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory)
            result = self.generate(output)
            self.assertEqual(result.returncode, 0, result.stderr)
            manifest = json.loads((output / "cad-source-manifest.json").read_text())
            architecture = json.loads((ROOT / "semantic-architecture.json").read_text())
            semantic_ids = {part["partID"] for part in architecture["parts"]}
            component_ids = {component["partID"] for component in manifest["components"]}
            body_names = [component["bodyName"] for component in manifest["components"]]
            self.assertEqual(component_ids, semantic_ids)
            self.assertEqual(manifest["coveredSemanticPartCount"], len(semantic_ids))
            self.assertEqual(len(body_names), len(set(body_names)))
            self.assertLessEqual(manifest["bodyCount"], 256)
            self.assertTrue(all(component["primitive"] in ("box", "cylinder") for component in manifest["components"]))
            self.assertFalse(any("fallback" in component["role"] for component in manifest["components"]))

    def test_generated_geometry_retains_engine_dimensions_and_slider_crank_closure(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory)
            result = self.generate(output)
            self.assertEqual(result.returncode, 0, result.stderr)
            manifest = json.loads((output / "cad-source-manifest.json").read_text())
            checks = manifest["geometryChecks"]
            self.assertEqual(checks["boreMillimeters"], 86)
            self.assertEqual(checks["strokeMillimeters"], 86)
            self.assertEqual(checks["cylinderPitchMillimeters"], 96)
            self.assertEqual(checks["deckHeightMillimeters"], 224)
            self.assertEqual(checks["bankAngleDegrees"], 90)
            self.assertEqual(checks["maximumConnectingRodResidualMillimeters"], 0)
            liners = [component for component in manifest["components"] if component["role"] == "bore-volume-envelope"]
            rods = [component for component in manifest["components"] if component["role"] == "weak-axis-envelope"]
            self.assertEqual(len(liners), 8)
            self.assertEqual(len(rods), 8)
            self.assertTrue(all(component["radiusMillimeters"] == 43 for component in liners))
            self.assertTrue(all(math.isclose(component["lengthMillimeters"], 150, abs_tol=1e-9) for component in rods))

    def test_fluid_geometry_remains_explicitly_envelope_only(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory)
            result = self.generate(output)
            self.assertEqual(result.returncode, 0, result.stderr)
            manifest = json.loads((output / "cad-source-manifest.json").read_text())
            fluid_components = [
                component
                for component in manifest["components"]
                if component["category"] in ("coolant-ht", "coolant-lt", "oil", "air", "exhaust")
            ]
            self.assertTrue(fluid_components)
            self.assertTrue(all("envelope" in component["role"] for component in fluid_components))
            unsupported = " ".join(manifest["unsupportedManufacturingDetails"])
            self.assertIn("hollow coolant jackets", unsupported)
            self.assertIn("combustion chambers", unsupported)
            self.assertIn("bearing oil films", unsupported)

    def test_generation_outputs_are_deterministic(self) -> None:
        with tempfile.TemporaryDirectory() as first, tempfile.TemporaryDirectory() as second:
            first_result = self.generate(Path(first))
            second_result = self.generate(Path(second))
            self.assertEqual(first_result.returncode, 0, first_result.stderr)
            self.assertEqual(second_result.returncode, 0, second_result.stderr)
            for filename in ("create-professional-v8-batch.json", "cad-source-manifest.json", "professional-v8-preview.png"):
                self.assertEqual((Path(first) / filename).read_bytes(), (Path(second) / filename).read_bytes())


if __name__ == "__main__":
    unittest.main()
