#!/usr/bin/env python3
"""Verify cumulative professional V8 P2 evidence and emit a compact report."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import subprocess
from typing import Any


class IntegrationVerificationError(ValueError):
    """Raised when cumulative V8 evidence is stale or incomplete."""


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def load(root: Path, name: str) -> dict[str, Any]:
    return json.loads((root / name).read_text())


def require(condition: bool, message: str) -> None:
    if not condition:
        raise IntegrationVerificationError(message)


def git_output(repository: Path, *arguments: str) -> str:
    result = subprocess.run(
        ["git", *arguments],
        cwd=repository,
        check=False,
        capture_output=True,
        text=True,
        timeout=10,
    )
    if result.returncode != 0:
        raise IntegrationVerificationError(f"git command failed: {' '.join(arguments)}")
    return result.stdout.strip()


def verify(root: Path, repository: Path, cli: Path) -> dict[str, Any]:
    requirements = load(root, "requirements.json")
    thermal = load(root, "analysis-thermal.json")
    mechanical = load(root, "analysis-mechanical.json")
    architecture = load(root, "semantic-architecture.json")
    manifest = load(root, "cad-source-manifest.json")
    batch = load(root, "create-professional-v8-batch.json")
    cad_verification = load(root, "verification-cad.json")

    requirement_hash = sha256(root / "requirements.json")
    thermal_hash = sha256(root / "analysis-thermal.json")
    mechanical_hash = sha256(root / "analysis-mechanical.json")
    architecture_hash = sha256(root / "semantic-architecture.json")
    manifest_hash = sha256(root / "cad-source-manifest.json")
    batch_hash = sha256(root / "create-professional-v8-batch.json")
    artifact_hash = sha256(root / "professional-v8.swcad")

    require(thermal["provenance"]["requirementsSHA256"] == requirement_hash, "thermal requirements provenance is stale")
    require(thermal["provenance"]["calculationSourceSHA256"] == sha256(root / "calculate_thermodynamics.py"), "thermal calculator provenance is stale")
    require(mechanical["provenance"]["requirementsSHA256"] == requirement_hash, "mechanical requirements provenance is stale")
    require(mechanical["provenance"]["thermalAnalysisSHA256"] == thermal_hash, "mechanical thermal provenance is stale")
    require(mechanical["provenance"]["calculationSourceSHA256"] == sha256(root / "calculate_mechanics.py"), "mechanical calculator provenance is stale")
    require(architecture["provenance"] == mechanical["provenance"], "semantic architecture provenance is stale")
    require(manifest["provenance"]["requirementsSHA256"] == requirement_hash, "CAD requirements provenance is stale")
    require(manifest["provenance"]["thermalAnalysisSHA256"] == thermal_hash, "CAD thermal provenance is stale")
    require(manifest["provenance"]["mechanicalAnalysisSHA256"] == mechanical_hash, "CAD mechanical provenance is stale")
    require(manifest["provenance"]["semanticArchitectureSHA256"] == architecture_hash, "CAD architecture provenance is stale")
    require(manifest["provenance"]["generatorSHA256"] == sha256(root / "generate_cad_artifacts.py"), "CAD generator provenance is stale")
    require(cad_verification["inputs"]["manifestSHA256"] == manifest_hash, "executed CAD manifest is stale")
    require(cad_verification["inputs"]["batchSHA256"] == batch_hash, "executed CAD batch is stale")
    require(cad_verification["artifact"]["sha256"] == artifact_hash, "executed native CAD artifact is stale")
    require(cli.is_file() and cad_verification["inputs"]["cliSHA256"] == sha256(cli), "executed Rupa CLI binary is stale")

    require(requirements["performance"]["targetPowerWatts"] == 450000, "target power drifted")
    require(thermal["performance"]["targetPowerKilowatts"] == 450, "calculated target power drifted")
    require(thermal["performance"]["peakTorqueNewtonMeters"] == 750, "peak torque drifted")
    require(thermal["performance"]["peakBMEPBar"] <= thermal["performance"]["maximumBMEPBar"], "BMEP gate failed")
    require(thermal["fullPowerHeatBalance"]["closureErrorWatts"] == 0, "first-law heat balance does not close")
    require(thermal["fullPowerHeatBalance"]["chargeCoolingReserveKilowatts"] >= 0, "charge-cooling reserve is negative")
    require(thermal["turboThermalEnvelope"]["estimatedTurbineInletCelsius"] <= thermal["turboThermalEnvelope"]["continuousLimitCelsius"], "turbine temperature screen failed")
    require("open-compressor-map-selection" in thermal["status"], "open compressor-map gate was hidden")

    require(mechanical["geometry"]["deckClosureResidualMicrometers"] == 0, "mechanical deck closure failed")
    require(mechanical["kinematics"]["meanPistonSpeedAtRedlineMetersPerSecond"] <= requirements["mechanical"]["maximumMeanPistonSpeedAtRedlineMetersPerSecond"], "mean piston speed gate failed")
    require(mechanical["loadScreens"]["rodEulerToGrossCompressionRatio"] >= mechanical["loadScreens"]["minimumRodEulerRatio"], "rod Euler screen failed")
    require(mechanical["architectureInventory"]["semanticPartCount"] == 168, "mechanical semantic inventory drifted")
    require(mechanical["openReleaseGates"], "mechanical release gates were hidden")

    architecture_ids = {part["partID"] for part in architecture["parts"]}
    component_ids = {component["partID"] for component in manifest["components"]}
    require(len(architecture_ids) == 168 and component_ids == architecture_ids, "CAD semantic coverage is incomplete")
    require(manifest["bodyCount"] == 202, "CAD body inventory drifted")
    require(len(batch["commands"]) == manifest["bodyCount"] + 1, "CAD batch command inventory drifted")
    require(cad_verification["atomicBatch"]["metrics"]["historyEntryCount"] == 1, "CAD publication was not atomic")
    require(cad_verification["atomicBatch"]["metrics"]["evaluationPassCount"] == 1, "CAD batch evaluation count drifted")
    require(cad_verification["sourceAndSolidMeasurement"]["counts"]["solids"] == manifest["bodyCount"], "loaded CAD solid count drifted")
    require(cad_verification["topology"]["counts"]["bodyCount"] == manifest["bodyCount"], "loaded topology body count drifted")
    require(cad_verification["viewerMesh"]["bodyCount"] == manifest["bodyCount"], "viewer Mesh body count drifted")
    require(cad_verification["semanticCoverage"]["coveredSemanticPartCount"] == 168, "executed semantic coverage drifted")
    require(cad_verification["semanticCoverage"]["unsupportedManufacturingDetails"], "unsupported manufacturing details were hidden")

    claim_levels = {thermal["claimLevel"], mechanical["claimLevel"], architecture["claimLevel"], manifest["claimLevel"], cad_verification["claimLevel"]}
    require(claim_levels == {"P2-engineering-reference"}, "claim levels are inconsistent")
    open_gates = sorted(set(thermal["openReleaseGates"] + mechanical["openReleaseGates"] + manifest["unsupportedManufacturingDetails"]))
    require(len(open_gates) >= 10, "production-release blockers are incomplete")

    expected_commits = {
        "V8-0": "473821b8",
        "V8-T": "e33ba27",
        "V8-M": "9bc5e82",
        "V8-C": "a0bf0466",
    }
    for sprint, prefix in expected_commits.items():
        resolved = git_output(repository, "rev-parse", prefix)
        require(resolved.startswith(prefix), f"{sprint} commit is missing")

    return {
        "schemaVersion": "professional-v8.integration-verification.v1",
        "claimLevel": "P2-engineering-reference",
        "status": "p2-professional-engineering-reference-verified-production-release-rejected",
        "product": {
            "architecture": "90-degree-cross-plane-parallel-twin-turbo-V8",
            "displacementLiters": thermal["derivedGeometry"]["displacementLiters"],
            "targetPowerKilowatts": thermal["performance"]["targetPowerKilowatts"],
            "peakTorqueNewtonMeters": thermal["performance"]["peakTorqueNewtonMeters"],
            "redlineRPM": requirements["engine"]["redlineRPM"],
        },
        "thermalEvidence": {
            "peakBMEPBar": thermal["performance"]["peakBMEPBar"],
            "fuelMassKilogramsPerHour": thermal["fullPowerAirAndFuel"]["fuelMassKilogramsPerHour"],
            "highTemperatureCoolantKilowatts": thermal["fullPowerHeatBalance"]["highTemperatureCoolantKilowatts"],
            "oilKilowatts": thermal["fullPowerHeatBalance"]["oilKilowatts"],
            "estimatedTurbineInletCelsius": thermal["turboThermalEnvelope"]["estimatedTurbineInletCelsius"],
            "heatClosureErrorWatts": thermal["fullPowerHeatBalance"]["closureErrorWatts"],
        },
        "mechanicalEvidence": {
            "meanPistonSpeedMetersPerSecond": mechanical["kinematics"]["meanPistonSpeedAtRedlineMetersPerSecond"],
            "designGasForceKilonewtons": mechanical["loadScreens"]["designGasForceKilonewtons"],
            "grossRodCompressionKilonewtons": mechanical["loadScreens"]["grossRodCompressionEnvelopeKilonewtons"],
            "rodEulerRatio": mechanical["loadScreens"]["rodEulerToGrossCompressionRatio"],
        },
        "cadEvidence": {
            "semanticParts": 168,
            "sourceBodies": manifest["bodyCount"],
            "sourceFeatures": cad_verification["sourceAndSolidMeasurement"]["counts"]["sourceFeatures"],
            "topologyFaces": cad_verification["topology"]["counts"]["faceCount"],
            "meshTriangles": cad_verification["viewerMesh"]["triangleCount"],
            "artifactSHA256": artifact_hash,
        },
        "provenance": {
            "requirementsSHA256": requirement_hash,
            "thermalAnalysisSHA256": thermal_hash,
            "mechanicalAnalysisSHA256": mechanical_hash,
            "semanticArchitectureSHA256": architecture_hash,
            "cadManifestSHA256": manifest_hash,
            "cadBatchSHA256": batch_hash,
            "cadVerificationSHA256": sha256(root / "verification-cad.json"),
        },
        "verifiedSprintCommits": expected_commits,
        "openProductionReleaseGates": open_gates,
    }


def main() -> None:
    root = Path(__file__).parent
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, default=root)
    parser.add_argument("--repository", type=Path, default=root.parents[1])
    parser.add_argument("--cli", type=Path, default=root.parents[1] / "RupaKit/.build/out/Products/Debug/rupa")
    parser.add_argument("--output", type=Path, default=root / "integration-report.json")
    arguments = parser.parse_args()
    report = verify(arguments.root, arguments.repository, arguments.cli)
    content = json.dumps(report, indent=2, sort_keys=True, allow_nan=False) + "\n"
    candidate = arguments.output.with_name(f".{arguments.output.name}.candidate")
    candidate.write_text(content)
    candidate.replace(arguments.output)
    print(json.dumps({
        "status": report["status"],
        "semanticParts": report["cadEvidence"]["semanticParts"],
        "sourceBodies": report["cadEvidence"]["sourceBodies"],
        "openProductionReleaseGateCount": len(report["openProductionReleaseGates"]),
    }, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
