#!/usr/bin/env python3

from __future__ import annotations

import argparse
from collections import Counter
from dataclasses import dataclass
from datetime import datetime, timezone
import json
import math
import os
from pathlib import Path
import plistlib
import re
import signal
import subprocess
import sys
import tempfile
import uuid


TEST_TARGET = "RupaCoreTests"
PROFILE_SCHEMA_VERSION = 1
MAX_TIMEOUT_SECONDS = 120
PARALLELISM_ENVIRONMENT_KEY = "SWT_EXPERIMENTAL_MAXIMUM_PARALLELIZATION_WIDTH"


@dataclass(frozen=True)
class TestMeasurement:
    identifier: str
    duration: float


@dataclass(frozen=True)
class SelectionGroup:
    selector: str
    members: tuple[TestMeasurement, ...]

    @property
    def duration(self) -> float:
        return sum(member.duration for member in self.members)


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Run RupaCoreTests in balanced, independently isolated xcodebuild "
            "workers using measurements from a prior successful result."
        )
    )
    parser.add_argument("--xctestrun", required=True, type=Path)
    parser.add_argument(
        "--profile",
        type=Path,
        help=(
            "A prior .xcresult, a directory containing worker-*.xcresult, or a "
            "profile JSON. Defaults to .build/rupa-core-parallel/profile.json."
        ),
    )
    parser.add_argument("--workers", type=positive_integer)
    parser.add_argument("--width", type=positive_integer)
    parser.add_argument("--timeout", type=bounded_timeout, default=120)
    return parser.parse_args()


def positive_integer(value: str) -> int:
    parsed = int(value)
    if parsed < 1:
        raise argparse.ArgumentTypeError("value must be a positive integer")
    return parsed


def bounded_timeout(value: str) -> int:
    parsed = positive_integer(value)
    if parsed > MAX_TIMEOUT_SECONDS:
        raise argparse.ArgumentTypeError(
            f"timeout must not exceed {MAX_TIMEOUT_SECONDS} seconds"
        )
    return parsed


def repository_root() -> Path:
    return Path(__file__).resolve().parent.parent


def logical_cpu_count() -> int:
    return os.cpu_count() or 1


