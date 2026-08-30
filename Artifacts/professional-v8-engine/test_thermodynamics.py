#!/usr/bin/env python3
"""Independent checks for generated professional V8 thermal evidence."""

from __future__ import annotations

import copy
import json
import math
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


ROOT = Path(__file__).parent
CALCULATOR = ROOT / "calculate_thermodynamics.py"
REQUIREMENTS = ROOT / "requirements.json"


class ThermodynamicEvidenceTests(unittest.TestCase):
    def run_calculator(self, requirements: Path, output: Path) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [
                sys.executable,
                str(CALCULATOR),
                "--requirements",
                str(requirements),
                "--output-directory",
                str(output),
            ],
            check=False,
            capture_output=True,
            text=True,
            timeout=10,
        )

    def test_generated_report_independently_closes_power_and_heat(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory)
            result = self.run_calculator(REQUIREMENTS, output)
            self.assertEqual(result.returncode, 0, result.stderr)
            requirements = json.loads(REQUIREMENTS.read_text())
            report = json.loads((output / "analysis-thermal.json").read_text())

            engine = requirements["engine"]
            displacement = (
                engine["cylinders"]
                * math.pi
                * engine["boreMeters"] ** 2
                * engine["strokeMeters"]
                / 4
            )
            self.assertAlmostEqual(
                report["derivedGeometry"]["displacementLiters"],
                displacement * 1000,
                places=8,
            )

            target = next(
                point
                for point in requirements["performance"]["curve"]
                if point["rpm"] == requirements["performance"]["targetPowerRPM"]
            )
            power = 2 * math.pi * target["rpm"] * target["torqueNewtonMeters"] / 60
            self.assertAlmostEqual(power, requirements["performance"]["targetPowerWatts"], places=6)
            bmep_bar = 4 * math.pi * target["torqueNewtonMeters"] / displacement / 100000
            self.assertLessEqual(bmep_bar, requirements["performance"]["maximumBMEPBar"])

            heat = report["fullPowerHeatBalance"]
            allocated = sum(
                heat[key]
                for key in (
                    "brakeKilowatts",
                    "exhaustBeforeTurbineKilowatts",
                    "highTemperatureCoolantKilowatts",
                    "oilKilowatts",
                    "chargeCoolingAllocatedKilowatts",
                    "ambientAndUnmodeledKilowatts",
                )
            )
            self.assertAlmostEqual(allocated, heat["fuelInputKilowatts"], places=5)
            self.assertGreaterEqual(heat["chargeCoolingReserveKilowatts"], 0)
            turbo = report["turboThermalEnvelope"]
            self.assertLessEqual(
                turbo["estimatedTurbineInletCelsius"], turbo["continuousLimitCelsius"]
            )

    def test_output_is_deterministic(self) -> None:
        with tempfile.TemporaryDirectory() as first, tempfile.TemporaryDirectory() as second:
            first_result = self.run_calculator(REQUIREMENTS, Path(first))
            second_result = self.run_calculator(REQUIREMENTS, Path(second))
            self.assertEqual(first_result.returncode, 0, first_result.stderr)
            self.assertEqual(second_result.returncode, 0, second_result.stderr)
            for filename in (
                "analysis-thermal.json",
                "power-curve.csv",
                "compressor-operating-points.csv",
                "thermal-budget.csv",
            ):
                self.assertEqual(
                    (Path(first) / filename).read_bytes(),
                    (Path(second) / filename).read_bytes(),
                )

    def test_nonclosing_heat_split_is_rejected_without_success_report(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            temporary = Path(directory)
            invalid = copy.deepcopy(json.loads(REQUIREMENTS.read_text()))
            invalid["thermal"]["energyFractions"]["ambientAndUnmodeled"] = 0.1
            invalid_path = temporary / "invalid.json"
            invalid_path.write_text(json.dumps(invalid))
            output = temporary / "output"
            result = self.run_calculator(invalid_path, output)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("thermal energy fractions must sum to one", result.stderr)
            self.assertFalse((output / "analysis-thermal.json").exists())

    def test_target_power_mismatch_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            temporary = Path(directory)
            invalid = copy.deepcopy(json.loads(REQUIREMENTS.read_text()))
            invalid["performance"]["curve"][9]["torqueNewtonMeters"] = 650
            invalid_path = temporary / "invalid.json"
            invalid_path.write_text(json.dumps(invalid))
            result = self.run_calculator(invalid_path, temporary / "output")
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("target power point does not match target power", result.stderr)

    def test_original_exhaust_split_is_rejected_by_continuous_temperature_gate(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            temporary = Path(directory)
            invalid = copy.deepcopy(json.loads(REQUIREMENTS.read_text()))
            fractions = invalid["thermal"]["energyFractions"]
            fractions["exhaustBeforeTurbine"] = 0.34
            fractions["ambientAndUnmodeled"] = 0.04
            invalid_path = temporary / "invalid.json"
            invalid_path.write_text(json.dumps(invalid))
            result = self.run_calculator(invalid_path, temporary / "output")
            self.assertNotEqual(result.returncode, 0)
            self.assertIn(
                "estimated continuous turbine inlet temperature exceeds its limit",
                result.stderr,
            )

    def test_invalid_unused_product_requirement_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            temporary = Path(directory)
            invalid = copy.deepcopy(json.loads(REQUIREMENTS.read_text()))
            invalid["application"]["roadLifeTargetKilometers"] = float("nan")
            invalid_path = temporary / "invalid.json"
            invalid_path.write_text(json.dumps(invalid))
            result = self.run_calculator(invalid_path, temporary / "output")
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("roadLifeTargetKilometers must be finite and positive", result.stderr)


if __name__ == "__main__":
    unittest.main()
