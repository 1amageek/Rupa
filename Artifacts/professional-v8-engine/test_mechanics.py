#!/usr/bin/env python3
"""Independent checks for generated professional V8 mechanical evidence."""

from __future__ import annotations

import copy
import hashlib
import json
import math
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


ROOT = Path(__file__).parent
CALCULATOR = ROOT / "calculate_mechanics.py"
REQUIREMENTS = ROOT / "requirements.json"
THERMAL = ROOT / "analysis-thermal.json"


class MechanicalEvidenceTests(unittest.TestCase):
    def run_calculator(self, requirements: Path, thermal: Path, output: Path) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [sys.executable, str(CALCULATOR), "--requirements", str(requirements), "--thermal-analysis", str(thermal), "--output-directory", str(output)],
            check=False,
            capture_output=True,
            text=True,
            timeout=10,
        )

    def test_report_independently_closes_geometry_and_loads(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory)
            result = self.run_calculator(REQUIREMENTS, THERMAL, output)
            self.assertEqual(result.returncode, 0, result.stderr)
            requirements = json.loads(REQUIREMENTS.read_text())
            report = json.loads((output / "analysis-mechanical.json").read_text())
            engine = requirements["engine"]
            mechanical = requirements["mechanical"]
            radius = engine["strokeMeters"] / 2
            closure = radius + mechanical["connectingRodLengthMeters"] + mechanical["pistonCompressionHeightMeters"]
            self.assertAlmostEqual(closure, mechanical["crankAxisToDeckMeters"], places=12)
            self.assertEqual(report["geometry"]["deckClosureResidualMicrometers"], 0)
            omega = engine["redlineRPM"] * 2 * math.pi / 60
            acceleration = radius * omega**2 * (1 + radius / mechanical["connectingRodLengthMeters"])
            inertia = acceleration * mechanical["reciprocatingMassPerCylinderKilograms"]
            area = math.pi * engine["boreMeters"] ** 2 / 4
            gas = area * mechanical["designCylinderPressurePascals"]
            gross = gas + inertia
            self.assertAlmostEqual(report["loadScreens"]["grossRodCompressionEnvelopeKilonewtons"], gross / 1000, places=5)
            euler = math.pi**2 * mechanical["connectingRodYoungsModulusPascals"] * mechanical["connectingRodWeakAxisSecondMomentMeters4"] / mechanical["connectingRodEffectiveBucklingLengthMeters"] ** 2
            self.assertAlmostEqual(report["loadScreens"]["rodEulerToGrossCompressionRatio"], euler / gross, places=5)
            self.assertGreaterEqual(report["loadScreens"]["rodEulerToGrossCompressionRatio"], mechanical["minimumEulerBucklingRatio"])

    def test_semantic_inventory_has_unique_complete_cylinder_roles(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory)
            result = self.run_calculator(REQUIREMENTS, THERMAL, output)
            self.assertEqual(result.returncode, 0, result.stderr)
            architecture = json.loads((output / "semantic-architecture.json").read_text())
            part_ids = [part["partID"] for part in architecture["parts"]]
            datum_ids = [datum["datumID"] for datum in architecture["datums"]]
            self.assertEqual(len(part_ids), len(set(part_ids)))
            self.assertEqual(len(datum_ids), len(set(datum_ids)))
            for part in architecture["parts"]:
                self.assertTrue(part["subsystem"])
                self.assertTrue(part["materialIntent"])
                self.assertTrue(part["cadRepresentation"])
                self.assertTrue(part["calculationDependencies"])
            for interface in architecture["fluidInterfaces"]:
                numeric_values = [
                    value
                    for key, value in interface.items()
                    if key in ("designFlowLitersPerMinute", "designHeatKilowatts")
                ]
                self.assertEqual(len(numeric_values), 1)
                self.assertGreater(numeric_values[0], 0)
            for cylinder in ("L1", "L2", "L3", "L4", "R1", "R2", "R3", "R4"):
                required_suffixes = ("liner", "piston", "wrist-pin", "connecting-rod", "big-end-bearing", "spark-plug", "di-injector", "pfi-injector", "ignition-coil", "oil-jet")
                for suffix in required_suffixes:
                    self.assertIn(f"cylinder.{cylinder}.{suffix}", part_ids)
                self.assertEqual(sum(identifier.startswith(f"cylinder.{cylinder}.intake-valve.") for identifier in part_ids), 2)
                self.assertEqual(sum(identifier.startswith(f"cylinder.{cylinder}.exhaust-valve.") for identifier in part_ids), 2)
                self.assertIn(f"datum.cylinder-axis.{cylinder}", datum_ids)

    def test_stale_thermal_dependency_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            temporary = Path(directory)
            changed = copy.deepcopy(json.loads(REQUIREMENTS.read_text()))
            changed["mechanical"]["reciprocatingMassPerCylinderKilograms"] = 0.56
            changed_path = temporary / "requirements.json"
            changed_path.write_text(json.dumps(changed))
            result = self.run_calculator(changed_path, THERMAL, temporary / "output")
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("thermal analysis does not match requirements", result.stderr)

    def test_nonclosing_deck_is_rejected_without_output(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            temporary = Path(directory)
            changed = copy.deepcopy(json.loads(REQUIREMENTS.read_text()))
            changed["mechanical"]["crankAxisToDeckMeters"] = 0.225
            changed_bytes = (json.dumps(changed, indent=2, sort_keys=True) + "\n").encode()
            changed_path = temporary / "requirements.json"
            changed_path.write_bytes(changed_bytes)
            thermal = copy.deepcopy(json.loads(THERMAL.read_text()))
            thermal["provenance"]["requirementsSHA256"] = hashlib.sha256(changed_bytes).hexdigest()
            thermal_path = temporary / "thermal.json"
            thermal_path.write_text(json.dumps(thermal))
            output = temporary / "output"
            result = self.run_calculator(changed_path, thermal_path, output)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("do not close", result.stderr)
            self.assertFalse((output / "analysis-mechanical.json").exists())

    def test_outputs_are_deterministic(self) -> None:
        with tempfile.TemporaryDirectory() as first, tempfile.TemporaryDirectory() as second:
            first_result = self.run_calculator(REQUIREMENTS, THERMAL, Path(first))
            second_result = self.run_calculator(REQUIREMENTS, THERMAL, Path(second))
            self.assertEqual(first_result.returncode, 0, first_result.stderr)
            self.assertEqual(second_result.returncode, 0, second_result.stderr)
            for filename in ("analysis-mechanical.json", "mechanical-load-cases.csv", "semantic-architecture.json"):
                self.assertEqual((Path(first) / filename).read_bytes(), (Path(second) / filename).read_bytes())

    def test_insufficient_rod_buckling_screen_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            temporary = Path(directory)
            changed = copy.deepcopy(json.loads(REQUIREMENTS.read_text()))
            changed["mechanical"]["connectingRodWeakAxisSecondMomentMeters4"] = 1.0e-9
            changed_bytes = (json.dumps(changed, indent=2, sort_keys=True) + "\n").encode()
            changed_path = temporary / "requirements.json"
            changed_path.write_bytes(changed_bytes)
            thermal = copy.deepcopy(json.loads(THERMAL.read_text()))
            thermal["provenance"]["requirementsSHA256"] = hashlib.sha256(changed_bytes).hexdigest()
            thermal_path = temporary / "thermal.json"
            thermal_path.write_text(json.dumps(thermal))
            result = self.run_calculator(changed_path, thermal_path, temporary / "output")
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("Euler screening ratio is below its minimum", result.stderr)


if __name__ == "__main__":
    unittest.main()
