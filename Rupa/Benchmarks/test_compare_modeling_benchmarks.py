import copy
import unittest

import compare_modeling_benchmarks as benchmark


class ModelingBenchmarkValidationTests(unittest.TestCase):
    def test_valid_report_recomputes_statistics_and_accepts_telemetry(self):
        rupa = self.make_report("rupa")
        workloads = benchmark.validate_report(rupa, "Rupa", "rupa", 4)

        benchmark.validate_rupa_telemetry(workloads, rupa["bodyCount"])

    def test_report_rejects_a_forged_percentile(self):
        report = self.make_report("blender")
        report["workloads"][0]["statistics"]["p95"] = 0.0

        with self.assertRaises(ValueError):
            benchmark.validate_report(report, "Blender", "blender", 4)

    def test_rupa_report_rejects_nonincremental_edit_telemetry(self):
        report = self.make_report("rupa")
        workloads = benchmark.workload_map(report)
        workloads["edit_one_body"]["telemetry"]["rebuiltFeatureCount"] = 2

        with self.assertRaises(ValueError):
            benchmark.validate_rupa_telemetry(workloads, report["bodyCount"])

    def make_report(self, engine):
        body_count = 2
        samples = [0.001, 0.002, 0.003, 0.004]
        statistics = {
            "minimum": 0.001,
            "median": 0.002,
            "p95": 0.004,
            "maximum": 0.004,
            "samples": samples,
        }
        create_telemetry = {
            "evaluationPassCount": 1,
            "historyEntryCount": 1,
            "totalFeatureCount": 4,
            "rebuiltFeatureCount": 4,
            "reusedFeatureCount": 0,
            "invalidatedFeatureCount": 4,
            "replayFallbackCount": 0,
            "tessellatedBodyCount": 2,
            "reusedMeshCount": 0,
        }
        edit_telemetry = {
            "evaluationPassCount": 1,
            "historyEntryCount": 1,
            "totalFeatureCount": 4,
            "rebuiltFeatureCount": 1,
            "reusedFeatureCount": 3,
            "invalidatedFeatureCount": 1,
            "replayFallbackCount": 0,
            "tessellatedBodyCount": 1,
            "reusedMeshCount": 1,
        }
        return {
            "schemaVersion": 2,
            "engine": engine,
            "unit": "seconds",
            "bodyCount": body_count,
            "iterationCount": 4,
            "workloads": [
                {
                    "name": "create_bodies",
                    "statistics": copy.deepcopy(statistics),
                    "telemetry": create_telemetry if engine == "rupa" else None,
                },
                {
                    "name": "edit_one_body",
                    "statistics": copy.deepcopy(statistics),
                    "telemetry": edit_telemetry if engine == "rupa" else None,
                },
            ],
        }


if __name__ == "__main__":
    unittest.main()
