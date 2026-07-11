import argparse
import json
import math
import sys


def parse_arguments():
    parser = argparse.ArgumentParser()
    parser.add_argument("rupa_report")
    parser.add_argument("blender_report")
    parser.add_argument("--maximum-ratio", type=float, default=2.0)
    parser.add_argument("--minimum-iterations", type=int, default=100)
    return parser.parse_args()


def load_report(path):
    with open(path, "r", encoding="utf-8") as file_value:
        content = file_value.read()
    begin = "RUPA_BENCHMARK_JSON_BEGIN"
    end = "RUPA_BENCHMARK_JSON_END"
    if begin in content and end in content:
        content = content.split(begin, 1)[1].split(end, 1)[0]
    return json.loads(content)


def workload_map(report):
    return {workload["name"]: workload for workload in report["workloads"]}


def percentile(value, samples):
    ordered = sorted(samples)
    rank = math.ceil(value * len(ordered)) - 1
    return ordered[min(max(rank, 0), len(ordered) - 1)]


def validate_statistics(workload, iteration_count, report_name):
    statistics = workload["statistics"]
    samples = statistics["samples"]
    if len(samples) != iteration_count:
        raise ValueError(
            f"{report_name} workload {workload['name']} has an invalid sample count"
        )
    if not samples or any(not math.isfinite(sample) or sample < 0.0 for sample in samples):
        raise ValueError(
            f"{report_name} workload {workload['name']} has invalid samples"
        )
    expected = {
        "minimum": min(samples),
        "median": percentile(0.5, samples),
        "p95": percentile(0.95, samples),
        "maximum": max(samples),
    }
    for name, value in expected.items():
        if not math.isclose(statistics[name], value, rel_tol=1.0e-12, abs_tol=1.0e-15):
            raise ValueError(
                f"{report_name} workload {workload['name']} has an invalid {name}"
            )


def validate_report(report, report_name, expected_engine, minimum_iterations):
    if report.get("engine") != expected_engine:
        raise ValueError(f"{report_name} report has an unexpected engine")
    if report.get("unit") != "seconds":
        raise ValueError(f"{report_name} report must use seconds")
    iteration_count = report.get("iterationCount")
    if not isinstance(iteration_count, int) or iteration_count < minimum_iterations:
        raise ValueError(
            f"{report_name} report requires at least {minimum_iterations} iterations"
        )
    workloads = workload_map(report)
    for name in ("create_bodies", "edit_one_body"):
        if name not in workloads:
            raise ValueError(f"{report_name} report is missing workload {name}")
        validate_statistics(workloads[name], iteration_count, report_name)
    return workloads


def validate_rupa_telemetry(rupa, body_count):
    create = rupa["create_bodies"].get("telemetry")
    edit = rupa["edit_one_body"].get("telemetry")
    if create is None or edit is None:
        raise ValueError("Rupa Agent workloads require telemetry")
    expected_create = {
        "evaluationPassCount": 1,
        "historyEntryCount": 1,
        "totalFeatureCount": body_count * 2,
        "rebuiltFeatureCount": body_count * 2,
        "reusedFeatureCount": 0,
        "invalidatedFeatureCount": body_count * 2,
        "replayFallbackCount": 0,
        "tessellatedBodyCount": body_count,
        "reusedMeshCount": 0,
    }
    expected_edit = {
        "evaluationPassCount": 1,
        "historyEntryCount": 1,
        "totalFeatureCount": body_count * 2,
        "rebuiltFeatureCount": 1,
        "reusedFeatureCount": body_count * 2 - 1,
        "invalidatedFeatureCount": 1,
        "replayFallbackCount": 0,
        "tessellatedBodyCount": 1,
        "reusedMeshCount": body_count - 1,
    }
    for workload_name, telemetry, expected in (
        ("create_bodies", create, expected_create),
        ("edit_one_body", edit, expected_edit),
    ):
        for name, value in expected.items():
            if telemetry.get(name) != value:
                raise ValueError(
                    f"Rupa workload {workload_name} has invalid telemetry {name}"
                )


def make_gate(name, statistic, rupa, blender, maximum_ratio):
    rupa_value = rupa[name]["statistics"][statistic]
    blender_value = blender[name]["statistics"][statistic]
    ratio = rupa_value / blender_value if blender_value > 0.0 else float("inf")
    return {
        "workload": name,
        "statistic": statistic,
        "rupaSeconds": rupa_value,
        "blenderSeconds": blender_value,
        "ratio": ratio,
        "maximumRatio": maximum_ratio,
        "passed": ratio <= maximum_ratio,
    }


def main():
    options = parse_arguments()
    rupa_report = load_report(options.rupa_report)
    blender_report = load_report(options.blender_report)
    if options.minimum_iterations < 1:
        raise ValueError("minimum iterations must be positive")
    rupa = validate_report(
        rupa_report,
        "Rupa",
        "rupa",
        options.minimum_iterations,
    )
    blender = validate_report(
        blender_report,
        "Blender",
        "blender",
        options.minimum_iterations,
    )
    if rupa_report["bodyCount"] != blender_report["bodyCount"]:
        raise ValueError("benchmark reports use different body counts")
    validate_rupa_telemetry(rupa, rupa_report["bodyCount"])

    gates = []
    for name in ("create_bodies", "edit_one_body"):
        for statistic in ("median", "p95"):
            gates.append(make_gate(name, statistic, rupa, blender, options.maximum_ratio))
    result = {
        "schemaVersion": 1,
        "bodyCount": rupa_report["bodyCount"],
        "rupaIterationCount": rupa_report["iterationCount"],
        "blenderIterationCount": blender_report["iterationCount"],
        "maximumRatio": options.maximum_ratio,
        "equivalent": all(gate["passed"] for gate in gates),
        "gates": gates,
    }
    print(json.dumps(result, indent=2, sort_keys=True))
    if not result["equivalent"]:
        sys.exit(1)


if __name__ == "__main__":
    main()
