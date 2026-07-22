#!/usr/bin/env python3

import json
import subprocess
import sys
from pathlib import Path


def run_git(repository: Path, *arguments: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["git", "-C", str(repository), *arguments],
        check=False,
        capture_output=True,
        text=True,
    )


def main() -> int:
    workspace = Path(__file__).resolve().parent.parent
    manifest_path = workspace / "P0_INTEGRATION_BASELINE.json"

    with manifest_path.open(encoding="utf-8") as manifest_file:
        manifest = json.load(manifest_file)

    failures: list[str] = []
    for requirement in manifest["repositories"]:
        name = requirement["name"]
        repository = (workspace / requirement["path"]).resolve()
        if not repository.is_dir():
            failures.append(f"{name}: repository path is missing: {repository}")
            continue

        head_result = run_git(repository, "rev-parse", "HEAD")
        if head_result.returncode != 0:
            failures.append(f"{name}: cannot resolve HEAD: {head_result.stderr.strip()}")
            continue

        actual_revision = head_result.stdout.strip()
        expected_revision = requirement["revision"]
        policy = requirement["revisionPolicy"]

        if policy == "exact":
            if actual_revision != expected_revision:
                failures.append(
                    f"{name}: expected exact revision {expected_revision}, found {actual_revision}"
                )
        elif policy == "ancestor":
            ancestor_result = run_git(
                repository,
                "merge-base",
                "--is-ancestor",
                expected_revision,
                actual_revision,
            )
            if ancestor_result.returncode != 0:
                failures.append(
                    f"{name}: revision {actual_revision} does not contain baseline {expected_revision}"
                )
        else:
            failures.append(f"{name}: unsupported revision policy {policy}")

        if requirement["requireClean"]:
            status_result = run_git(repository, "status", "--porcelain")
            if status_result.returncode != 0:
                failures.append(f"{name}: cannot inspect worktree status")
            elif status_result.stdout.strip():
                failures.append(f"{name}: worktree must be clean for baseline verification")

    if failures:
        for failure in failures:
            print(f"ERROR: {failure}", file=sys.stderr)
        return 1

    print(f"P0 integration baseline verified: {manifest['baselineID']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
