"""The CI workflow, and the SDK pin it reads.

`getting-started.md` calls `.fvmrc` the single source of truth for the SDK.
That is only true while CI actually reads it — a version typed into the
workflow as well is a second copy, and the one that goes stale is always the
one everybody's PR is built with.

The rest is about the gate itself: #23 asks for `make lint`, `make test` and
`verify_content.py`, and a workflow that quietly stopped running one of them
would look exactly like a green build.
"""

from __future__ import annotations

import json
import re
from pathlib import Path

import pytest
import yaml

REPO = Path(__file__).resolve().parents[2]
FVMRC = REPO / ".fvmrc"
WORKFLOW = REPO / ".github" / "workflows" / "ci.yml"
GETTING_STARTED = REPO / "docs" / "05-dev-guide" / "getting-started.md"


@pytest.fixture(scope="module")
def workflow() -> dict:
    return yaml.safe_load(WORKFLOW.read_text(encoding="utf-8"))


@pytest.fixture(scope="module")
def steps(workflow: dict) -> list[dict]:
    """Every step of every job, flattened."""
    return [step for job in workflow["jobs"].values() for step in job["steps"]]


@pytest.fixture(scope="module")
def commands(steps: list[dict]) -> str:
    return "\n".join(step["run"] for step in steps if "run" in step)


def test_the_sdk_pin_exists() -> None:
    assert FVMRC.is_file(), (
        "getting-started.md tells every developer to run `fvm install`, which "
        "reads .fvmrc. Without the file they each get whatever is on PATH."
    )
    assert json.loads(FVMRC.read_text(encoding="utf-8"))["flutter"]


def test_the_docs_name_the_pinned_version() -> None:
    """A version in prose that disagrees with the pin is worse than none."""
    pinned = json.loads(FVMRC.read_text(encoding="utf-8"))["flutter"]
    assert pinned in GETTING_STARTED.read_text(encoding="utf-8"), (
        f".fvmrc pins {pinned}, which getting-started.md does not mention. "
        f"One of the two is out of date."
    )


def test_ci_reads_the_pin_rather_than_repeating_it(
    commands: str, steps: list[dict]
) -> None:
    assert ".fvmrc" in commands, "the workflow does not read .fvmrc"

    pinned = json.loads(FVMRC.read_text(encoding="utf-8"))["flutter"]
    literal = re.compile(rf"['\"]?{re.escape(pinned)}['\"]?")
    for step in steps:
        rendered = yaml.safe_dump(step)
        if ".fvmrc" in rendered:
            continue
        assert not literal.search(rendered), (
            f"the workflow writes {pinned} out as well as reading .fvmrc:\n"
            f"{rendered}"
        )


def test_the_workflow_runs_the_three_gates(commands: str) -> None:
    for gate in ("make lint", "make test", "verify_content.py"):
        assert gate in commands, f"the workflow does not run `{gate}`"


def test_generated_code_is_rebuilt_before_it_is_linted(commands: str) -> None:
    """Generated code is git-ignored (ADR 17), so CI has to make it first.

    `dart analyze` on a tree with no `.g.dart` files reports hundreds of
    errors that say nothing about the change under review.
    """
    lines = [line.strip() for line in commands.splitlines()]
    gen = next(i for i, line in enumerate(lines) if line == "make gen")
    lint = next(i for i, line in enumerate(lines) if line == "make lint")
    test = next(i for i, line in enumerate(lines) if line == "make test")
    assert gen < lint < test


def test_it_runs_on_every_pull_request(workflow: dict) -> None:
    # PyYAML reads a bare `on:` key as the boolean True.
    triggers = workflow.get("on", workflow.get(True))
    assert triggers is not None and "pull_request" in triggers
    assert "main" in triggers["push"]["branches"]


def test_the_goldens_are_verified(commands: str, workflow: dict) -> None:
    """`app/test/golden/README.md`: "CI should run goldens-verify on a single
    fixed runner."

    `make test` excludes them, so without a job of their own the six committed
    PNGs are checked by nobody and testing.md's "reviewed as images in the PR"
    has nothing behind it.
    """
    assert "test/golden" in commands, "nothing runs the goldens"

    runners = {
        job["runs-on"]
        for job in workflow["jobs"].values()
        if "test/golden" in yaml.safe_dump(job)
    }
    assert runners == {"windows-latest"}, (
        f"the goldens were generated on Windows; on {runners} the diff would "
        f"be about the renderer, not the design"
    )


def test_the_pub_cache_is_not_keyed_on_the_sources(workflow: dict) -> None:
    """Hundreds of megabytes that only change when the lock file does.

    Keyed on the sources as well, every PR touching one Dart file saves a
    fresh copy and evicts the entries that would have been hits.
    """
    for job in workflow["jobs"].values():
        for step in job["steps"]:
            if step.get("with", {}).get("path", "").strip() != "~/.pub-cache":
                continue
            key = step["with"]["key"]
            assert "pubspec.lock" in key
            assert ".dart" not in key, f"the pub cache is keyed on sources: {key}"


def test_both_jobs_are_cached(workflow: dict) -> None:
    """#23 asks for pub and build_runner output to be cached."""
    cached = "\n".join(
        yaml.safe_dump(step)
        for job in workflow["jobs"].values()
        for step in job["steps"]
        if "cache" in yaml.safe_dump(step)
    )
    assert "~/.pub-cache" in cached
    assert "app/.dart_tool/build" in cached, "build_runner output is not cached"
    assert "cache: pip" in cached


def test_every_job_has_a_timeout(workflow: dict) -> None:
    """A hung job holds the queue until GitHub's six-hour default gives up."""
    for name, job in workflow["jobs"].items():
        assert "timeout-minutes" in job, f"{name} has no timeout"


def test_a_second_push_cancels_the_first(workflow: dict) -> None:
    assert workflow["concurrency"]["cancel-in-progress"] is True