def default_worker_count(cpu_count: int) -> int:
    return min(4, max(1, cpu_count // 3))


def load_profile(profile_path: Path) -> list[TestMeasurement]:
    if profile_path.is_file() and profile_path.suffix == ".json":
        payload = json.loads(profile_path.read_text())
        if payload.get("schemaVersion") != PROFILE_SCHEMA_VERSION:
            raise ValueError(
                f"unsupported profile schema: {payload.get('schemaVersion')}"
            )
        measurements = [
            TestMeasurement(
                identifier=item["identifier"],
                duration=float(item["duration"]),
            )
            for item in payload.get("tests", [])
        ]
        return unique_measurements(measurements)

    result_paths: list[Path]
    if profile_path.is_dir() and profile_path.suffix == ".xcresult":
        result_paths = [profile_path]
    elif profile_path.is_dir():
        result_paths = sorted(profile_path.glob("worker-*.xcresult"))
    else:
        result_paths = []

    if not result_paths:
        raise ValueError(f"no test profile results found at {profile_path}")

    measurements: list[TestMeasurement] = []
    for result_path in result_paths:
        measurements.extend(measurements_from_result(result_path))
    return unique_measurements(measurements)


def measurements_from_result(result_path: Path) -> list[TestMeasurement]:
    completed = subprocess.run(
        [
            "xcrun",
            "xcresulttool",
            "get",
            "test-results",
            "tests",
            "--path",
            str(result_path),
            "--compact",
        ],
        check=True,
        capture_output=True,
        text=True,
    )
    payload = json.loads(completed.stdout)
    measurements: list[TestMeasurement] = []

    def visit(node: dict[str, object]) -> None:
        if node.get("nodeType") == "Test Case":
            if node.get("result") != "Passed":
                raise ValueError(
                    "test profile contains a non-passing case: "
                    f"{node.get('nodeIdentifier')}"
                )
            raw_identifier = str(node["nodeIdentifier"])
            identifier = f"{TEST_TARGET}/{raw_identifier.removesuffix('()')}"
            measurements.append(
                TestMeasurement(
                    identifier=identifier,
                    duration=float(node.get("durationInSeconds", 0.0)),
                )
            )
        for child in node.get("children", []):
            visit(child)

    for root_node in payload.get("testNodes", []):
        visit(root_node)
    return measurements


def unique_measurements(
    measurements: list[TestMeasurement],
) -> list[TestMeasurement]:
    durations_by_identifier: dict[str, float] = {}
    for measurement in measurements:
        durations_by_identifier[measurement.identifier] = max(
            measurement.duration,
            durations_by_identifier.get(measurement.identifier, 0.0),
        )
    return [
        TestMeasurement(identifier=identifier, duration=duration)
        for identifier, duration in sorted(durations_by_identifier.items())
    ]


def source_test_names(test_source_root: Path) -> list[str]:
    annotation_pattern = re.compile(r"@Test\b")
    declaration_pattern = re.compile(
        r"@Test\b(?:(?!@Test\b).){0,2000}?\bfunc\s+([A-Za-z_][A-Za-z0-9_]*)\s*\(",
        re.DOTALL,
    )
    annotation_count = 0
    names: list[str] = []
    for source_path in sorted(test_source_root.rglob("*.swift")):
        source = source_path.read_text()
        annotation_count += len(annotation_pattern.findall(source))
        names.extend(declaration_pattern.findall(source))
    if len(names) != annotation_count:
        raise ValueError(
            "could not map every @Test annotation to a test function: "
            f"annotations={annotation_count}, functions={len(names)}"
        )
    return names


def validate_profile_against_sources(
    measurements: list[TestMeasurement], test_source_root: Path
) -> None:
    profile_names = [
        measurement.identifier.rsplit("/", 1)[-1] for measurement in measurements
    ]
    current_names = source_test_names(test_source_root)
    if Counter(profile_names) != Counter(current_names):
        missing = sorted((Counter(current_names) - Counter(profile_names)).elements())
        removed = sorted((Counter(profile_names) - Counter(current_names)).elements())
        raise ValueError(
            "test profile does not match current RupaCoreTests sources; create a "
            "new full-suite result before sharding "
            f"(missing={missing[:5]}, removed={removed[:5]})"
        )


def selection_groups(
    measurements: list[TestMeasurement],
) -> list[SelectionGroup]:
    sorted_measurements = sorted(measurements, key=lambda item: item.identifier)
    groups: list[SelectionGroup] = []
    index = 0
    while index < len(sorted_measurements):
        root = sorted_measurements[index]
        members = [root]
        following_index = index + 1
        while (
            following_index < len(sorted_measurements)
            and sorted_measurements[following_index].identifier.startswith(
                root.identifier
            )
        ):
            members.append(sorted_measurements[following_index])
            following_index += 1
        groups.append(
            SelectionGroup(selector=root.identifier, members=tuple(members))
        )
        index = following_index
    return groups


def balanced_selectors(
    groups: list[SelectionGroup], worker_count: int
) -> list[list[str]]:
    shards: list[tuple[list[str], float]] = [([], 0.0) for _ in range(worker_count)]
    for group in sorted(groups, key=lambda item: item.duration, reverse=True):
        shard_index = min(
            range(worker_count),
            key=lambda index: (shards[index][1], len(shards[index][0])),
        )
        selectors, duration = shards[shard_index]
        selectors.append(group.selector)
        shards[shard_index] = (selectors, duration + group.duration)
    return [selectors for selectors, _ in shards]


def configured_xctestrun(source_path: Path, width: int) -> Path:
    with source_path.open("rb") as source_file:
        payload = plistlib.load(source_file)
    target_configuration = payload.get(TEST_TARGET)
    if not isinstance(target_configuration, dict):
        raise ValueError(f"{source_path} does not contain {TEST_TARGET}")
    environment = target_configuration.setdefault("EnvironmentVariables", {})
    environment[PARALLELISM_ENVIRONMENT_KEY] = str(width)

    temporary_file = tempfile.NamedTemporaryFile(
        mode="wb",
        prefix=f".{TEST_TARGET}.parallel.",
        suffix=".xctestrun",
        dir=source_path.parent,
        delete=False,
    )
    configured_path = Path(temporary_file.name)
    with temporary_file:
        plistlib.dump(payload, temporary_file)
    return configured_path


def run_shards(
    *,
    selectors: list[list[str]],
    xctestrun_path: Path,
    timeout_seconds: int,
    artifacts_root: Path,
) -> list[Path]:
    repo_root = repository_root()
    timeout_script = repo_root / "scripts" / "swift-test-timeout.sh"
    architecture = subprocess.run(
        ["uname", "-m"], check=True, capture_output=True, text=True
    ).stdout.strip()

    result_paths: list[Path] = []
    processes: list[tuple[int, subprocess.Popen[bytes], object]] = []
    try:
        for worker_index, worker_selectors in enumerate(selectors):
            response_path = artifacts_root / f"shard-{worker_index}.txt"
            response_path.write_text("\n".join(worker_selectors) + "\n")
            result_path = artifacts_root / f"worker-{worker_index}.xcresult"
            log_path = artifacts_root / f"worker-{worker_index}.log"
            result_paths.append(result_path)
            log_file = log_path.open("wb")
            command = [
                str(timeout_script),
                str(timeout_seconds),
                "--",
                "xcodebuild",
                "test-without-building",
                "-xctestrun",
                str(xctestrun_path),
                "-destination",
                f"platform=macOS,arch={architecture}",
                "-only-testing",
                f"@{response_path}",
                "-resultBundlePath",
                str(result_path),
            ]
            try:
                process = subprocess.Popen(
                    command,
                    cwd=repo_root,
                    stdout=log_file,
                    stderr=subprocess.STDOUT,
                    start_new_session=True,
                )
            except BaseException:
                log_file.close()
                raise
            processes.append((worker_index, process, log_file))
    except BaseException:
        for _, process, log_file in processes:
            os.killpg(process.pid, signal.SIGTERM)
            process.wait()
            log_file.close()
        raise

    failures: list[int] = []
    for worker_index, process, log_file in processes:
        return_code = process.wait()
        log_file.close()
        if return_code != 0:
            failures.append(worker_index)
    if failures:
        raise RuntimeError(
            f"parallel test workers failed: {', '.join(map(str, failures))}; "
            f"artifacts: {artifacts_root}"
        )
    return result_paths


def validate_results(
    result_paths: list[Path], expected_measurements: list[TestMeasurement]
) -> list[TestMeasurement]:
    executed: list[TestMeasurement] = []
    for result_path in result_paths:
        executed.extend(measurements_from_result(result_path))
    unique_executed = unique_measurements(executed)
    expected_identifiers = {
        measurement.identifier for measurement in expected_measurements
    }
    executed_identifiers = {measurement.identifier for measurement in unique_executed}
    if len(executed) != len(unique_executed):
        raise RuntimeError(
            "parallel test selection executed duplicate cases: "
            f"total={len(executed)}, unique={len(unique_executed)}"
        )
    if executed_identifiers != expected_identifiers:
        missing = sorted(expected_identifiers - executed_identifiers)
        unexpected = sorted(executed_identifiers - expected_identifiers)
        raise RuntimeError(
            "parallel test selection did not preserve the complete test set "
            f"(missing={missing[:5]}, unexpected={unexpected[:5]})"
        )
    return unique_executed


def write_profile(profile_path: Path, measurements: list[TestMeasurement]) -> None:
    profile_path.parent.mkdir(parents=True, exist_ok=True)
    payload = {
        "schemaVersion": PROFILE_SCHEMA_VERSION,
        "generatedAt": datetime.now(timezone.utc).isoformat(),
        "tests": [
            {
                "identifier": measurement.identifier,
                "duration": measurement.duration,
            }
            for measurement in measurements
        ],
    }
    temporary_path = profile_path.with_suffix(".tmp")
    temporary_path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n")
    temporary_path.replace(profile_path)


def main() -> int:
    arguments = parse_arguments()
    repo_root = repository_root()
    xctestrun_path = arguments.xctestrun.resolve()
    if not xctestrun_path.is_file():
        raise ValueError(f"xctestrun does not exist: {xctestrun_path}")

    profile_cache = repo_root / ".build" / "rupa-core-parallel" / "profile.json"
    profile_path = (arguments.profile or profile_cache).resolve()
    measurements = load_profile(profile_path)
    validate_profile_against_sources(
        measurements, repo_root / "Tests" / TEST_TARGET
    )

    cpu_count = logical_cpu_count()
    worker_count = arguments.workers or default_worker_count(cpu_count)
    execution_width = arguments.width or max(1, math.ceil(cpu_count / worker_count))
    groups = selection_groups(measurements)
    if worker_count > len(groups):
        raise ValueError(
            f"worker count {worker_count} exceeds selectable test groups {len(groups)}"
        )
    selectors = balanced_selectors(groups, worker_count)

    run_identifier = (
        datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
        + "-"
        + uuid.uuid4().hex[:8]
    )
    artifacts_root = (
        repo_root / ".build" / "rupa-core-parallel" / "runs" / run_identifier
    )
    artifacts_root.mkdir(parents=True)
    configured_path = configured_xctestrun(xctestrun_path, execution_width)
    try:
        print(
            f"running {len(measurements)} tests with {worker_count} workers "
            f"and width {execution_width}"
        )
        result_paths = run_shards(
            selectors=selectors,
            xctestrun_path=configured_path,
            timeout_seconds=arguments.timeout,
            artifacts_root=artifacts_root,
        )
        executed = validate_results(result_paths, measurements)
        write_profile(profile_cache, executed)
    finally:
        configured_path.unlink(missing_ok=True)

    print(f"passed {len(executed)} unique tests; artifacts: {artifacts_root}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, ValueError, RuntimeError, subprocess.SubprocessError) as error:
        print(f"error: {error}", file=sys.stderr)
        raise SystemExit(1)
