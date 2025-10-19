#!/usr/bin/env python3
"""
Harvest golden fixtures from the Python Codex SDK.

The script loads scenario modules from the Python repository, executes their
`record(output_path: pathlib.Path, *, codex_path: Optional[pathlib.Path])`
function, and writes JSONL transcripts into `integration/fixtures/python`.

Usage:
    python3 scripts/harvest_python_fixtures.py \\
        --python-sdk ../openai-agents-python \\
        --output integration/fixtures/python
"""

from __future__ import annotations

import argparse
import importlib
import os
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable, List, Optional


@dataclass(frozen=True)
class Scenario:
    name: str
    module: str
    function: str = "record"
    description: str = ""


SCENARIOS: List[Scenario] = [
    Scenario(
        name="thread_basic",
        module="harvest_scenarios.thread_basic",
        description="Simple thread start + single turn execution.",
    ),
    Scenario(
        name="thread_with_tool_retry",
        module="harvest_scenarios.thread_with_tool_retry",
        description="Thread that exercises tool invocation and auto-run retry loop.",
    ),
    Scenario(
        name="structured_output_success",
        module="harvest_scenarios.structured_output_success",
        description="Structured output with valid JSON payload.",
    ),
    Scenario(
        name="sandbox_approval_denied",
        module="harvest_scenarios.sandbox_approval_denied",
        description="Approval workflow where a command is denied.",
    ),
]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--python-sdk",
        type=Path,
        default=os.environ.get("CODEX_PYTHON_SDK_PATH"),
        help="Path to the openai-agents-python checkout (default: $CODEX_PYTHON_SDK_PATH).",
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=Path("integration/fixtures/python"),
        help="Directory where JSONL fixtures will be written.",
    )
    parser.add_argument(
        "--codex-path",
        type=Path,
        default=None,
        help="Optional path to codex-rs binary to force the Python SDK to use.",
    )
    parser.add_argument(
        "--scenario",
        dest="scenarios",
        action="append",
        default=[],
        help="Scenario name to run (may be repeated). Runs all when omitted.",
    )
    return parser.parse_args()


def select_scenarios(requested: Iterable[str]) -> List[Scenario]:
    if not requested:
        return SCENARIOS

    requested = list(requested)
    lookup = {s.name: s for s in SCENARIOS}
    unknown = [name for name in requested if name not in lookup]
    if unknown:
        raise SystemExit(f"Unknown scenario(s): {', '.join(unknown)}")

    return [lookup[name] for name in requested]


def ensure_python_path(python_sdk: Path) -> None:
    if not python_sdk:
        raise SystemExit(
            "Path to the Python SDK is required. Pass --python-sdk or set CODEX_PYTHON_SDK_PATH."
        )

    if not python_sdk.exists():
        raise SystemExit(f"Python SDK path does not exist: {python_sdk}")

    sys.path.insert(0, str(python_sdk.resolve()))


def run_scenario(
    scenario: Scenario, output_dir: Path, codex_path: Optional[Path]
) -> None:
    module = importlib.import_module(scenario.module)
    handler = getattr(module, scenario.function, None)
    if handler is None:
        raise SystemExit(
            f"Scenario {scenario.name} expected function "
            f"{scenario.function} in module {scenario.module}"
        )

    output_dir.mkdir(parents=True, exist_ok=True)
    output_path = output_dir / f"{scenario.name}.jsonl"
    output_path.parent.mkdir(parents=True, exist_ok=True)

    kwargs = {}
    if codex_path:
        kwargs["codex_path"] = codex_path

    print(f"[harvest] running {scenario.name} -> {output_path}")
    handler(output_path=output_path, **kwargs)


def main() -> None:
    args = parse_args()
    ensure_python_path(args.python_sdk)

    output_dir = args.output.resolve()
    scenarios = select_scenarios(args.scenarios)

    for scenario in scenarios:
        run_scenario(scenario, output_dir, args.codex_path)

    print("[harvest] completed")


if __name__ == "__main__":
    main()
