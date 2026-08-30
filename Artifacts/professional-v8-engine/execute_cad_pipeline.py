#!/usr/bin/env python3
"""Execute and verify the professional V8 batch through the public Rupa CLI."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
from typing import Any


class CADPipelineError(RuntimeError):
    """Raised when the public CLI pipeline violates the CAD evidence contract."""


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        while chunk := source.read(1024 * 1024):
            digest.update(chunk)
    return digest.hexdigest()


def run_json(command: list[str], timeout: int) -> dict[str, Any]:
    result = subprocess.run(command, check=False, capture_output=True, text=True, timeout=timeout)
    if result.returncode != 0:
        raise CADPipelineError(
            f"command failed with exit code {result.returncode}: {' '.join(command)}\n{result.stderr}"
        )
    try:
        return json.loads(result.stdout)
    except json.JSONDecodeError as error:
        raise CADPipelineError(f"command did not return JSON: {' '.join(command)}") from error


def error_diagnostics(value: dict[str, Any]) -> list[dict[str, Any]]:
    return [
        diagnostic
        for diagnostic in value.get("diagnostics", [])
        if diagnostic.get("severity") in ("error", "fatal")
    ]


def stable_diagnostics(value: dict[str, Any]) -> list[dict[str, Any]]:
    return [
        {
            key: diagnostic[key]
            for key in ("severity", "code", "message")
            if key in diagnostic
        }
        for diagnostic in value.get("diagnostics", [])
    ]


def main() -> None:
    root = Path(__file__).parent
    parser = argparse.ArgumentParser()
    parser.add_argument("--cli", type=Path, default=root.parents[1] / "RupaKit/.build/out/Products/Debug/rupa")
    parser.add_argument("--batch", type=Path, default=root / "create-professional-v8-batch.json")
    parser.add_argument("--manifest", type=Path, default=root / "cad-source-manifest.json")
    parser.add_argument("--artifact", type=Path, default=root / "professional-v8.swcad")
    parser.add_argument("--report", type=Path, default=root / "verification-cad.json")
    arguments = parser.parse_args()
    cli = arguments.cli.resolve()
    if not cli.is_file():
        raise CADPipelineError(f"Rupa CLI not found: {cli}")
    manifest = json.loads(arguments.manifest.read_text())
    batch = json.loads(arguments.batch.read_text())
    body_count = manifest["bodyCount"]
    command_count = len(batch["commands"])
    if command_count != body_count + 1:
        raise CADPipelineError("batch must contain one body command per manifest body plus validation")
    if manifest["coveredSemanticPartCount"] != manifest["semanticPartCount"]:
        raise CADPipelineError("CAD manifest does not cover every semantic part")

    with tempfile.TemporaryDirectory(prefix="professional-v8-cad-") as directory:
        temporary = Path(directory)
        staged_artifact = temporary / "professional-v8.swcad"
        new_result = run_json(
            [str(cli), "new", str(staged_artifact), "--name", "Professional V8 P2 Engineering Reference", "--json"],
            timeout=30,
        )
        batch_result = run_json(
            [str(cli), "batch", str(staged_artifact), "--mode", "file", "--in-place", "--input", str(arguments.batch), "--json"],
            timeout=300,
        )
        if not batch_result.get("saved") or not batch_result.get("didMutate"):
            raise CADPipelineError("atomic batch did not publish a saved mutation")
        if batch_result.get("commandCount") != command_count:
            raise CADPipelineError("executed batch command count does not match the generated batch")
        metrics = batch_result.get("metrics", {})
        if metrics.get("historyEntryCount") != 1 or metrics.get("evaluationPassCount") != 1:
            raise CADPipelineError("batch did not execute as one history entry and one evaluation pass")
        if error_diagnostics(batch_result):
            raise CADPipelineError("batch returned error diagnostics")

        validation = run_json([str(cli), "validate", str(staged_artifact), "--json"], timeout=180)
        if error_diagnostics(validation):
            raise CADPipelineError("independent reload validation returned error diagnostics")
        measurement = run_json([str(cli), "measure", str(staged_artifact), "--mode", "file", "--json"], timeout=240)
        measurement_value = measurement["measurement"]
        counts = measurement_value["counts"]
        if counts["solids"] != body_count or counts["profiles"] != body_count or counts["sourceFeatures"] != body_count * 2:
            raise CADPipelineError("post-load source and solid counts do not match the manifest")
        profile_names = {profile["featureName"]: profile for profile in measurement_value["profiles"]}
        liner_name = "cylinder.L1.liner__bore-volume-envelope Sketch"
        main_name = "crankshaft__main-journal-3 Sketch"
        if liner_name not in profile_names or main_name not in profile_names:
            raise CADPipelineError("required measured source profiles are missing")
        expected_liner_area = 3.141592653589793 * 0.043**2
        expected_main_area = 3.141592653589793 * 0.0325**2
        if abs(profile_names[liner_name]["area"]["value"] - expected_liner_area) > 1e-12:
            raise CADPipelineError("loaded bore profile does not retain the 86 mm diameter")
        if abs(profile_names[main_name]["area"]["value"] - expected_main_area) > 1e-12:
            raise CADPipelineError("loaded main journal does not retain the 65 mm diameter")

        topology = run_json([str(cli), "inspect", "topology", str(staged_artifact), "--mode", "file", "--json"], timeout=240)
        topology_counts = topology["topologySummary"]["counts"]
        if topology_counts["bodyCount"] != body_count or topology_counts["faceCount"] <= 0:
            raise CADPipelineError("topology evaluation does not match the source body inventory")
        if error_diagnostics(topology):
            raise CADPipelineError("topology evaluation returned error diagnostics")

        mesh = run_json([str(cli), "mesh", str(staged_artifact), "--mode", "file", "--json"], timeout=300)
        mesh_value = mesh["meshSummary"]
        if mesh_value["bodyCount"] != body_count or mesh_value["triangleCount"] <= 0:
            raise CADPipelineError("viewer mesh does not match the source body inventory")
        if error_diagnostics(mesh):
            raise CADPipelineError("viewer mesh returned error diagnostics")

        arguments.artifact.parent.mkdir(parents=True, exist_ok=True)
        artifact_candidate = arguments.artifact.with_name(f".{arguments.artifact.name}.candidate")
        shutil.copyfile(staged_artifact, artifact_candidate)
        artifact_candidate.replace(arguments.artifact)

    report = {
        "schemaVersion": "professional-v8.cad-verification.v1",
        "claimLevel": "P2-engineering-reference",
        "status": "public-agent-cli-cad-route-passed",
        "artifact": {
            "path": arguments.artifact.name,
            "byteCount": arguments.artifact.stat().st_size,
            "sha256": sha256_file(arguments.artifact),
        },
        "inputs": {
            "batchSHA256": sha256_file(arguments.batch),
            "manifestSHA256": sha256_file(arguments.manifest),
            "cliSHA256": sha256_file(cli),
        },
        "creation": {
            "createdInIsolatedStagingDirectory": bool(new_result.get("message")),
            "commandCount": command_count,
            "bodyMutationCount": body_count,
        },
        "atomicBatch": {
            "generation": batch_result["generation"],
            "saved": batch_result["saved"],
            "diagnostics": stable_diagnostics(batch_result),
            "metrics": metrics,
        },
        "independentReload": {
            "validationMessage": validation["message"],
            "diagnostics": stable_diagnostics(validation),
        },
        "sourceAndSolidMeasurement": {
            "counts": counts,
            "boundsMeters": measurement_value["bounds"],
            "boreDiameterMillimeters": 86.0,
            "mainJournalDiameterMillimeters": 65.0,
        },
        "topology": {
            "counts": topology_counts,
            "diagnostics": stable_diagnostics(topology),
        },
        "viewerMesh": {
            "bodyCount": mesh_value["bodyCount"],
            "vertexCount": mesh_value["vertexCount"],
            "triangleCount": mesh_value["triangleCount"],
            "indexedElementCount": mesh_value["indexedElementCount"],
            "boundsMeters": mesh_value["bounds"],
            "diagnostics": stable_diagnostics(mesh_value),
        },
        "semanticCoverage": {
            "semanticPartCount": manifest["semanticPartCount"],
            "coveredSemanticPartCount": manifest["coveredSemanticPartCount"],
            "sourceBodyCount": body_count,
            "unsupportedManufacturingDetails": manifest["unsupportedManufacturingDetails"],
        },
    }
    report_candidate = arguments.report.with_name(f".{arguments.report.name}.candidate")
    report_candidate.write_text(json.dumps(report, indent=2, sort_keys=True, allow_nan=False) + "\n")
    report_candidate.replace(arguments.report)
    print(json.dumps({
        "artifact": str(arguments.artifact),
        "artifactSHA256": report["artifact"]["sha256"],
        "bodyCount": body_count,
        "semanticPartCount": manifest["semanticPartCount"],
        "topologyFaceCount": topology_counts["faceCount"],
        "meshTriangleCount": mesh_value["triangleCount"],
    }, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
